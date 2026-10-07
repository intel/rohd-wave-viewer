# Building the Wellen Bridge

Run supported bridge builds from the ROHD Wave Viewer repository root. The
root Makefile tracks both generated binding files and applies the WebAssembly
patches required by the VS Code webview.

## Toolchain

The development and CI toolchain uses:

- the repository-pinned Rust toolchain with the `wasm32-unknown-unknown`
  target;
- the Flutter Rust Bridge code generator;
- wasm-pack and wasm-bindgen-cli;
- LLVM/Clang and `libclang` for binding generation; and
- Binaryen and wabt for WebAssembly inspection and patching.

The setup scripts and package manifests are authoritative for compatible
versions; this guide does not duplicate them.

Install or verify those tools with the repository scripts:

```bash
tool/gh_actions/install_rust_1_92.sh
tool/gh_actions/install_wasm_tools.sh
tool/gh_actions/install_build_tools.sh
tool/gh_actions/install_dependencies.sh
```

## Generate Bindings

```bash
make dart
```

This command uses
`packages/dart_wellen/flutter_rust_bridge.yaml` and updates both:

- `packages/dart_wellen/lib/src/rust/frb_generated.dart`
- `rust/wellen_bridge/src/frb_generated.rs`

The Cargo manifest, bridge configuration, handwritten `src/api.rs`, and
generator script are prerequisites. Native and WebAssembly builds also depend
on both generated files.

## Native Build

```bash
make rust-native
```

The platform-specific release library is written under
`rust/wellen_bridge/target/release/`. On Linux the expected artifact is
`libwellen_bridge.so`.

Run the crate tests with the pinned toolchain:

```bash
make rust-test
```

## WebAssembly Build

```bash
make wasm
```

This command:

1. generates bindings when required;
2. runs wasm-pack with the `no-modules` target;
3. writes the generated package under `web/pkg/`;
4. patches the WebAssembly binary for VS Code webview compatibility; and
5. patches the JavaScript loader to match the adjusted imports.

Do not package a raw wasm-pack output for the extension. The post-build patches
are part of the supported artifact. See the
[WASM webview patch guide](../../doc/WASM_WEBVIEW_PATCH.md) for their
rationale.

## Application and Extension Builds

The bridge is prepared automatically by higher-level targets:

```bash
make linux-release
make web-release
make extension
make vsix
```

Use `make extension` for the staged slim extension archive and `make vsix` for
the installable VSIX.

## Cleanup

```bash
make clean
make real-clean
```

`make clean` removes Flutter and staged extension output while retaining
dependency caches and Rust/WASM build output. `make real-clean` also removes
the retained Node, Rust, WASM, and related caches.

## Troubleshooting

- If either generated binding is missing, rerun `make dart`.
- If binding generation cannot locate Clang, run
  `tool/gh_actions/install_build_tools.sh` and verify `LIBCLANG_PATH`.
- If wasm-pack or wasm-bindgen reports a version mismatch, rerun
  `tool/gh_actions/install_wasm_tools.sh` rather than installing an unpinned
  version.
- If Flutter cannot load the native bridge, rebuild with `make rust-native`
  and verify the platform library under `target/release/`.

---

Copyright (C) 2024-2026 Intel Corporation
SPDX-License-Identifier: BSD-3-Clause
