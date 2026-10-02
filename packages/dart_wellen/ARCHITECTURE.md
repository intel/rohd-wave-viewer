# dart_wellen Architecture

## Purpose

`dart_wellen` is the Dart-facing boundary around the Rust Wellen parser. It
converts generated Flutter Rust Bridge values into shared ROHD hierarchy and
waveform models so applications do not depend on bridge-specific types.

The repository deliberately separates:

1. public Dart APIs in `packages/dart_wellen`;
2. generated Dart bindings in `packages/dart_wellen/lib/src/rust`;
3. handwritten and generated Rust bridge code in `rust/wellen_bridge`; and
4. application state and presentation in the root `rohd_wave_viewer` package.

## Public Libraries

### `dart_wellen.dart`

The cross-platform entry point exports:

- `WellenReader`, a file-oriented convenience reader;
- `WellenSignalWaveformApi`, the implementation of the shared
  `SignalWaveformApi` contract; and
- hierarchy and waveform model types needed by callers.

`WellenSignalWaveformApi.loadBytes` is the browser-compatible loading path.
The host must initialize the generated Wellen WebAssembly module before
Flutter Rust Bridge attaches to it.

### `dart_wellen_io.dart`

The native-only entry point exports:

- `WellenWriter`; and
- `WellenWaveDumper`.

These classes use `dart:io` and currently write VCD only.

## Read Data Flow

```text
file path (native) or bytes (native/web)
                  |
                  v
WellenReader / WellenSignalWaveformApi
                  |
                  v
generated Flutter Rust Bridge bindings
                  |
                  v
rust/wellen_bridge/src/api.rs
                  |
                  v
Wellen parser and process-wide waveform state
                  |
                  v
ModuleStructure / WaveformData
```

The Rust bridge stores one loaded waveform in process-wide state. Subsequent
loads replace that waveform. Dart objects therefore share the underlying
store even though they maintain their own converted-structure caches.

Signal values are loaded on demand. The hierarchy conversion records the
mapping between ROHD occurrence addresses and Wellen signal identifiers, and
waveform requests ask the bridge only for the selected identifiers and
optional time range.

`WellenSignalWaveformApi` exposes times through the `rohd_waveform` contract in
picoseconds. The bridge metadata retains the input timescale used for
conversion.

## Write Data Flow

`WellenWriter` and `WellenWaveDumper` implement native VCD output directly in
Dart. They do not use the Rust Wellen reader and are not automatically
registered with a ROHD simulation. An integration layer must enumerate
`SignalOccurrence` objects and forward timestamped changes.

FST and GHW writing are not implemented.

## Code Generation

The authoritative generator configuration is
`packages/dart_wellen/flutter_rust_bridge.yaml`. Run generation from the
repository root:

```bash
make dart
```

The Makefile treats both generated outputs as one grouped target:

- `packages/dart_wellen/lib/src/rust/frb_generated.dart`
- `rust/wellen_bridge/src/frb_generated.rs`

Changes to the Cargo manifest, bridge configuration, Rust API, or generator
script trigger regeneration. Native and WebAssembly builds depend on both
files, preventing a partially generated bridge from appearing current.

## Build Artifacts

```bash
make rust-native  # Platform-native dynamic library.
make wasm         # wasm-pack package under web/pkg/.
make test         # Native bridge plus root and workspace tests.
```

The repository's release gates validate Linux native and browser WebAssembly
builds. Consumers targeting other platforms must provide and validate the
appropriate native bridge artifact.

## Dependency Boundary

The package depends on published `rohd_hierarchy` and `rohd_waveform`
contracts. It is a member of the root Pub workspace during repository
development, so its normal local resolution requires no path override. The
dependency-source helper can disable that workspace when explicitly testing a
hosted or Git `dart_wellen` release.

---

Copyright (C) 2024-2026 Intel Corporation
SPDX-License-Identifier: BSD-3-Clause
