#!/usr/bin/env bash
set -euo pipefail
# Install complete C++ build environment: compiler, CMake, Ninja, pkg-config, LLVM/libclang.
# Suitable for Flutter Linux builds, Rust bridge codegen (ffigen), and other C/C++ projects.
# Works in both CI (root) and local dev (regular user) environments.

log() { echo "[install-build-tools] $*"; }

# Determine if we need sudo (only when not already root)
SUDO_CMD=""
if [ "$EUID" -ne 0 ]; then
  SUDO_CMD="sudo -E"
fi

has_cmd() { command -v "$1" >/dev/null 2>&1; }

has_cxx() {
  command -v g++ >/dev/null 2>&1 || command -v clang++ >/dev/null 2>&1
}

# Check if all required tools are already present
if has_cxx && command -v make >/dev/null 2>&1 && \
   command -v cmake >/dev/null 2>&1 && command -v ninja >/dev/null 2>&1 && \
   command -v pkg-config >/dev/null 2>&1 && has_cmd clang; then
  log "All build tools found; skipping install."
  exit 0
fi

OS="$(uname -s)"
case "$OS" in
  Linux*)
    if command -v apt-get >/dev/null 2>&1; then
      log "Installing via apt-get..."
      $SUDO_CMD apt-get update -y
      # Core build tools + GTK/graphics for Flutter Linux + LLVM for codegen
      $SUDO_CMD apt-get install -y \
        build-essential cmake ninja-build pkg-config \
        clang llvm libclang-dev \
        python3 \
        nodejs npm \
        libgtk-3-dev libglib2.0-dev libgirepository1.0-dev \
        libpango1.0-dev libatk1.0-dev libcairo2-dev libgdk-pixbuf2.0-dev \
        libx11-dev libxext-dev libxkbcommon-dev libxfixes-dev \
        libwayland-dev
    elif command -v dnf >/dev/null 2>&1; then
      log "Installing via dnf..."
      $SUDO_CMD dnf install -y \
        gcc-c++ make cmake ninja-build pkg-config \
        clang llvm llvm-devel \
        python3 \
        nodejs npm \
        gtk3-devel glib2-devel gobject-introspection-devel \
        pango-devel atk-devel cairo-devel gdk-pixbuf2-devel \
        libX11-devel libXext-devel libxkbcommon-devel libxfixes-devel \
        wayland-devel
    elif command -v yum >/dev/null 2>&1; then
      log "Installing via yum..."
      $SUDO_CMD yum install -y \
        gcc-c++ make cmake ninja-build pkg-config \
        clang llvm llvm-devel \
        python3 \
        nodejs npm \
        gtk3-devel glib2-devel gobject-introspection-devel \
        pango-devel atk-devel cairo-devel gdk-pixbuf2-devel \
        libX11-devel libXext-devel libxkbcommon-devel libxfixes-devel \
        wayland-devel
    elif command -v pacman >/dev/null 2>&1; then
      log "Installing via pacman..."
      $SUDO_CMD pacman -Sy --noconfirm \
        base-devel cmake ninja pkg-config \
        clang llvm \
        python \
        nodejs npm \
        gtk3 glib2 gobject-introspection \
        pango atk cairo gdk-pixbuf \
        libx11 libxext libxkbcommon libxfixes \
        wayland
    elif command -v zypper >/dev/null 2>&1; then
      log "Installing via zypper..."
      $SUDO_CMD zypper -n install \
        gcc-c++ make cmake ninja pkg-config \
        clang llvm llvm-devel \
        python3 \
        nodejs npm \
        gtk3-devel glib2-devel gobject-introspection-devel \
        pango-devel atk-devel cairo-devel gdk-pixbuf-devel \
        libX11-devel libXext-devel libxkbcommon-devel libxfixes-devel \
        wayland-devel
    else
      log "Unknown package manager. Please install gcc, make, cmake, ninja, pkg-config, clang, llvm, nodejs, npm, gtk3, glib2 manually."
      exit 1
    fi
    ;;
  Darwin*)
    if has_cmd brew; then
      log "Installing via Homebrew..."
      # Note: macOS includes native graphics frameworks (Quartz), so GTK is optional.
      # Install LLVM for codegen and other tools for consistency
      brew install gcc cmake ninja pkg-config llvm gobject-introspection make python3 node
      log "Note: you may want to add GNU make to PATH if needed (brew install make)."
    else
      log "Homebrew not found. Please install Command Line Tools (xcode-select --install) or Homebrew."
      exit 1
    fi
    ;;
  *)
    log "Unsupported OS: $OS. Please install build tools manually."
    exit 1
    ;;
 esac

# Discover libclang and export LIBCLANG_PATH for current shell
libclang_path=""
if has_cmd ldconfig; then
  libclang_path=$(ldconfig -p 2>/dev/null | awk '/libclang\.so/ {print $NF}' | head -n1 || true)
fi
if [ -z "$libclang_path" ]; then
  libclang_path=$(find /usr/lib /usr/lib64 /usr/lib/x86_64-linux-gnu /usr/local/lib /usr/lib/llvm-* -name 'libclang.so*' -print -quit 2>/dev/null || true)
fi
if [ -n "$libclang_path" ]; then
  export LIBCLANG_PATH="$(dirname "$libclang_path")"
  log "Found libclang: $libclang_path"
  log "LIBCLANG_PATH=$LIBCLANG_PATH"
else
  log "WARNING: libclang not found after installation attempts."
  log "Please install LLVM/libclang manually and re-run, or set LIBCLANG_PATH environment variable."
fi

if has_cxx && command -v make >/dev/null 2>&1 && \
   command -v cmake >/dev/null 2>&1 && command -v ninja >/dev/null 2>&1 && \
   command -v pkg-config >/dev/null 2>&1 && has_cmd clang; then
  log "Build environment installed successfully."
else
  log "Build tools installation did not fully succeed. Some tools may be missing."
  exit 1
fi
