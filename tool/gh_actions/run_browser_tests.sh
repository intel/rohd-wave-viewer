#!/usr/bin/env bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# run_browser_tests.sh
# Runs dart_wellen's Rust/WASM integration test through both Dart web compilers.
#
# 2026 October 05
# Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
package_root="$repo_root/packages/dart_wellen"
browser_assets="$package_root/test/browser_assets"
wasm_pkg="$repo_root/web/pkg"
fixture="$package_root/test/fixtures/xz_transitions.vcd"

bash "$repo_root/scripts/verify_flutter_version.sh"

for asset in wellen_bridge.js wellen_bridge_bg.wasm; do
  if [[ ! -s "$wasm_pkg/$asset" ]]; then
    echo "Missing browser WASM asset: $wasm_pkg/$asset" >&2
    echo 'Run make wasm before running browser tests.' >&2
    exit 2
  fi
done
if [[ ! -s "$fixture" ]]; then
  echo "Missing tracked browser test fixture: $fixture" >&2
  exit 2
fi

chrome_executable="${CHROME_EXECUTABLE:-}"
if [[ -z "$chrome_executable" ]]; then
  for candidate in google-chrome chromium chromium-browser; do
    if command -v "$candidate" >/dev/null 2>&1; then
      chrome_executable="$(command -v "$candidate")"
      break
    fi
  done
fi
if [[ -z "$chrome_executable" || ! -x "$chrome_executable" ]]; then
  echo 'Chrome or Chromium is required for browser tests.' >&2
  exit 2
fi
export CHROME_EXECUTABLE="$chrome_executable"
browser_platform="${BROWSER_TEST_PLATFORM:-chrome}"

cleanup() {
  rm -rf "$browser_assets"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

cleanup
mkdir -p "$browser_assets"
cp "$wasm_pkg/wellen_bridge.js" "$wasm_pkg/wellen_bridge_bg.wasm" \
  "$browser_assets/"

flutter_bin="$(readlink -f "$(command -v flutter)")"
dart_bin="$(dirname "$flutter_bin")/dart"

cd "$package_root"
for compiler in dart2js dart2wasm; do
  echo "Running browser/WASM integration test with $compiler..."
  "$dart_bin" run test:test \
    --platform "$browser_platform" \
    --compiler "$compiler" \
    --concurrency 1 \
    test/web_wasm_integration_test.dart
done
