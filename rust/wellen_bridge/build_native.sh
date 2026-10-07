#!/usr/bin/env bash
set -euo pipefail
# Build native shared/static library for wellen_bridge using pinned toolchain.
# Outputs to rust/wellen_bridge/target/release/ (e.g., libwellen_bridge.so on Linux).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$ROOT_DIR/scripts/setup_rust_env.sh"

echo "[rust-native] Building native library for wellen_bridge..."
cd "$ROOT_DIR/rust/wellen_bridge"
"$RUSTUP_BIN" run "$RUST_TOOLCHAIN" cargo build --release

# Report built artifact
case "$(uname -s)" in
  Linux*)  ART="$ROOT_DIR/rust/wellen_bridge/target/release/libwellen_bridge.so" ;;
  Darwin*) ART="$ROOT_DIR/rust/wellen_bridge/target/release/libwellen_bridge.dylib" ;;
  MINGW*|MSYS*|CYGWIN*|Windows_NT) ART="$ROOT_DIR/rust/wellen_bridge/target/release/wellen_bridge.dll" ;;
  *) ART="$ROOT_DIR/rust/wellen_bridge/target/release/libwellen_bridge.so" ;;
esac

if [ -f "$ART" ]; then
  echo "[rust-native] Built: $ART"
else
  echo "[rust-native] Build complete; artifact in target/release (platform-dependent name)."
fi
