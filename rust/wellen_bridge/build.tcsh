#!/bin/tcsh
# Build script for wellen_bridge
# Handles Rust toolchain switching automatically

set STABLE_CARGO = ${HOME}/.rustup/toolchains/stable-x86_64-unknown-linux-gnu/bin/cargo
set RUST_180_CARGO = ${HOME}/.rustup/toolchains/1.80.0-x86_64-unknown-linux-gnu/bin/cargo

echo "=== wellen_bridge Build Script ==="
echo ""
echo "This project requires two Rust toolchains:"
echo "  - Rust 1.80:  For flutter_rust_bridge_codegen"
echo "  - Rust 1.92+: For wellen_bridge library (wellen 0.20.1 requires edition2024)"
echo ""

# Check if code generator is installed
if (! -x ${HOME}/.cargo/bin/flutter_rust_bridge_codegen) then
    echo "flutter_rust_bridge_codegen not found. Installing with Rust 1.80..."
    if (-x "$RUST_180_CARGO") then
        echo "Using Rust 1.80 to install code generator..."
        # Ensure per-user cargo/rustup locations
        setenv CARGO_HOME ${HOME}/.cargo
        setenv RUSTUP_HOME ${HOME}/.rustup
        $RUST_180_CARGO install flutter_rust_bridge_codegen --version 2.6.0 --locked
        if ($status != 0) then
            echo "ERROR: Failed to install code generator"
            exit 1
        endif
    else
        echo "ERROR: Rust 1.80 toolchain not found at $RUST_180_CARGO"
        echo "Install it with: rustup install 1.80.0"
        exit 1
    endif
else
    echo "✓ Code generator already installed"
endif

echo ""
echo "Building wellen_bridge library with Rust 1.92 (stable)..."

if (! -x "$STABLE_CARGO") then
    echo "ERROR: Rust stable toolchain not found at $STABLE_CARGO"
    echo "Install it with: rustup install stable"
    exit 1
endif

# Set PATH to use stable toolchain
setenv PATH ~/.rustup/toolchains/stable-x86_64-unknown-linux-gnu/bin:$PATH

# Build the library
$script_dir = `dirname $0`
cd $script_dir
$STABLE_CARGO build --release

if ($status != 0) then
    echo ""
    echo "ERROR: Build failed"
    exit 1
endif

echo ""
echo "✓ Build successful!"
echo ""
echo "Library location:"
echo "  target/release/libwellen_bridge.so"
echo ""
echo "Dart FFI bindings are already generated in:"
echo "  /home/ganewto/src/rohd/rohd-wave-viewer/packages/dart_wellen/lib/src/rust/"
echo ""
echo "To run tests:"
echo "  cd /home/ganewto/src/rohd/rohd-wave-viewer/packages/dart_wellen"
echo "  dart test"
