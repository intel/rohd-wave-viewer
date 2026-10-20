#!/usr/bin/env bash
# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# Stage the embedding Pub package without its separately published bridge.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
destination="${1:-$repo_root/build/pub/rohd_wave_viewer}"
if [[ -e "$destination" ]]; then
  echo "error: publication staging destination already exists: $destination" >&2
  echo "Use a new directory to avoid publishing stale files." >&2
  exit 1
fi
mkdir -p "$destination"
destination="$(cd "$destination" && pwd)"

tar -C "$repo_root" \
  --exclude=.git \
  --exclude=.dart_tool \
  --exclude=.flutter-plugins \
  --exclude=.flutter-plugins-dependencies \
  --exclude=build \
  --exclude=coverage \
  --exclude=node_modules \
  --exclude=packages \
  --exclude=pubspec.lock \
  --exclude=pubspec_overrides.yaml \
  --exclude='pubspec_overrides.yaml.disabled*' \
  --exclude=rust/wellen_bridge/target \
  --exclude=web/pkg \
  --exclude="./${destination#"$repo_root"/}" \
  -cf - . | tar -C "$destination" -xf -

awk '
  /^workspace:[[:space:]]*$/ { skipping = 1; next }
  skipping && /^[^[:space:]#]/ { skipping = 0 }
  !skipping { print }
' "$destination/pubspec.yaml" > "$destination/pubspec.yaml.hosted"
mv "$destination/pubspec.yaml.hosted" "$destination/pubspec.yaml"

echo "Embedding package staged without bridge artifacts: $destination"
