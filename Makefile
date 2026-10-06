# Makefile for ROHD Wave Viewer
#
# Design: two separate dependency strategies coexist here.
#
#   RUN targets  (web-run, linux-run-debug, linux-run-release)
#     Only ensure non-Dart prerequisites (WASM, native lib, pub get) are
#     ready, then hand off to `flutter run`.  Flutter's own incremental
#     compiler + hot reload handles Dart changes, so Make must NOT depend
#     on $(DART_SOURCES) on this path.
#
#   PACKAGE targets  (extension, install-remote)
#     Must produce build artifacts that reflect the CURRENT Dart sources
#     before they get zipped into the extension.  The real output files
#     (build/web/index.html, build/linux/.../wave_viewer) serve as Make
#     targets and depend on $(DART_SOURCES) so that any source edit
#     invalidates them and forces a rebuild on the next package.
#
#   BUILD targets  (web, linux, etc.)
#     Explicit "build me now" commands.  These use the output-file targets
#     so they also track Dart sources.
#
# FLUTTER_WEB_MODE controls debug vs release for web builds (default: release).
#   make install                           # release (default)
#   make install FLUTTER_WEB_MODE=debug    # debug

ROOT := $(abspath $(CURDIR))
FLUTTER ?= flutter
NODE ?= node

FLUTTER_WEB_MODE ?= release
FLUTTER_WEB_BUILD_ARGS ?=
# Release web artifacts use Flutter's WASM entrypoint. The generated
# flutter_bootstrap.js selects the WASM files when they are present, while
# debug builds remain JavaScript-based unless explicitly overridden.
FLUTTER_WEB_WASM ?= $(if $(filter release,$(FLUTTER_WEB_MODE)),1,0)
FLUTTER_WEB_RELEASE_WASM ?= 1
FLUTTER_WEB_WASM_ARGS := $(if $(filter 1 true yes,$(FLUTTER_WEB_WASM)),--wasm,)
ROHD_LOCAL_PATH ?= $(HOME)/release/rohd

# Source file patterns for dependency tracking.
# Includes the app's own lib/ and the local Wellen dependency package.
DART_DEP_DIRS := \
	$(ROOT)/lib \
	$(ROOT)/packages/dart_wellen/lib \
	$(ROHD_LOCAL_PATH)/packages/rohd_devtools_widgets/lib \
	$(ROHD_LOCAL_PATH)/packages/rohd_hierarchy/lib \
	$(ROHD_LOCAL_PATH)/packages/rohd_waveform/lib
DART_SOURCES := $(shell find $(DART_DEP_DIRS) -name '*.dart' 2>/dev/null)
RUST_SOURCES := $(shell find $(ROOT)/rust/wellen_bridge/src -name '*.rs' ! -name 'frb_generated.rs' 2>/dev/null)
RUST_CARGO := $(ROOT)/rust/wellen_bridge/Cargo.toml
TS_SOURCES := $(shell find $(ROOT)/vscode-extension/src -name '*.ts' 2>/dev/null)

# Source of truth: extract version from pubspec.yaml
PUBSPEC_VERSION := $(shell grep '^version:' $(ROOT)/pubspec.yaml | head -1 | sed 's/version: *//')

PKG_NAME := $(shell command -v $(NODE) >/dev/null 2>&1 && $(NODE) -p "require('$(ROOT)/vscode-extension/package.json').name" || echo rohd-wave-viewer-vscode)
PKG_VERSION := $(PUBSPEC_VERSION)
EXT_STAGE := $(ROOT)/build/extension/$(PKG_NAME)-$(PKG_VERSION)
SLIM_ZIP := $(ROOT)/build/$(PKG_NAME)-$(PKG_VERSION)-slim.zip
WEB_BUILD := $(ROOT)/build/web
LINUX_BUNDLE := $(ROOT)/build/linux/x64/release/bundle
LINUX_BUNDLE_DEBUG := $(ROOT)/build/linux/x64/debug/bundle
DART_FRB_DIR := $(ROOT)/packages/dart_wellen/lib/src/rust
DART_FRB_API := $(DART_FRB_DIR)/api.dart
DART_FRB := $(DART_FRB_DIR)/frb_generated.dart
DART_FRB_IO := $(DART_FRB_DIR)/frb_generated.io.dart
DART_FRB_WEB := $(DART_FRB_DIR)/frb_generated.web.dart
DART_FRB_OUTPUTS := $(DART_FRB_API) $(DART_FRB) $(DART_FRB_IO) $(DART_FRB_WEB)
RUST_FRB := $(ROOT)/rust/wellen_bridge/src/frb_generated.rs
FRB_OUTPUTS := $(DART_FRB_OUTPUTS) $(RUST_FRB)
FRB_CONFIG := $(ROOT)/packages/dart_wellen/flutter_rust_bridge.yaml
FRB_API := $(ROOT)/rust/wellen_bridge/src/api.rs
WASM_PKG := $(ROOT)/web/pkg
WASM_OUTPUTS := $(WASM_PKG)/wellen_bridge.js $(WASM_PKG)/wellen_bridge_bg.wasm
VSIX := $(ROOT)/build/rohd-wave-viewer-$(PKG_VERSION).vsix
NATIVE_LIB := $(ROOT)/rust/wellen_bridge/target/release/libwellen_bridge.so

.PHONY: all help extension extension-web extension-web-js web web-debug web-release linux linux-debug linux-release \
	vsix package dart wasm wasm-tools rust-native test \
	pana \
	rust-test browser-test coverage coverage-view coverage-clean \
	coverity coverity-setup coverity-clean \
        install install-local install-remote \
	prepare web-run linux-run-debug linux-run-release \
        clean clean-extension clean-web clean-linux force real-clean \
        sync-version

help:
	@echo "ROHD Wave Viewer Extension - Build Targets"
	@echo ""
	@echo "Extension Build Targets:"
	@echo "  all              - Build the extension (default target)"
	@echo "  extension        - Build VS Code extension (TS + Flutter web)"
	@echo "  vsix             - Package extension as VSIX file"
	@echo "  package          - Package extension as slim zip"
	@echo ""
	@echo "Web Build Targets:"
	@echo "  web              - Build Flutter web app (default mode: release)"
	@echo "  web-debug        - Build Flutter web app (debug, forces rebuild)"
	@echo "  web-release      - Build Flutter web app (release, forces rebuild)"
	@echo ""
	@echo "Linux Build Targets:"
	@echo "  linux            - Build Flutter Linux desktop app (release)"
	@echo "  linux-debug      - Build Flutter Linux desktop app (debug)"
	@echo "  linux-release    - Build Flutter Linux desktop app (release)"
	@echo ""
	@echo "Dependency Targets:"
	@echo "  dart             - Generate Dart/Rust bridge bindings"
	@echo "  wasm             - Build WASM bridge"
	@echo "  wasm-tools       - Install required WASM build tools into the environment"
	@echo "  rust-native      - Build native Rust library for Linux"
	@echo "  rust-test        - Run Rust bridge unit tests separately from Dart coverage"
	@echo "  browser-test     - Run dart_wellen WASM integration tests in Chrome"
	@echo "  coverity         - Run configured Coverity scan workflow"
	@echo "  coverage         - Cover root and dart_wellen tests in LCOV/HTML reports"
	@echo "  coverage-view    - Serve coverage/html locally on port 8000"
	@echo ""
	@echo "Run Targets (Flutter manages Dart rebuilds via hot reload):"
	@echo "  web-run          - Run Flutter web server (development)"
	@echo "  linux-run-debug  - Run Flutter Linux app (debug, with hot reload)"
	@echo "  linux-run-release - Run Flutter Linux app (release)"
	@echo ""
	@echo "Install Targets:"
	@echo "  install          - Build and install extension to remote"
	@echo "  install-local    - Build and install as VSIX to local VS Code"
	@echo "  install-remote   - Build and install extension to remote"
	@echo "                     Use FLUTTER_WEB_MODE=debug for debug build"
	@echo ""
	@echo "Test Targets:"
	@echo "  test             - Run Flutter tests with native lib on LD_LIBRARY_PATH"
	@echo "                     Pass extra args via ARGS, e.g. make test ARGS=test/vcd_snapshot_test.dart"
	@echo "  pana             - Run Pana for publishable workspace packages"
	@echo ""
	@echo "Clean Targets:"
	@echo "  clean            - Clean all build artifacts (except source)"
	@echo "  clean-web        - Clean Flutter web build artifacts"
	@echo "  clean-linux      - Clean Flutter Linux build artifacts"
	@echo "  clean-extension  - Clean extension packaging artifacts"
	@echo "  real-clean       - Deep clean including Rust builds and generated code"
	@echo ""
	@echo "Development Targets:"

wasm-tools:
	@bash $(ROOT)/tool/gh_actions/install_wasm_tools.sh
	@echo "  force            - Clean everything and rebuild from scratch"
	@echo ""

all: extension

pana:
	@bash "$(ROOT)/tool/gh_actions/pana_source.sh"

# ---------------------------------------------------------------------------
# Rust / WASM / FRB dependency targets (actual output files)
# ---------------------------------------------------------------------------
# Note: Do NOT list $(RUST_SOURCES) as Make prerequisites.  The build
# scripts check Rust source timestamps internally (Cargo handles this),
# and listing them here would cause unnecessary re-runs of the bridge
# generator when only Rust internals changed.

# Generate Dart/Rust bridge bindings
$(FRB_OUTPUTS) &: $(RUST_CARGO) $(FRB_CONFIG) $(FRB_API) scripts/build_dart_wellen_bridge.sh
	@echo "Generating Flutter Rust Bridge bindings..."
	@bash "$(ROOT)/scripts/build_dart_wellen_bridge.sh"

dart: $(FRB_OUTPUTS)

# Build WASM bridge
$(WASM_OUTPUTS) &: $(FRB_OUTPUTS) $(RUST_CARGO) rust/wellen_bridge/build_wasm.sh
	@echo "Building WASM bridge..."
	@bash "$(ROOT)/rust/wellen_bridge/build_wasm.sh"
	@echo "Patching WASM binary for VS Code Remote webview compatibility..."
	@bash "$(ROOT)/scripts/patch_wasm_binary.sh"
	@echo "Patching WASM JS for VS Code Remote webview compatibility..."
	@bash "$(ROOT)/scripts/patch_wasm_js.sh"

wasm: $(WASM_OUTPUTS)

# Build native Rust library for Linux
$(NATIVE_LIB): $(FRB_OUTPUTS) $(RUST_CARGO) rust/wellen_bridge/build_native.sh
	@echo "Building native Rust library..."
	@bash "$(ROOT)/rust/wellen_bridge/build_native.sh"

rust-native: $(NATIVE_LIB)

# Root DevTools build and run targets invoke this generic widget hook.
prepare: rust-native

# ---------------------------------------------------------------------------
# BUILD / PACKAGE path  (actual output files track Dart source freshness)
# ---------------------------------------------------------------------------
# These targets use real build outputs as Make targets.  When any
# $(DART_SOURCES) file is newer than the output, Make triggers a rebuild.
#
# `flutter run` (used by RUN targets) also updates these same output files
# as a side-effect of its own incremental compiler.  So if you iterate
# with `flutter run` then run `make install`, Make sees the output
# is already fresh and skips the `flutter build` step.

# Flutter web: both debug and release write to build/web/ (Flutter default).
# FLUTTER_WEB_MODE controls the mode; web-debug/web-release force it.
$(WEB_BUILD)/index.html: web/index.html $(WASM_OUTPUTS) pubspec.yaml $(DART_SOURCES) \
	scripts/fix_bootstrap.py scripts/patch_wasm_binary.sh scripts/patch_wasm_js.sh \
	scripts/verify_flutter_native_dependencies.sh security/native-dependency-exceptions.json
	@echo "Building Flutter web ($(FLUTTER_WEB_MODE))..."
	# Flutter can retain a previous dual JS/WASM build in build/web, so always
	# remove the output before producing a package.
	@rm -rf "$(WEB_BUILD)"
	@cd "$(ROOT)" && $(FLUTTER) pub get
	# The separately built Rust WASM bridge is copied below.
	@cd "$(ROOT)" && $(FLUTTER) build web --$(FLUTTER_WEB_MODE) $(FLUTTER_WEB_WASM_ARGS) --target lib/main_web.dart $(FLUTTER_WEB_BUILD_ARGS)
	@echo "Copying WASM pkg into build/web..."
	@rm -rf "$(WEB_BUILD)/pkg"
	@cp -r "$(WASM_PKG)" "$(WEB_BUILD)/"
	@echo "Patching flutter_bootstrap.js for webview compatibility..."
	@python3 "$(ROOT)/scripts/fix_bootstrap.py"
	@echo "Patching WASM binary for VS Code Remote webview compatibility..."
	@bash "$(ROOT)/scripts/patch_wasm_binary.sh"
	@echo "Patching WASM JS for VS Code Remote webview compatibility..."
	@bash "$(ROOT)/scripts/patch_wasm_js.sh"
	@bash "$(ROOT)/scripts/verify_flutter_native_dependencies.sh" \
		"$(WEB_BUILD)/canvaskit/canvaskit.wasm"

# Convenience aliases
web: $(WEB_BUILD)/index.html

# web-debug / web-release: force the correct mode by cleaning + rebuilding.
# Both land in build/web/ so we must remove the stale output first.
web-debug:
	@rm -f $(WEB_BUILD)/index.html
	@$(MAKE) $(WEB_BUILD)/index.html FLUTTER_WEB_MODE=debug FLUTTER_WEB_WASM=0

web-release:
	@rm -f $(WEB_BUILD)/index.html
	@$(MAKE) $(WEB_BUILD)/index.html FLUTTER_WEB_MODE=release FLUTTER_WEB_WASM=$(FLUTTER_WEB_RELEASE_WASM)

# Flutter Linux release
$(LINUX_BUNDLE)/wave_viewer: $(NATIVE_LIB) pubspec.yaml $(DART_SOURCES) \
	scripts/verify_flutter_native_dependencies.sh security/native-dependency-exceptions.json
	@echo "Building Flutter Linux desktop app (release)..."
	@mkdir -p build/native_assets/linux
	@cd "$(ROOT)" && $(FLUTTER) pub get
	@cd "$(ROOT)" && $(FLUTTER) build linux --release --target lib/main.dart
	@echo "Copying native Rust library into bundle..."
	@mkdir -p "$(LINUX_BUNDLE)/lib"
	@cp "$(NATIVE_LIB)" "$(LINUX_BUNDLE)/lib/"
	@bash "$(ROOT)/scripts/verify_flutter_native_dependencies.sh" \
		"$(LINUX_BUNDLE)/lib/libflutter_linux_gtk.so"

# Flutter Linux debug
$(LINUX_BUNDLE_DEBUG)/wave_viewer: $(NATIVE_LIB) pubspec.yaml $(DART_SOURCES) \
	scripts/verify_flutter_native_dependencies.sh security/native-dependency-exceptions.json
	@echo "Building Flutter Linux desktop app (debug)..."
	@mkdir -p build/native_assets/linux
	@cd "$(ROOT)" && $(FLUTTER) pub get
	@cd "$(ROOT)" && $(FLUTTER) build linux --debug --target lib/main.dart
	@echo "Copying native Rust library into bundle..."
	@mkdir -p "$(LINUX_BUNDLE_DEBUG)/lib"
	@cp "$(NATIVE_LIB)" "$(LINUX_BUNDLE_DEBUG)/lib/"
	@bash "$(ROOT)/scripts/verify_flutter_native_dependencies.sh" \
		"$(LINUX_BUNDLE_DEBUG)/lib/libflutter_linux_gtk.so"

linux: $(LINUX_BUNDLE)/wave_viewer
linux-release: $(LINUX_BUNDLE)/wave_viewer
linux-debug: $(LINUX_BUNDLE_DEBUG)/wave_viewer

# ---------------------------------------------------------------------------
# RUN path  (Flutter manages Dart rebuilds; Make only ensures prerequisites)
# ---------------------------------------------------------------------------
# These do NOT depend on $(DART_SOURCES).
# Flutter's incremental compiler + hot reload handle Dart changes.

web-run: $(WASM_PKG)/wellen_bridge_bg.wasm
	@cd "$(ROOT)" && $(FLUTTER) pub get
	@echo "Running Flutter web server (development)..."
	@cd "$(ROOT)" && $(FLUTTER) run -d web-server --web-port=9199 --web-hostname=localhost --target lib/main_web.dart

linux-run-debug: $(NATIVE_LIB)
	@mkdir -p build/native_assets/linux
	@cd "$(ROOT)" && $(FLUTTER) pub get
	@echo "Running Flutter Linux app (debug mode with hot reload)..."
	@cd "$(ROOT)" && $(FLUTTER) run -d linux --target lib/main.dart

linux-run-release: $(NATIVE_LIB)
	@mkdir -p build/native_assets/linux
	@cd "$(ROOT)" && $(FLUTTER) pub get
	@echo "Running Flutter Linux app (release mode)..."
	@cd "$(ROOT)" && $(FLUTTER) run -d linux --release --target lib/main.dart

# ---------------------------------------------------------------------------
# Test
# ---------------------------------------------------------------------------

test:
	@cd "$(ROOT)" && tool/gh_actions/run_tests.sh $(ARGS)

rust-test:
	@bash -lc 'set -euo pipefail; \
		cd "$(ROOT)"; \
		source scripts/setup_rust_env.sh; \
		"$$RUSTUP_BIN" run "$$RUST_TOOLCHAIN" cargo test \
			--manifest-path rust/wellen_bridge/Cargo.toml --lib'

browser-test: $(WASM_OUTPUTS)
	@bash "$(ROOT)/tool/gh_actions/run_browser_tests.sh"

coverage:
	@bash "$(ROOT)/scripts/generate_coverage.sh"

coverage-view:
	@bash "$(ROOT)/scripts/view_coverage.sh"

coverage-clean:
	@rm -rf "$(ROOT)/coverage/html" "$(ROOT)/coverage/lcov.info"

coverity:
	@bash "$(ROOT)/scripts/run_coverity.sh" all

coverity-setup:
	@bash "$(ROOT)/scripts/run_coverity.sh" setup

coverity-clean:
	@bash "$(ROOT)/scripts/run_coverity.sh" clean

# ---------------------------------------------------------------------------
# Version sync  (pubspec.yaml → package.json files)
# ---------------------------------------------------------------------------
# Ensures the VS Code extension manifests and lockfiles match the single source
# of truth in pubspec.yaml. Uses Node.js, which is required for extension builds.

sync-version:
	@echo "Syncing version $(PUBSPEC_VERSION) from pubspec.yaml → package.json files..."
	@if command -v $(NODE) >/dev/null 2>&1; then \
		for f in "$(ROOT)/vscode-extension/package.json"; do \
			$(NODE) -e " \
				const fs = require('fs'); \
				const pkg = JSON.parse(fs.readFileSync('$$f','utf8')); \
				pkg.version = '$(PUBSPEC_VERSION)'; \
				fs.writeFileSync('$$f', JSON.stringify(pkg, null, 2) + '\n');" ; \
			echo "  $$f → $(PUBSPEC_VERSION)"; \
		done; \
		for f in "$(ROOT)/vscode-extension/package-lock.json"; do \
			$(NODE) -e " \
				const fs = require('fs'); \
				const lock = JSON.parse(fs.readFileSync('$$f','utf8')); \
				lock.version = '$(PUBSPEC_VERSION)'; \
				if (lock.packages && lock.packages['']) lock.packages[''].version = '$(PUBSPEC_VERSION)'; \
				fs.writeFileSync('$$f', JSON.stringify(lock, null, 2) + '\n');" ; \
			echo "  $$f → $(PUBSPEC_VERSION)"; \
		done; \
	else \
		echo "error: Node.js is required to synchronize extension versions."; \
		exit 1; \
	fi

# ---------------------------------------------------------------------------
# Extension packaging  (TypeScript + Flutter web + asset staging)
# ---------------------------------------------------------------------------
# The wave-viewer extension always requires Flutter web — there is no
# JS-only rendering fallback.  Every package/install target goes through
# the same staging pipeline: compile TS, build Flutter web, copy into
# EXT_STAGE, zip.

# Compiled extension.js output
vscode-extension/out/extension.js: $(TS_SOURCES) vscode-extension/package.json
	@echo "Building VS Code TypeScript extension..."
	@bash -lc 'set -euo pipefail; \
		if [ -x /usr/bin/node ] && [ "$$(/usr/bin/node -p "process.versions.node.split(\".\")[0]")" -eq 24 ]; then \
			export PATH="/usr/bin:$$PATH"; \
		elif [ -s "$$HOME/.nvm/nvm.sh" ]; then \
			. "$$HOME/.nvm/nvm.sh"; \
			if nvm use --silent 24 >/dev/null 2>&1; then \
				echo "Using Node $$(node -v) via nvm (from .nvmrc expectation)"; \
			else \
				echo "error: Unable to activate Node 24 for the VS Code extension build."; \
				exit 1; \
			fi; \
		fi; \
		cd "$(ROOT)/vscode-extension"; \
		node_major=$$(node -p "process.versions.node.split(\".\")[0]"); \
		if [ "$$node_major" -ne 24 ]; then \
			echo "error: Node $$(node -v) is active for the VS Code extension build."; \
			echo "expected: Node 24 from .nvmrc"; \
			exit 1; \
		else \
			echo "Using Node $$(node -v)"; \
		fi; \
		npm install; \
		npm run compile'

# Stage extension: compiled TS output + Flutter web build + package metadata.
# vscode-extension/ is the sole source tree. The staged manifest points at the
# compiled entrypoint and excludes development-only Node metadata.
# This is the single packaging recipe used by all install targets.
# The extension uses Flutter's JavaScript bootstrap with the WASM application
# payload. Keep the old target as a compatibility alias for callers that used
# the previous JS-only name.
extension-web:
	@$(MAKE) web-release

extension-web-js: extension-web

$(SLIM_ZIP): vscode-extension/out/extension.js extension-web \
	scripts/copy_devtools_extension_assets.cjs | sync-version
	@echo "Staging extension (with Flutter web)..."
	@rm -rf "$(EXT_STAGE)"
	@mkdir -p "$(EXT_STAGE)"
	@cp "$(ROOT)/vscode-extension/package.json" "$(EXT_STAGE)/package.json"
	@cp "$(ROOT)/vscode-extension/README.md" "$(EXT_STAGE)/README.md"
	@cp "$(ROOT)/vscode-extension/icon.png" "$(EXT_STAGE)/icon.png"
	@cp "$(ROOT)/vscode-extension/filter_bank_waves.png" "$(EXT_STAGE)/filter_bank_waves.png"
	@cp "$(ROOT)/vscode-extension/waveform-demo.mp4" "$(EXT_STAGE)/waveform-demo.mp4"
	@cp -r "$(ROOT)/vscode-extension/images" "$(EXT_STAGE)/images"
	@cp "$(ROOT)/vscode-extension/out/extension.js" "$(EXT_STAGE)/extension.js"
	@if [ -f "$(ROOT)/vscode-extension/out/extension.js.map" ]; then \
		cp "$(ROOT)/vscode-extension/out/extension.js.map" "$(EXT_STAGE)/"; \
	fi
	@$(NODE) -e 'const fs = require("fs"); const path = "$(EXT_STAGE)/package.json"; const pkg = JSON.parse(fs.readFileSync(path, "utf8")); pkg.main = "./extension.js"; delete pkg.scripts; delete pkg.devDependencies; fs.writeFileSync(path, JSON.stringify(pkg, null, 2) + "\n");'
	@mkdir -p "$(EXT_STAGE)/shared"
	@node "$(ROOT)/scripts/copy_devtools_extension_assets.cjs" "$(EXT_STAGE)/shared"
	@rm -rf "$(EXT_STAGE)/flutter_web" && cp -r "$(WEB_BUILD)" "$(EXT_STAGE)/flutter_web"
	@echo "Packaging slim zip..."
	@bash "$(ROOT)/scripts/package_slim_zip.sh"

extension: $(SLIM_ZIP)
	@echo "Extension build complete"

package: $(SLIM_ZIP)
	@echo "Package available at $(SLIM_ZIP)"

vsix: $(SLIM_ZIP)
	@echo "Packaging staged extension as VSIX..."
	@echo "Packaging VSIX..."
	@bash "$(ROOT)/scripts/build_vsix.sh" "$(EXT_STAGE)" "$(VSIX)"
	@echo "VSIX available at $(VSIX)"

# ---------------------------------------------------------------------------
# Install targets
# ---------------------------------------------------------------------------

# Install to local VS Code (via VSIX)
install-local: vsix
	@echo "Installing extension to local VS Code..."
	@code --install-extension "$(VSIX)" || echo "Note: VS Code CLI not found; install manually from $(VSIX)"

# Install to remote VS Code Server (via slim zip)
install-remote: extension
	@echo "Installing extension to remote VS Code Server..."
	@bash "$(ROOT)/scripts/install_extension_server.sh" "$(SLIM_ZIP)"

# All install aliases point to the same pipeline (always includes Flutter web)
install: install-remote

# ---------------------------------------------------------------------------
# Clean targets
# ---------------------------------------------------------------------------

clean-extension:
	@echo "Cleaning extension build and packaging artifacts..."
	-@rm -rf "$(EXT_STAGE)"
	-@rm -f "$(VSIX)"
	-@rm -f "$(SLIM_ZIP)"
	-@rm -rf "$(ROOT)/vscode-extension/out"
	-@rm -rf "$(ROOT)/vscode-extension/.dart_tool"
	-@rm -f "$(ROOT)/vscode-extension/"*.vsix
	-@rm -f "$(ROOT)/vscode-extension/"*.bak

clean-web:
	@echo "Cleaning Flutter web build..."
	-@rm -rf "$(WEB_BUILD)"

clean-linux:
	@echo "Cleaning Flutter Linux build..."
	-@rm -rf "$(ROOT)/build/linux"
	-@rm -rf "$(ROOT)/linux/flutter/ephemeral"

clean: clean-extension clean-web clean-linux
	@FLUTTER="$(FLUTTER)" bash "$(ROOT)/scripts/clean_workspace.sh"
	@echo "Clean complete"

# Deep clean - removes all generated build artifacts including Rust builds
real-clean: clean
	@echo "Deep cleaning Rust, WASM, and generated build artifacts..."
	-@rm -rf "$(ROOT)/rust/wellen_bridge/target"
	-@rm -f "$(RUST_FRB)"
	-@rm -rf "$(DART_FRB_DIR)"
	-@rm -rf "$(ROOT)/web/pkg"
	-@rm -rf "$(ROOT)/vscode-extension/node_modules"
	-@rm -rf "$(ROOT)/vscode-extension/out"
	-@rm -rf "$(ROOT)/vscode-extension/.dart_tool"
	-@rm -f "$(ROOT)/vscode-extension/"*.vsix
	-@rm -f "$(ROOT)/vscode-extension/"*.bak
	-@rm -rf "$(ROOT)/build"
	@echo "Real clean complete - all generated build artifacts removed"

# Force rebuild of everything
force: clean all
