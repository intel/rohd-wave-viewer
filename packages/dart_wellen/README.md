# dart_wellen

`dart_wellen` exposes the Rust
[Wellen](https://github.com/ekiwi/wellen) waveform parser to Dart through
Flutter Rust Bridge. It reads VCD, FST, and GHW waveforms and adapts them to
the shared `rohd_hierarchy` and `rohd_waveform` contracts.

## Capabilities

| Operation | Native | WebAssembly |
| --- | --- | --- |
| Read VCD, FST, or GHW from a file path | Yes | No |
| Read VCD, FST, or GHW from bytes | Yes | Yes |
| Query hierarchy and selected signal data | Yes | Yes |
| Write VCD | Yes | No |
| Write FST or GHW | No | No |

Writing is deliberately separated from the cross-platform reader because it
uses `dart:io`.

## Installation

Add the package to a Dart or Flutter package:

```yaml
dependencies:
  dart_wellen: ^0.1.0
```

Applications also need the matching native or WebAssembly bridge artifact. The
ROHD Wave Viewer build system prepares those artifacts automatically.

## Reading a Waveform

`WellenReader` is a convenience API for native, file-backed workflows:

```dart
import 'package:dart_wellen/dart_wellen.dart';

Future<void> inspectWaveform(String path) async {
  await WellenReader.init();
  final reader = WellenReader();

  try {
    final metadata = await reader.loadFile(path);
    final structure = await reader.getStructure();
    final signals = await reader.getSignalData(
      ['top.clk', 'top.counter'],
      startTime: 0,
      endTime: metadata.endTime,
    );

    print('${structure.modules.length} top-level modules');
    for (final waveform in signals) {
      print('${waveform.signalId}: ${waveform.data.length} changes');
    }
  } finally {
    await reader.close();
  }
}
```

`WellenSignalWaveformApi` implements the `SignalWaveformApi` contract used by
ROHD viewers. Use `loadFile` on native platforms or `loadBytes` after the
generated Wellen WebAssembly module has been initialized in a browser:

```dart
final api = WellenSignalWaveformApi();
await api.loadBytes(bytes, fileName: 'simulation.fst');

final hierarchy = await api.getModuleStructureOnly();
final waveforms = await api.getWaveformData(
  signalIds: ['top.clk'],
);
```

Only one waveform is held by the Rust bridge at a time. Creating multiple Dart
reader or API objects does not create independent Rust waveform stores.

## Writing VCD

Native code that writes waveforms must import the IO-specific library:

```dart
import 'package:dart_wellen/dart_wellen_io.dart';
```

- `WellenWriter` writes registered `SignalOccurrence` values directly to a VCD
  file.
- `WellenWaveDumper` provides a manual adapter that registers signals and
  records timestamped value changes.

The adapter is not automatically attached to the ROHD simulator. Callers must
register signals and forward simulation changes themselves. Selecting
`WaveFormat.fst` currently throws an unsupported-format error.

## Repository Development

This package is a member of the ROHD Wave Viewer Pub workspace. From the
repository root:

```bash
# Resolve the workspace.
flutter pub get

# Generate both Dart and Rust Flutter Rust Bridge bindings.
make dart

# Build native or WebAssembly bridge artifacts.
make rust-native
make wasm

# Run root and workspace-member tests.
make test
```

The generator configuration is
`packages/dart_wellen/flutter_rust_bridge.yaml`. Generated Dart bindings are
written to `packages/dart_wellen/lib/src/rust/`; the generated Rust counterpart
is `rust/wellen_bridge/src/frb_generated.rs`. Do not invoke the generator with
ad hoc output paths.

See [ARCHITECTURE.md](ARCHITECTURE.md) for package boundaries and the
[repository build guide](../../doc/BUILD.md) for the complete build matrix.

---

Copyright (C) 2024-2026 Intel Corporation
SPDX-License-Identifier: BSD-3-Clause
