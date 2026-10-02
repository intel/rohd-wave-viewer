#!/usr/bin/env bash
set -euo pipefail
# Install WASM tools: wasm-pack, wasm-bindgen-cli, binaryen (wasm-opt), and wabt (wasm2wat/wat2wasm)
# These tools are needed for building and patching WebAssembly packages for VS Code extension compatibility.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
WASM_PACK_VERSION="0.13.1"
WASM_BINDGEN_VERSION="0.2.121"

# Load rust environment (expects install_rust_1_92.sh or equivalent run beforehand)
source "$ROOT_DIR/scripts/setup_rust_env.sh"

# Preserve environment variables (including proxy settings) when installing tools
# This ensures tools can download dependencies through corporate proxies
export http_proxy="${http_proxy:-}"
export https_proxy="${https_proxy:-}"
export HTTP_PROXY="${HTTP_PROXY:-}"
export HTTPS_PROXY="${HTTPS_PROXY:-}"
export NO_PROXY="${NO_PROXY:-}"
export no_proxy="${no_proxy:-}"

# Ensure cargo is available
if ! command -v cargo >/dev/null 2>&1; then
  echo "[install-wasm-tools] ERROR: cargo not found. Run install_rust_1_92.sh first." >&2
  exit 1
fi

# Install binaryen (wasm-opt) - needed by wasm-pack for optimization
if ! command -v wasm-opt >/dev/null 2>&1; then
  echo "[install-wasm-tools] Installing binaryen (wasm-opt)..."

  # Determine if we need sudo (only when not already root)
  SUDO_CMD=""
  if [ "$EUID" -ne 0 ]; then
    SUDO_CMD="sudo -E"
  fi

  OS="$(uname -s)"
  case "$OS" in
    Linux*)
      if command -v apt-get >/dev/null 2>&1; then
        $SUDO_CMD apt-get update -y
        $SUDO_CMD apt-get install -y binaryen
      elif command -v dnf >/dev/null 2>&1; then
        $SUDO_CMD dnf install -y binaryen
      elif command -v yum >/dev/null 2>&1; then
        $SUDO_CMD yum install -y binaryen
      elif command -v pacman >/dev/null 2>&1; then
        $SUDO_CMD pacman -Sy --noconfirm binaryen
      elif command -v zypper >/dev/null 2>&1; then
        $SUDO_CMD zypper -n install binaryen
      else
        echo "[install-wasm-tools] WARNING: Unknown package manager. Please install binaryen manually."
        echo "[install-wasm-tools] Download from: https://github.com/WebAssembly/binaryen/releases"
      fi
      ;;
    Darwin*)
      if command -v brew >/dev/null 2>&1; then
        brew install binaryen
      else
        echo "[install-wasm-tools] WARNING: Homebrew not found. Please install binaryen manually."
      fi
      ;;
    *)
      echo "[install-wasm-tools] WARNING: Unsupported OS. Please install binaryen manually."
      ;;
  esac
else
  echo "[install-wasm-tools] binaryen (wasm-opt) already installed"
fi

# Install the pinned wasm-pack version if missing or different
if ! command -v wasm-pack >/dev/null 2>&1 ||
  [ "$(wasm-pack --version | awk '{print $2}')" != "$WASM_PACK_VERSION" ]; then
  echo "[install-wasm-tools] Installing wasm-pack $WASM_PACK_VERSION via cargo..."
  cargo install wasm-pack --version "$WASM_PACK_VERSION" --locked --force
else
  echo "[install-wasm-tools] wasm-pack $WASM_PACK_VERSION already installed"
fi

# Install the version matching rust/wellen_bridge/Cargo.lock
if ! command -v wasm-bindgen >/dev/null 2>&1 ||
  [ "$(wasm-bindgen --version | awk '{print $2}')" != "$WASM_BINDGEN_VERSION" ]; then
  echo "[install-wasm-tools] Installing wasm-bindgen-cli $WASM_BINDGEN_VERSION via cargo..."
  cargo install wasm-bindgen-cli --version "$WASM_BINDGEN_VERSION" --locked --force
else
  echo "[install-wasm-tools] wasm-bindgen $WASM_BINDGEN_VERSION already installed"
fi

# Install wabt (WebAssembly Binary Toolkit) - needed for patching WASM for webview compatibility
if ! command -v wasm2wat >/dev/null 2>&1 || ! command -v wat2wasm >/dev/null 2>&1; then
  echo "[install-wasm-tools] Installing wabt (wasm2wat, wat2wasm)..."

  # Determine if we need sudo (only when not already root)
  SUDO_CMD=""
  if [ "$EUID" -ne 0 ]; then
    SUDO_CMD="sudo -E"
  fi

  OS="$(uname -s)"
  case "$OS" in
    Linux*)
      if command -v apt-get >/dev/null 2>&1; then
        $SUDO_CMD apt-get update -y
        $SUDO_CMD apt-get install -y wabt
      elif command -v dnf >/dev/null 2>&1; then
        $SUDO_CMD dnf install -y wabt
      elif command -v yum >/dev/null 2>&1; then
        $SUDO_CMD yum install -y wabt
      elif command -v pacman >/dev/null 2>&1; then
        $SUDO_CMD pacman -Sy --noconfirm wabt
      elif command -v zypper >/dev/null 2>&1; then
        $SUDO_CMD zypper -n install wabt
      else
        echo "[install-wasm-tools] WARNING: Unknown package manager. Please install wabt manually."
        echo "[install-wasm-tools] Download from: https://github.com/WebAssembly/wabt/releases"
      fi
      ;;
    Darwin*)
      if command -v brew >/dev/null 2>&1; then
        brew install wabt
      else
        echo "[install-wasm-tools] WARNING: Homebrew not found. Please install wabt manually."
      fi
      ;;
    *)
      echo "[install-wasm-tools] WARNING: Unsupported OS. Please install wabt manually."
      ;;
  esac
else
  echo "[install-wasm-tools] wabt (wasm2wat, wat2wasm) already installed"
fi

for required_tool in wasm-pack wasm-bindgen wasm-opt wasm2wat wat2wasm; do
  if ! command -v "$required_tool" >/dev/null 2>&1; then
    echo "[install-wasm-tools] ERROR: required tool not found after installation: $required_tool" >&2
    exit 1
  fi
done

echo "[install-wasm-tools] Done."
