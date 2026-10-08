#!/usr/bin/env bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# test_unlocked_dart_wellen_consumer.sh
# Verifies dart_wellen initialization with freshly resolved dependencies.
#
# 2026 October 07
# Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
dart_bin="${DART:-dart}"
temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/dart-wellen-consumer.XXXXXXXX")"
trap 'rm -rf "$temp_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$temp_dir/dart_wellen" "$temp_dir/consumer/bin"
tar -C "$repo_root/packages/dart_wellen" \
  --exclude=.dart_tool --exclude=build --exclude=pubspec.lock \
  -cf - . | tar -C "$temp_dir/dart_wellen" -xf -

cat > "$temp_dir/pubspec.yaml" <<'YAML'
name: dart_wellen_consumer_workspace
publish_to: none
environment:
  sdk: '>=3.6.0 <4.0.0'
workspace:
  - dart_wellen
  - consumer
YAML

cat > "$temp_dir/consumer/pubspec.yaml" <<'YAML'
name: dart_wellen_unlocked_consumer
publish_to: none
resolution: workspace
environment:
  sdk: '>=3.6.0 <4.0.0'
dependencies:
  dart_wellen: 0.1.0
YAML

cat > "$temp_dir/consumer/bin/initialize.dart" <<'DART'
// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// initialize.dart
// Exercises dart_wellen initialization from an unlocked consumer.
//
// 2026 October 07
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:dart_wellen/dart_wellen.dart';

Future<void> main() => WellenReader.init();
DART

cd "$temp_dir"
"$dart_bin" pub upgrade

expected_version="$(
  sed -n "s/.*String get codegenVersion => '\([^']*\)';/\1/p" \
    dart_wellen/lib/src/rust/frb_generated.dart
)"
if [[ -z "$expected_version" || "$expected_version" == *$'\n'* ]]; then
  echo 'error: could not determine one generated Flutter Rust Bridge version.' >&2
  exit 1
fi

resolved_versions="$(
  "$dart_bin" pub deps --style=compact |
    awk '$2 == "flutter_rust_bridge" { print $3 }' |
    sort -u
)"
if [[ "$resolved_versions" != "$expected_version" ]]; then
  echo "error: generated Flutter Rust Bridge version is $expected_version," >&2
  echo "but the unlocked consumer resolved: ${resolved_versions:-none}" >&2
  exit 1
fi

set +e
initialization_output="$(
  "$dart_bin" run consumer/bin/initialize.dart 2>&1
)"
initialization_status=$?
set -e

if grep -Fq 'codegen version' <<<"$initialization_output" ||
    grep -Fq 'runtime version' <<<"$initialization_output"; then
  echo "$initialization_output" >&2
  echo 'error: Flutter Rust Bridge generated/runtime version mismatch.' >&2
  exit 1
fi

if [[ "$initialization_status" -eq 0 ]]; then
  echo "Unlocked consumer initialized with Flutter Rust Bridge $expected_version."
elif grep -Fq 'Failed to load dynamic library' <<<"$initialization_output" &&
    grep -Fq 'wellen_bridge' <<<"$initialization_output"; then
  echo "Unlocked consumer passed the version check with Flutter Rust Bridge $expected_version."
  echo 'Native library loading was not expected in the isolated consumer.'
else
  echo "$initialization_output" >&2
  echo 'error: unlocked consumer initialization failed unexpectedly.' >&2
  exit "$initialization_status"
fi
