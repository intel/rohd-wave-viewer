#!/usr/bin/env bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# verify_flutter_version.sh
# Verifies that Flutter and its Dart SDK meet the repository's minimum versions.
#
# 2026 August
# Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

set -euo pipefail

minimum_flutter_version='3.47.0'
minimum_dart_version='3.12.0'

version_is_at_least() {
  local minimum="$1"
  local actual="$2"
  [[ "$(printf '%s\n%s\n' "$minimum" "$actual" | sort -V | head -n1)" == "$minimum" ]]
}

if ! command -v flutter >/dev/null 2>&1; then
  echo 'error: flutter must be available on PATH.' >&2
  exit 2
fi

flutter_version="$(flutter --version | sed -n '1s/^Flutter \([^ ]*\).*/\1/p')"
if [[ -z "$flutter_version" ]]; then
  echo 'error: could not determine the Flutter version on PATH.' >&2
  exit 2
fi

if ! version_is_at_least "$minimum_flutter_version" "$flutter_version"; then
  echo "error: Flutter $minimum_flutter_version or newer is required; found $flutter_version." >&2
  exit 1
fi

if ! command -v dart >/dev/null 2>&1; then
  echo 'error: the Dart SDK bundled with Flutter must be available on PATH.' >&2
  exit 2
fi

dart_version="$(dart --version 2>&1 | sed -n 's/^Dart SDK version: \([^ ]*\).*/\1/p')"
if [[ -z "$dart_version" ]]; then
  echo 'error: could not determine the Dart SDK version on PATH.' >&2
  exit 2
fi

if ! version_is_at_least "$minimum_dart_version" "$dart_version"; then
  echo "error: Dart $minimum_dart_version or newer is required; found $dart_version." >&2
  exit 1
fi

echo "Using Flutter $flutter_version with Dart $dart_version."
