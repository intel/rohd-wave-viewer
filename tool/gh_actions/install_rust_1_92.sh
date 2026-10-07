#!/usr/bin/env bash
set -euo pipefail
# Install Rust 1.92 toolchain into per-user ~/.cargo and ~/.rustup
# Also installs the WASM target and FRB code generator used by wellen_bridge.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Determine invoking user's home (handles sudo)
if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER-}" ]; then
  INVOKER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
  INVOKER_HOME="$HOME"
fi

export CARGO_HOME="${CARGO_HOME:-${INVOKER_HOME}/.cargo}"
export RUSTUP_HOME="${RUSTUP_HOME:-${INVOKER_HOME}/.rustup}"

# Normalize potential colon-separated envs
CARGO_HOME="${CARGO_HOME%%:*}"
RUSTUP_HOME="${RUSTUP_HOME%%:*}"
export CARGO_HOME RUSTUP_HOME

export PATH="$CARGO_HOME/bin:$PATH"

RUST_VERSION="1.92.0"

echo "[install-rust] CARGO_HOME=$CARGO_HOME"
echo "[install-rust] RUSTUP_HOME=$RUSTUP_HOME"

# Install rustup if missing
RUSTUP_BIN="$CARGO_HOME/bin/rustup"
if ! command -v "$RUSTUP_BIN" >/dev/null 2>&1; then
  echo "[install-rust] rustup not found; installing to $CARGO_HOME/bin"

  # Retry function with exponential backoff
  retry_download() {
    local max_attempts=3
    local attempt=1
    local delay=2

    while [ $attempt -le $max_attempts ]; do
      echo "[install-rust] Download attempt $attempt/$max_attempts..."

      if command -v curl >/dev/null 2>&1; then
        if curl --proto '=https' --tlsv1.2 -sSf --connect-timeout 10 --max-time 60 \
               https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain "$RUST_VERSION"; then
          return 0
        fi
      elif command -v wget >/dev/null 2>&1; then
        if wget -qO- --timeout=10 https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain "$RUST_VERSION"; then
          return 0
        fi
      fi

      if [ $attempt -lt $max_attempts ]; then
        echo "[install-rust] Attempt $attempt failed. Waiting ${delay}s before retry..."
        sleep $delay
        delay=$((delay * 2))
      fi
      attempt=$((attempt + 1))
    done

    echo "[install-rust] ERROR: Failed to download Rust installer after $max_attempts attempts." >&2
    return 1
  }

  # Execute download with retries
  if ! retry_download; then
    echo "[install-rust] ERROR: Neither curl nor wget succeeded, or both unavailable." >&2
    exit 1
  fi
else
  echo "[install-rust] rustup already present at $RUSTUP_BIN"
fi

# Ensure toolchain and components
"$CARGO_HOME/bin/rustup" toolchain install "$RUST_VERSION"
"$CARGO_HOME/bin/rustup" default "$RUST_VERSION"
"$CARGO_HOME/bin/rustup" target add wasm32-unknown-unknown --toolchain "$RUST_VERSION"
"$CARGO_HOME/bin/rustup" component add rust-src --toolchain "$RUST_VERSION"
"$CARGO_HOME/bin/rustup" component add rustfmt --toolchain "$RUST_VERSION"

# Show versions
"$CARGO_HOME/bin/rustc" --version
"$CARGO_HOME/bin/cargo" --version
"$CARGO_HOME/bin/rustup" show

if ! command -v flutter_rust_bridge_codegen >/dev/null 2>&1; then
  echo "[install-rust] Installing flutter_rust_bridge_codegen via cargo..."
  "$CARGO_HOME/bin/cargo" install flutter_rust_bridge_codegen --version 2.7.0 --locked
fi

echo "[install-rust] Rust $RUST_VERSION installation complete."
