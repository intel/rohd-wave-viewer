#!/usr/bin/env bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# build_dart_wellen_bridge.sh
# Builds the Dart and Flutter interface for the Wellen bridge.
#
# 2026 January
# Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

set -euo pipefail
# Build Dart/Flutter interface for wellen_bridge (FRB codegen + Dart artifacts)
# Generates Dart bindings and frb_generated.rs from Rust code.
# Works for both Linux and web builds. Assumes Rust toolchain and tools (flutter_rust_bridge_codegen, libclang) are pre-installed.
# Does not build Rust itself; use `make rust-native` or `make wasm` for that.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "[build-dart-wellen] Building Dart interface for wellen_bridge..."

# Set up Rust environment
source "$ROOT_DIR/scripts/setup_rust_env.sh"

# Try to find libclang for ffigen
find_libclang() {
    if command -v ldconfig >/dev/null 2>&1; then
        ldconfig -p 2>/dev/null | awk '/libclang\.so/ {print $NF}' | head -n1
    fi
    return 0
}

_libclang=$(find_libclang)
if [ -z "$_libclang" ]; then
    _libclang=$(find /usr/lib /usr/lib64 /usr/lib/x86_64-linux-gnu /usr/local/lib /usr/lib/llvm-* -name 'libclang.so*' -print -quit 2>/dev/null || true)
fi
if [ -n "$_libclang" ]; then
    export LIBCLANG_PATH="$(dirname "$_libclang")"
    echo "[build-dart-wellen] Found libclang: $_libclang"
    echo "[build-dart-wellen] Setting LIBCLANG_PATH=$LIBCLANG_PATH"
else
    echo "" >&2
    echo "ERROR: libclang not found. This is required for ffigen to generate Dart bindings." >&2
    echo "" >&2
    echo "Please install the required build tools by running:" >&2
    echo "  bash tool/gh_actions/install_build_tools.sh" >&2
    echo "" >&2
    exit 1
fi

# Ensure flutter_rust_bridge_codegen is installed
if ! command -v flutter_rust_bridge_codegen >/dev/null 2>&1; then
    echo "[build-dart-wellen] ERROR: flutter_rust_bridge_codegen not found."
    echo "Please install: cargo install flutter_rust_bridge_codegen --version 2.7.0 --locked"
    exit 1
fi

ORIG_CFG="$ROOT_DIR/packages/dart_wellen/flutter_rust_bridge.yaml"
ORIG_DIR="$(dirname "$ORIG_CFG")"
TMP_CFG="$ORIG_DIR/flutter_rust_bridge.generated.$(date +%s).yaml"

cleanup() {
    rm -f "$TMP_CFG"
}
trap cleanup EXIT

if [ ! -f "$ORIG_CFG" ]; then
    echo "[build-dart-wellen] ERROR: original config not found at $ORIG_CFG" >&2
    exit 1
fi

# Compute absolute paths for rust entries
ABS_RUST_ROOT="$ROOT_DIR/rust/wellen_bridge"
ABS_RUST_OUTPUT="$ROOT_DIR/rust/wellen_bridge/src/frb_generated.rs"

echo "[build-dart-wellen] Rewriting rust_root -> $ABS_RUST_ROOT"
echo "[build-dart-wellen] Rewriting rust_output -> $ABS_RUST_OUTPUT"

# Keep dart_output and dart_root as package-local
sed -E \
    -e "s|^rust_root:.*$|rust_root: $ABS_RUST_ROOT|" \
    -e "s|^rust_output:.*$|rust_output: $ABS_RUST_OUTPUT|" \
    "$ORIG_CFG" > "$TMP_CFG"

# Ensure dart_root is set correctly
if grep -q "^dart_root:" "$TMP_CFG"; then
    sed -i 's|^dart_root:.*$|dart_root: "."|' "$TMP_CFG"
else
    printf "\ndart_root: \".\"\n" >> "$TMP_CFG"
fi

# FRB 2.7 only searches dart_root for pubspec.lock and predates root workspace
# lockfiles. Pub has already validated and resolved dependencies at the root,
# so skip its legacy checks and automatic pubspec mutation.
if grep -q "^deps_check:" "$TMP_CFG"; then
    sed -i 's|^deps_check:.*$|deps_check: false|' "$TMP_CFG"
else
    printf "\ndeps_check: false\n" >> "$TMP_CFG"
fi
if grep -q "^local:" "$TMP_CFG"; then
    sed -i 's|^local:.*$|local: true|' "$TMP_CFG"
else
    printf "local: true\n" >> "$TMP_CFG"
fi

echo "[build-dart-wellen] Using temporary config $TMP_CFG"

# Ensure dart output directory exists
mkdir -p "$ROOT_DIR/packages/dart_wellen/lib/src/rust"

# Run codegen
echo "[build-dart-wellen] Invoking: flutter_rust_bridge_codegen generate (from packages/dart_wellen)"
pushd "$ROOT_DIR/packages/dart_wellen" >/dev/null
"$RUSTUP_BIN" run "$RUST_TOOLCHAIN" flutter_rust_bridge_codegen generate --config-file "$TMP_CFG"
popd >/dev/null

echo "[build-dart-wellen] Done."

echo "[build-dart-wellen] Dart interface ready in packages/dart_wellen/"
