# Wellen Bridge

`wellen_bridge` is the Rust implementation behind the ROHD Wave Viewer's
`dart_wellen` package. It uses
[Wellen](https://github.com/ekiwi/wellen) to parse VCD, FST, and GHW data and
[Flutter Rust Bridge](https://cjycode.com/flutter_rust_bridge/) to expose the
parser to native Dart and browser WebAssembly.

Application code should consume `package:dart_wellen/dart_wellen.dart` rather
than call this crate directly.

## Bridge API

The handwritten API is in `src/api.rs` and exposes these operations to
generated bindings:

- `load_waveform` for a native file path;
- `load_waveform_from_bytes` for in-memory data;
- `get_waveform_structure`;
- `get_waveform_data` for selected signals and an optional time range;
- `get_max_timestamp` and `get_all_timestamps`;
- `is_waveform_loaded`; and
- `unload_waveform`.

The bridge keeps one loaded waveform in process-wide state. Loading another
waveform replaces it.

## Supported Outputs

The crate builds as `cdylib`, `staticlib`, and `rlib`:

- native builds place a platform-specific library under
  `rust/wellen_bridge/target/release/`;
- WebAssembly builds place the wasm-pack package under `web/pkg/`; and
- Flutter Rust Bridge generation writes `src/frb_generated.rs` plus the Dart
  bindings under `packages/dart_wellen/lib/src/rust/`.

The repository validates Linux native and browser WebAssembly outputs.

## Build

Use the root Makefile so code generation, patches, and artifact dependencies
remain synchronized:

```bash
make dart         # Generate Dart and Rust bridge bindings.
make rust-native  # Build the native library.
make wasm         # Build and patch the wasm-pack package.
make rust-test    # Run Rust tests with the pinned toolchain.
```

The repository's `rust/wellen_bridge/BUILDING.md` and `doc/BUILD.md` guides
describe the authoritative toolchain setup and installation commands.

## Source Layout

```text
rust/wellen_bridge/
├── Cargo.toml
├── src/
│   ├── api.rs
│   ├── frb_generated.rs
│   └── lib.rs
├── build_native.sh
└── build_wasm.sh
```

`frb_generated.rs` is generated. Change the handwritten API or generator
configuration, then run `make dart`; do not edit generated bindings manually.

---

Copyright (C) 2024-2026 Intel Corporation
SPDX-License-Identifier: BSD-3-Clause
