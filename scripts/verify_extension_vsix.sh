#!/usr/bin/env bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# Verifies the Marketplace VSIX package and required web/WASM runtime assets.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VSIX="${1:-}"

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

if [[ -z "$VSIX" ]]; then
  archives=("$ROOT"/build/rohd-wave-viewer-*.vsix)
  [[ "${#archives[@]}" == 1 ]] ||
    fail 'Expected exactly one VSIX; run make vsix first'
  VSIX="${archives[0]}"
fi

[[ -f "$VSIX" ]] || fail "VSIX not found: $VSIX"

entries="$(unzip -Z1 "$VSIX")"
require_entry() {
  grep -Fxq "$1" <<<"$entries" ||
    fail "VSIX is missing required entry: $1"
}

for entry in \
  '[Content_Types].xml' \
  extension.vsixmanifest \
  extension/package.json \
  extension/readme.md \
  extension/changelog.md \
  extension/LICENSE.txt \
  extension/extension.js \
  extension/icon.png \
  extension/flutter_web/index.html \
  extension/flutter_web/flutter_bootstrap.js \
  extension/flutter_web/main.dart.wasm \
  extension/flutter_web/pkg/wellen_bridge.js \
  extension/flutter_web/pkg/wellen_bridge_bg.wasm; do
  require_entry "$entry"
done

source_version="$(
  node -p 'require(process.argv[1]).version' "$ROOT/vscode-extension/package.json"
)"
pubspec_version="$(awk '/^version:/ { print $2; exit }' "$ROOT/pubspec.yaml")"
lock_version="$(
  node -p 'require(process.argv[1]).version' "$ROOT/vscode-extension/package-lock.json"
)"
lock_root_version="$(
  node -p 'require(process.argv[1]).packages[""].version' "$ROOT/vscode-extension/package-lock.json"
)"
source_publisher="$(
  node -p 'require(process.argv[1]).publisher' "$ROOT/vscode-extension/package.json"
)"
source_name="$(
  node -p 'require(process.argv[1]).name' "$ROOT/vscode-extension/package.json"
)"
package_version="$(
  unzip -p "$VSIX" extension/package.json |
    node -e 'let input = ""; process.stdin.on("data", c => input += c); process.stdin.on("end", () => console.log(JSON.parse(input).version));'
)"
package_publisher="$(
  unzip -p "$VSIX" extension/package.json |
    node -e 'let input = ""; process.stdin.on("data", c => input += c); process.stdin.on("end", () => console.log(JSON.parse(input).publisher));'
)"

[[ "$source_version" == "$pubspec_version" ]] ||
  fail "package.json version $source_version does not match pubspec $pubspec_version"
[[ "$lock_version" == "$pubspec_version" ]] ||
  fail "package-lock.json version $lock_version does not match pubspec $pubspec_version"
[[ "$lock_root_version" == "$pubspec_version" ]] ||
  fail "package-lock.json root version $lock_root_version does not match pubspec $pubspec_version"
[[ "$package_version" == "$source_version" ]] ||
  fail "VSIX version $package_version does not match package.json $source_version"
[[ "$package_publisher" == "$source_publisher" ]] ||
  fail "VSIX publisher $package_publisher does not match package.json $source_publisher"
[[ "$package_publisher" == "intel-corporation" ]] ||
  fail "VSIX publisher must be intel-corporation, got $package_publisher"
manifest="$(unzip -p "$VSIX" extension.vsixmanifest)"
grep -Fq "Id=\"${source_name}\"" <<<"$manifest" ||
  fail "VSIX extension name does not match $source_name"
grep -Fq "Publisher=\"${package_publisher}\"" <<<"$manifest" ||
  fail "VSIX publisher identity does not match $package_publisher"
grep -Fq "Version=\"${package_version}\"" <<<"$manifest" ||
  fail "VSIX manifest version does not match $package_version"

printf 'Verified Marketplace VSIX: %s (%s.rohd-wave-viewer %s, Flutter and Rust WASM present).\n' \
  "${VSIX#$ROOT/}" "$package_publisher" "$package_version"
