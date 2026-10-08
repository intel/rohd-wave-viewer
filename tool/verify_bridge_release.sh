#!/usr/bin/env bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# verify_bridge_release.sh
# Verifies the generated, native, and WebAssembly Wellen bridge release set.
#
# 2026 October 07
# Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dart_generated="$repo_root/packages/dart_wellen/lib/src/rust/frb_generated.dart"
rust_generated="$repo_root/rust/wellen_bridge/src/frb_generated.rs"
native_artifact="$repo_root/rust/wellen_bridge/target/release/libwellen_bridge.so"
wasm_js="$repo_root/web/pkg/wellen_bridge.js"
wasm_artifact="$repo_root/web/pkg/wellen_bridge_bg.wasm"

fail() {
  echo "Bridge release validation: $*" >&2
  exit 1
}

require_file() {
  [[ -s "$1" ]] || fail "missing or empty artifact: $1"
}

single_value() {
  local label="$1"
  local value="$2"
  [[ -n "$value" ]] || fail "could not read $label"
  [[ "$value" != *$'\n'* ]] || fail "found multiple values for $label"
  printf '%s' "$value"
}

pubspec_bridge_version() {
  awk '$1 == "flutter_rust_bridge:" {print $2}' "$1" |
    tr -d "'\""
}

cargo_lock_version() {
  local package="$1"
  awk -v package="$package" '
    $0 == "name = \"" package "\"" { found = 1; next }
    found && /^version = / {
      gsub(/"/, "", $3)
      print $3
      exit
    }
  ' "$repo_root/rust/wellen_bridge/Cargo.lock"
}

require_file "$dart_generated"
require_file "$rust_generated"
require_file "$native_artifact"
require_file "$wasm_js"
require_file "$wasm_artifact"

package_runtime="$(
  single_value \
    'dart_wellen Flutter Rust Bridge constraint' \
    "$(pubspec_bridge_version "$repo_root/packages/dart_wellen/pubspec.yaml")"
)"
root_runtime="$(
  single_value \
    'rohd_wave_viewer Flutter Rust Bridge constraint' \
    "$(pubspec_bridge_version "$repo_root/pubspec.yaml")"
)"
pub_lock_runtime="$(
  single_value \
    'Pub lock Flutter Rust Bridge version' \
    "$(
      awk '
        /^  flutter_rust_bridge:$/ { found = 1; next }
        found && /^    version: / {
          gsub(/"/, "", $2)
          print $2
          exit
        }
      ' "$repo_root/pubspec.lock"
    )"
)"
cargo_runtime="$(
  single_value \
    'Cargo Flutter Rust Bridge constraint' \
    "$(
      sed -n \
        's/^flutter_rust_bridge = "=\([^"]*\)"$/\1/p' \
        "$repo_root/rust/wellen_bridge/Cargo.toml"
    )"
)"
cargo_codegen="$(
  single_value \
    'Cargo Flutter Rust Bridge codegen constraint' \
    "$(
      sed -n \
        's/^flutter_rust_bridge_codegen = "=\([^"]*\)"$/\1/p' \
        "$repo_root/rust/wellen_bridge/Cargo.toml"
    )"
)"
cargo_lock_runtime="$(
  single_value \
    'Cargo lock Flutter Rust Bridge version' \
    "$(cargo_lock_version flutter_rust_bridge)"
)"
cargo_lock_codegen="$(
  single_value \
    'Cargo lock Flutter Rust Bridge codegen version' \
    "$(cargo_lock_version flutter_rust_bridge_codegen)"
)"
dart_codegen="$(
  single_value \
    'generated Dart Flutter Rust Bridge version' \
    "$(
      sed -n \
        "s/.*String get codegenVersion => '\([^']*\)';/\1/p" \
        "$dart_generated"
    )"
)"
rust_codegen="$(
  single_value \
    'generated Rust Flutter Rust Bridge version' \
    "$(
      sed -n \
        's/.*FLUTTER_RUST_BRIDGE_CODEGEN_VERSION: &str = "\([^"]*\)";/\1/p' \
        "$rust_generated"
    )"
)"

expected_version="$package_runtime"
for version_entry in \
  "root manifest:$root_runtime" \
  "Pub lock:$pub_lock_runtime" \
  "Cargo runtime:$cargo_runtime" \
  "Cargo codegen:$cargo_codegen" \
  "Cargo lock runtime:$cargo_lock_runtime" \
  "Cargo lock codegen:$cargo_lock_codegen" \
  "generated Dart:$dart_codegen" \
  "generated Rust:$rust_codegen"; do
  label="${version_entry%%:*}"
  version="${version_entry#*:}"
  [[ "$version" == "$expected_version" ]] ||
    fail "$label uses $version; expected $expected_version"
done

dart_content_hash="$(
  single_value \
    'generated Dart content hash' \
    "$(
      sed -n \
        's/.*int get rustContentHash => \(-\{0,1\}[0-9][0-9]*\);/\1/p' \
        "$dart_generated"
    )"
)"
rust_content_hash="$(
  single_value \
    'generated Rust content hash' \
    "$(
      sed -n \
        's/.*FLUTTER_RUST_BRIDGE_CODEGEN_CONTENT_HASH: i32 = \(-\{0,1\}[0-9][0-9]*\);/\1/p' \
        "$rust_generated"
    )"
)"
[[ "$rust_content_hash" == "$dart_content_hash" ]] ||
  fail "generated content hashes differ: Dart=$dart_content_hash Rust=$rust_content_hash"

native_content_hash="$(
  python3 - "$native_artifact" <<'PY'
import ctypes
import sys

library = ctypes.CDLL(sys.argv[1])
content_hash = library.frb_get_rust_content_hash
content_hash.argtypes = []
content_hash.restype = ctypes.c_int32
print(content_hash())
PY
)"
[[ "$native_content_hash" == "$dart_content_hash" ]] ||
  fail "native content hash is $native_content_hash; expected $dart_content_hash"

wasm_magic="$(od -An -t x1 -N4 "$wasm_artifact" | tr -d ' \n')"
[[ "$wasm_magic" == '0061736d' ]] ||
  fail "WebAssembly artifact has invalid magic bytes: $wasm_magic"

wasm_content_hash="$(
  node - "$wasm_js" "$wasm_artifact" <<'NODE'
const fs = require('fs');
const vm = require('vm');

const jsPath = process.argv[2];
const wasmPath = process.argv[3];
const context = vm.createContext({
  console,
  TextDecoder,
  TextEncoder,
  WebAssembly,
});
const source = fs.readFileSync(jsPath, 'utf8');
const bindgen = vm.runInContext(
  `(function() {\n${source}\nreturn wasm_bindgen;\n})()`,
  context,
  {filename: jsPath},
);
context.bindgen = bindgen;
context.wasmModule = new WebAssembly.Module(fs.readFileSync(wasmPath));
vm.runInContext('bindgen.initSync({module: wasmModule})', context);
process.stdout.write(String(bindgen.frb_get_rust_content_hash()));
NODE
)"
[[ "$wasm_content_hash" == "$dart_content_hash" ]] ||
  fail "WebAssembly content hash is $wasm_content_hash; expected $dart_content_hash"

native_symbols="$(nm -D "$native_artifact")"
grep -Fq \
  'frbgen_dart_wellen_wire__crate__api__load_waveform_from_bytes' \
  <<<"$native_symbols" ||
  fail 'native artifact is missing the waveform byte-loader symbol'
wasm_exports="$(wasm-objdump -x "$wasm_artifact")"
grep -Fq \
  '"wire__crate__api__load_waveform_from_bytes"' \
  <<<"$wasm_exports" ||
  fail 'WebAssembly artifact is missing the waveform byte-loader export'

echo "Bridge release set verified:"
echo "  Flutter Rust Bridge: $expected_version"
echo "  Generated content hash: $dart_content_hash"
echo "  Native SHA-256: $(sha256sum "$native_artifact" | awk '{print $1}')"
echo "  WebAssembly SHA-256: $(sha256sum "$wasm_artifact" | awk '{print $1}')"
