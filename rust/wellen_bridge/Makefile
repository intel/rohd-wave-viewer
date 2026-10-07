# Makefile for wellen_bridge Rust library
# Builds both WASM (for web) and native (for desktop) targets

SHELL := /bin/bash
BRIDGE_DIR := $(abspath $(CURDIR))
ROOT_DIR := $(abspath $(BRIDGE_DIR)/../..)

WASM_PKG := $(ROOT_DIR)/web/pkg
NATIVE_LIB := $(BRIDGE_DIR)/target/release
FRB_GENERATED_RS := $(BRIDGE_DIR)/src/frb_generated.rs
FRB_GENERATED_DART := $(ROOT_DIR)/packages/dart_wellen/lib/src/rust/frb_generated.dart

.PHONY: all wasm native clean clean-wasm clean-native real-clean help

help:
	@echo "wellen_bridge Rust Library - Build Targets"
	@echo ""
	@echo "Build targets:"
	@echo "  all          - Build both WASM and native (default)"
	@echo "  wasm         - Build WASM package for web (web/pkg)"
	@echo "  native       - Build native library for desktop (target/release)"
	@echo ""
	@echo "Clean targets:"
	@echo "  clean        - Clean all build artifacts"
	@echo "  clean-wasm   - Clean WASM artifacts only"
	@echo "  clean-native - Clean native artifacts only"
	@echo ""
	@echo "Prerequisites:"
	@echo "  - Rust toolchain 1.92+ (run: ../../tool/gh_actions/install_rust_1_92.sh)"
	@echo "  - WASM tools for wasm target (run: ../../tool/gh_actions/install_wasm_tools.sh)"

all: wasm native

# Build WASM package using wasm-pack
wasm:
	@echo "Building WASM package..."
	@bash "$(BRIDGE_DIR)/build_wasm.sh"

# Build native shared library using cargo
native:
	@echo "Building native library..."
	@bash "$(BRIDGE_DIR)/build_native.sh"

# Clean all artifacts (WASM + native + generated files)
clean: clean-wasm clean-native
	@echo "Cleaning generated FRB files..."
	@rm -f "$(FRB_GENERATED_RS)"
	@rm -f "$(FRB_GENERATED_DART)"
	@rm -f "$(ROOT_DIR)/packages/dart_wellen/lib/src/rust/api"/*.dart 2>/dev/null || true
	@rm -f "$(ROOT_DIR)/packages/dart_wellen/lib/src/rust/frb_generated"*.dart 2>/dev/null || true
	@find "$(ROOT_DIR)/packages/dart_wellen" -type f -name 'flutter_rust_bridge.generated.*.yaml' -delete 2>/dev/null || true
	@rm -f "$(ROOT_DIR)/packages/dart_wellen/linux/"*.so 2>/dev/null || true
	@echo "✓ All wellen_bridge artifacts cleaned"

# Clean WASM artifacts
clean-wasm:
	@echo "Cleaning WASM artifacts..."
	@rm -rf "$(WASM_PKG)"

# Clean native artifacts
clean-native:
	@echo "Cleaning native artifacts..."
	@rm -rf "$(BRIDGE_DIR)/target"

# Deep clean - full clean plus flutter clean at root
real-clean: clean
	@echo "Running flutter clean from wellen_bridge..."
	-@cd "$(ROOT_DIR)" && flutter clean
	@echo "Removing Rust target directory..."
	-@rm -rf "$(BRIDGE_DIR)/target"
