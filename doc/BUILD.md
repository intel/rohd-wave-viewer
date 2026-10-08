# Building ROHD Wave Viewer

## Prerequisites

- Flutter with its bundled Dart SDK. The root `pubspec.yaml` declares package
  compatibility, the GitHub Actions workflows pin CI, and
  `scripts/verify_flutter_version.sh` validates the active toolchain.
- Rust and the `wasm32-unknown-unknown` target, installed by the repository
  setup scripts.
- Native build tools, including CMake, Clang/LLVM, and GTK development files
  for Linux desktop builds.
- Node.js as selected by `.nvmrc` for VS Code extension builds.
- `wasm-pack`, `wasm-bindgen-cli`, Binaryen, and wabt for WebAssembly builds.

## Environment Setup

Install the same Rust, WASM, native, and Pub dependencies used by CI:

```bash
tool/gh_actions/install_rust_1_92.sh
tool/gh_actions/install_wasm_tools.sh
tool/gh_actions/install_build_tools.sh
tool/gh_actions/install_dependencies.sh
```

These scripts and `.nvmrc` are authoritative for development-tool versions.
Native Linux builds require the compiler, CMake, LLVM/Clang, and GTK
dependencies installed by `install_build_tools.sh`.

Resolve the Pub workspace from the repository root:

```bash
flutter pub get
```

The workspace includes the root application and `packages/dart_wellen`. To
inspect or change the selected hosted, Git, or local dependency sources, use:

```bash
bash scripts/wave_dev_mode.sh show
bash scripts/wave_dev_mode.sh manifest
```

See [DEVELOPER.md](DEVELOPER.md) for dependency groups, source-selection
commands, and VS Code tasks.

Verify the active environment before building:

```bash
bash scripts/verify_flutter_version.sh
flutter pub get
flutter analyze
```

## Cleaning Generated Outputs

`make clean` runs `flutter clean` for the root package and every package
listed under `workspace:` in the root `pubspec.yaml`. It also removes compiled
VS Code extension output and packaged webview assets while retaining Node
dependency caches. Use `make real-clean` to remove those caches and all
generated Flutter Rust Bridge Dart and Rust sources. `make dart` recreates the
bindings after a real clean.

## Build Targets

```bash
# Generate all Flutter Rust Bridge Dart and Rust binding files.
make dart

# Generate Flutter Rust Bridge bindings and build the Wellen WebAssembly bridge.
make wasm

# Build the native Wellen library used by desktop tests and applications.
make rust-native

# Build Flutter web artifacts.
make web-debug
make web-release

# Build Flutter Linux artifacts.
make linux-debug
make linux-release

# Build a VS Code extension package.
make extension
make vsix

# Build the versioned slim extension archive (`extension` alias).
make package
```

`vscode-extension/` is the sole extension source tree. `make extension`
compiles its TypeScript host, builds the Flutter web application, and stages
the runtime package under `build/extension/<name>-<version>/`. It then creates
the slim extension archive. `make vsix` packages that same staged directory as
`build/<name>-<version>.vsix`.

## Running Locally

Use the dependency-aware launcher for the supported application run modes:

```bash
bash scripts/wave_run.sh web-debug
bash scripts/wave_run.sh web-release
bash scripts/wave_run.sh linux-debug
bash scripts/wave_run.sh linux-release
```

The web modes start a server at `http://127.0.0.1:9299`. The launcher resolves
the Pub workspace and verifies the Flutter/Dart toolchain before starting.

For direct Makefile development targets, use:

```bash
make web-run
make linux-run-debug
make linux-run-release
```

`make web-run` uses port 9199 and is independent of `wave_run.sh`.

## VS Code Extension Installation

```bash
# Install the generated VSIX into local VS Code.
make install-local

# Package and install to a remote VS Code Server.
make install-remote
```

`make install` is an alias for `make install-remote`.

## WebAssembly Compatibility Patches

The Makefile runs `scripts/patch_wasm_binary.sh` and
`scripts/patch_wasm_js.sh` after creating the Wellen WebAssembly package.
It also runs `scripts/fix_bootstrap.py` after the Flutter web build. See
[WASM_WEBVIEW_PATCH.md](WASM_WEBVIEW_PATCH.md) for details.

## Validation and Cleanup

```bash
flutter analyze
tool/gh_actions/generate_documentation.sh
make test
make rust-test
make browser-test
make coverage
make pana

make clean
make real-clean
```

`make test` delegates to `tool/gh_actions/run_tests.sh`; pass `ARGS` to select
root-package tests, for example:

```bash
make test ARGS=test/services/signal_data_service_test.dart
```

`make coverage` runs the root Flutter tests and the `dart_wellen` package tests
with coverage, then merges both results into `coverage/lcov.info` and the HTML
report. Rust tests remain a separate `make rust-test` validation gate.

`make browser-test` builds the Wellen WebAssembly bridge and runs the
`dart_wellen` browser integration test in Chrome through both Dart2Js and
Dart2Wasm. It validates bridge initialization and representative waveform
values from a tracked fixture. CI runs this in a dedicated hosted-Ubuntu job
with an explicitly installed Chrome, using the generated bindings and WASM
assets from the main build job.

---

Copyright (C) 2023-2026 Intel Corporation
SPDX-License-Identifier: BSD-3-Clause
