#!/usr/bin/env bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# setup_rust_env.sh
# Normalizes Rust environment variables and locates rustup.
#
# 2026 January
# Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

set -euo pipefail
# Script to normalize and export Rust environment variables and locate rustup

SCRIPT_DIR="$([ -n "${BASH_SOURCE[0]:-}" ] && dirname "${BASH_SOURCE[0]}" || pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Determine the invoking user's home: if run under sudo, prefer SUDO_USER.
if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER-}" ]; then
    INVOKER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    INVOKER_HOME="$HOME"
fi

# By default force the per-user cargo/rustup under the invoking user's home
# to avoid using system-owned locations like /opt which can cause permission errors.
# Set FORCE_SYSTEM_RUST=1 to allow using existing CARGO_HOME/RUSTUP_HOME if intentionally configured.
if [ -z "${FORCE_SYSTEM_RUST-}" ]; then
    export CARGO_HOME="${INVOKER_HOME}/.cargo"
    export RUSTUP_HOME="${INVOKER_HOME}/.rustup"
else
    # Respect an explicit CARGO_HOME if provided when forcing system rust
    export CARGO_HOME="${CARGO_HOME:-${INVOKER_HOME}/.cargo}"
    export RUSTUP_HOME="${RUSTUP_HOME:-${INVOKER_HOME}/.rustup}"
fi

# Normalize potential colon-separated paths by taking the first component
_CARGO_RAW="$CARGO_HOME"
_RUSTUP_RAW="$RUSTUP_HOME"
export CARGO_HOME="${_CARGO_RAW%%:*}"
export RUSTUP_HOME="${_RUSTUP_RAW%%:*}"

export PATH="$CARGO_HOME/bin:$PATH"

echo "[rust-env] CARGO_HOME=$CARGO_HOME"
echo "[rust-env] RUSTUP_HOME=$RUSTUP_HOME"
echo "[rust-env] PATH contains: $(echo $PATH | tr ':' '\n' | sed -n '1,5p')"

# Locate rustup: prefer $CARGO_HOME/bin/rustup
RUSTUP_BIN="$CARGO_HOME/bin/rustup"
if [ ! -x "$RUSTUP_BIN" ]; then
    if command -v rustup >/dev/null 2>&1; then
        RUSTUP_BIN="$(command -v rustup)"
    else
        RUSTUP_BIN=""
    fi
fi

if [ -z "$RUSTUP_BIN" ]; then
    echo "Error: rustup not found in $CARGO_HOME/bin or PATH. Please install rustup." >&2
    exit 1
fi

echo "[rust-env] using rustup: $RUSTUP_BIN"

# Pin a reproducible Rust nightly toolchain. Update this when you want a newer pinned nightly.
# Use an explicit date-based nightly such as 'nightly-2025-12-20' to ensure builds are repeatable.
RUST_TOOLCHAIN="1.92.0"
export RUST_TOOLCHAIN

# Ensure the pinned toolchain and wasm target are available
"$RUSTUP_BIN" toolchain list | grep -q "$RUST_TOOLCHAIN" || "$RUSTUP_BIN" toolchain install "$RUST_TOOLCHAIN"
"$RUSTUP_BIN" target add wasm32-unknown-unknown --toolchain "$RUST_TOOLCHAIN" 2>/dev/null || true
"$RUSTUP_BIN" component add rust-src --toolchain "$RUST_TOOLCHAIN" 2>/dev/null || true
"$RUSTUP_BIN" component add rustfmt --toolchain "$RUST_TOOLCHAIN" 2>/dev/null || true

# Export the selected rustup so callers can use it
export RUSTUP_BIN
