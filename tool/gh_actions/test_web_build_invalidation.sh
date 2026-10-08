#!/bin/bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# Verifies that reusable Flutter web output is invalidated by bundled assets.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
export ROHD_LOCAL_PATH="$work_dir/rohd"

mkdir -p \
  "$work_dir/assets/help" \
  "$work_dir/build/web" \
  "$work_dir/lib" \
  "$work_dir/packages/dart_wellen/lib/src/rust" \
  "$work_dir/rust/wellen_bridge/src" \
  "$work_dir/scripts" \
  "$work_dir/security" \
  "$work_dir/vscode-extension" \
  "$work_dir/web/pkg"

cp "$repo_root/Makefile" "$work_dir/Makefile"
printf 'help\n' >"$work_dir/assets/help/wave_viewer_help.md"
printf 'void main() {}\n' >"$work_dir/lib/main_web.dart"
printf 'version: 9.9.9\n' >"$work_dir/pubspec.yaml"
cat >"$work_dir/vscode-extension/package.json" <<'JSON'
{
  "name": "rohd-wave-viewer",
  "version": "0.1.0"
}
JSON

extension_version="$(
  make --no-print-directory -C "$work_dir" -pn 2>/dev/null |
    sed -n 's/^PKG_VERSION := //p' |
    head -n 1
)"
if [[ "$extension_version" != '0.1.0' ]]; then
  echo "error: extension version should come from package.json; found $extension_version." >&2
  exit 1
fi

touch \
  "$work_dir/scripts/fix_bootstrap.py" \
  "$work_dir/scripts/build_dart_wellen_bridge.sh" \
  "$work_dir/scripts/patch_wasm_binary.sh" \
  "$work_dir/scripts/patch_wasm_js.sh" \
  "$work_dir/scripts/verify_flutter_native_dependencies.sh" \
  "$work_dir/packages/dart_wellen/flutter_rust_bridge.yaml" \
  "$work_dir/packages/dart_wellen/lib/src/rust/api.dart" \
  "$work_dir/packages/dart_wellen/lib/src/rust/frb_generated.dart" \
  "$work_dir/packages/dart_wellen/lib/src/rust/frb_generated.io.dart" \
  "$work_dir/packages/dart_wellen/lib/src/rust/frb_generated.web.dart" \
  "$work_dir/rust/wellen_bridge/build_wasm.sh" \
  "$work_dir/rust/wellen_bridge/Cargo.toml" \
  "$work_dir/rust/wellen_bridge/src/api.rs" \
  "$work_dir/rust/wellen_bridge/src/frb_generated.rs" \
  "$work_dir/security/native-dependency-exceptions.json" \
  "$work_dir/web/index.html" \
  "$work_dir/web/pkg/wellen_bridge.js" \
  "$work_dir/web/pkg/wellen_bridge_bg.wasm"

# Establish deterministic ordering without sleeping or touching the checkout.
find "$work_dir" -exec touch -t 200001010000 {} +
touch "$work_dir/build/web/index.html"
web_build_config() {
  local build_args="$1"
  local key
  key="$(
    printf '%s\n' release 1 "$build_args" |
      sha256sum |
      cut -c1-16
  )"
  printf '%s/build/.rohd-wave-web-build-config-%s' "$work_dir" "$key"
}

local_config="$(web_build_config '')"
pages_args='--base-href=/rohd-wave-viewer/'
pages_config="$(web_build_config "$pages_args")"
printf 'mode=release\nwasm=1\nargs=\n' >"$local_config"
touch -t 200001010001 \
  "$work_dir/build/web/index.html" \
  "$local_config"

if ! make --no-print-directory -C "$work_dir" -q web; then
  echo "error: unchanged Flutter web inputs should reuse existing output." >&2
  make --no-print-directory -C "$work_dir" -n web >&2
  exit 1
fi

reuse_output="$(make --no-print-directory -C "$work_dir" extension-web)"
if [[ "$reuse_output" != *"Reusing existing Flutter release/WASM web build..."* ]] ||
  [[ "$reuse_output" == *"Building Flutter web"* ]]; then
  echo "error: extension packaging should reuse unchanged Flutter web output." >&2
  printf '%s\n' "$reuse_output" >&2
  exit 1
fi

set +e
make --no-print-directory -C "$work_dir" -q web \
  FLUTTER_WEB_BUILD_ARGS="$pages_args"
status=$?
set -e
if [[ "$status" -ne 1 ]]; then
  echo "error: changing to the Pages base href should invalidate output." >&2
  exit 1
fi

rm -f "$local_config"
printf 'mode=release\nwasm=1\nargs=%s\n' "$pages_args" >"$pages_config"
touch -t 200001010002 \
  "$work_dir/build/web/index.html" \
  "$pages_config"
if ! make --no-print-directory -C "$work_dir" -q web \
  FLUTTER_WEB_BUILD_ARGS="$pages_args"; then
  echo "error: unchanged Pages build arguments should reuse output." >&2
  exit 1
fi

set +e
make --no-print-directory -C "$work_dir" -q web
status=$?
set -e
if [[ "$status" -ne 1 ]]; then
  echo "error: changing from the Pages base href should invalidate output." >&2
  exit 1
fi

rm -f "$pages_config"
printf 'mode=release\nwasm=1\nargs=\n' >"$local_config"
touch -t 200001010003 \
  "$work_dir/build/web/index.html" \
  "$local_config"

touch -t 200001010004 "$work_dir/assets/help/wave_viewer_help.md"
set +e
make --no-print-directory -C "$work_dir" -q web
status=$?
set -e
if [[ "$status" -ne 1 ]]; then
  echo "error: a bundled asset edit should invalidate Flutter web output." >&2
  exit 1
fi

touch -t 200001010005 \
  "$work_dir/build/web/index.html" \
  "$local_config"
if ! make --no-print-directory -C "$work_dir" -q web; then
  echo "error: refreshed Flutter web output should be reusable." >&2
  exit 1
fi

echo "Flutter web build invalidation checks passed."
