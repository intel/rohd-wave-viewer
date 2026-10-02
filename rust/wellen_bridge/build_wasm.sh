#!/usr/bin/env bash
set -euo pipefail
# Build rust wasm package (wellen_bridge) for web/pkg using wasm-pack

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$ROOT_DIR/scripts/setup_rust_env.sh"

echo "[rust-wasm] Building wasm package using wasm-pack..."

cd "$ROOT_DIR/rust/wellen_bridge"

# Require tools to be pre-installed (see tool/gh_actions/install_wasm_tools.sh)
if ! command -v wasm-pack >/dev/null 2>&1; then
    echo "[rust-wasm] ERROR: wasm-pack not found. Run tool/gh_actions/install_wasm_tools.sh first." >&2
    exit 1
fi

if ! command -v wasm-bindgen >/dev/null 2>&1; then
    echo "[rust-wasm] ERROR: wasm-bindgen-cli not found. Run tool/gh_actions/install_wasm_tools.sh first." >&2
    exit 1
fi

# wasm-opt is intentionally disabled in Cargo metadata for clean-state builds.
if ! command -v wasm-opt >/dev/null 2>&1; then
    echo "[rust-wasm] NOTE: wasm-opt (binaryen) not found."
    echo "[rust-wasm] Continuing because wasm-pack release builds are configured"
    echo "[rust-wasm] with wasm-opt disabled for offline/clean-state reliability."
    echo "[rust-wasm] Install binaryen if you want an extra optimization pass:"
    echo "[rust-wasm]   Run: tool/gh_actions/install_wasm_tools.sh"
    echo "[rust-wasm]   Or Ubuntu/Debian: sudo apt install binaryen"
    echo "[rust-wasm]   Or macOS: brew install binaryen"
    echo ""
fi

export PATH="$CARGO_HOME/bin:$PATH"

# Ensure required toolchain is present (installed by install_rust_1_92.sh)
if ! "$RUSTUP_BIN" toolchain list | grep -q "$RUST_TOOLCHAIN"; then
    echo "[rust-wasm] ERROR: Rust toolchain $RUST_TOOLCHAIN missing. Run tool/gh_actions/install_rust_1_92.sh." >&2
    exit 1
fi

# Preserve environment variables (including proxy settings) when running wasm-pack
# This ensures binaryen can be downloaded through corporate proxies
export http_proxy="${http_proxy:-}"
export https_proxy="${https_proxy:-}"
export HTTP_PROXY="${HTTP_PROXY:-}"
export HTTPS_PROXY="${HTTPS_PROXY:-}"
export NO_PROXY="${NO_PROXY:-}"
export no_proxy="${no_proxy:-}"

"$RUSTUP_BIN" run "$RUST_TOOLCHAIN" wasm-pack build --target no-modules --out-dir ../../web/pkg

echo "[rust-wasm] wasm-pack build finished"
