# Architecture Overview

ROHD Wave Viewer is a Flutter application for inspecting VCD, FST, and GHW
waveforms. It uses BLoCs for interactive viewer state and separates waveform
parsing, cached client state, and presentation.

## Workspace Layout

The Pub workspace has the root application and one member:

```text
.
├── lib/                              # Flutter application
│   └── src/waveform_client_core/      # Future rohd_waveform migration unit
├── packages/
│   └── dart_wellen/                   # Wellen Rust FFI bindings
└── rust/wellen_bridge/                # Native and WebAssembly Wellen bridge
```

`rohd_hierarchy`, `rohd_waveform`, and `rohd_devtools_widgets` are published
dependencies declared in `pubspec.yaml`; they are not workspace directories.

## System Overview

```text
                         ROHD Wave Viewer
┌──────────────────────────────────────────────────────────────────────┐
│ Flutter application (`lib/`)                                        │
│                                                                      │
│  main.dart / main_io.dart / main_web.dart                            │
│                    │                                                 │
│                    v                                                 │
│  App: repository, service, and BLoC providers                        │
│                    │                                                 │
│     ┌──────────────┼───────────────────────────────────────────┐     │
│     │              │                                           │     │
│     v              v                                           v     │
│  home          rohd_module                                  signal   │
│     │              │                                           │     │
│     └──────────────┼───────────────────────┐                   │     │
│                    v                       v                   v      │
│              hierarchy UI             waveform UI        monitor UI  │
└────────────────────┬───────────────────────┬─────────────────────────┘
                     │                       │
                     v                       v
      SignalWaveformRepository      RepositorySignalDataService
                     │                       │
                     └───────────┬───────────┘
                                 v
                 WellenSignalWaveformApi
                                 │
                  ┌──────────────┴──────────────┐
                  v                             v
         Native Rust bridge              WebAssembly bridge
           (Linux desktop)              (browser/webview)
                  │                             │
                  └─────────── Wellen ──────────┘
```

## Application Layers

### Entry points

- `lib/main.dart` selects native or web-compatible initialization, then starts
  `EmbeddedWaveViewer`.
- `lib/main_io.dart` initializes file-backed waveform loading for native
  targets.
- `lib/main_web.dart` initializes the Wellen WebAssembly API and receives
  waveform data and host integration messages when embedded in a VS Code
  webview.

### State and presentation

`lib/embedded_wave_viewer.dart` owns the repository lifecycle.
`lib/src/ui/wave_viewer_app.dart` provides the repository,
`SignalDataService`, and BLoCs to the widget tree. Feature modules live in
`lib/src/modules/`:

- `home/` coordinates file loading, sessions, pane layout, and viewer actions.
- `rohd_module/` owns loaded hierarchy and module selection state.
- `signal/` manages signal selection, monitored rows, formats, grouping, and
  filtering.
- `waveform/` renders waveform data and handles navigation and markers.
- `hierarchy/` renders the module tree and hierarchy controls.

Widgets rebuild from BLoC state; repositories and services are supplied with
`RepositoryProvider`.

### Waveform data

`packages/dart_wellen` wraps the Wellen parser for native and WebAssembly
targets. Its `WellenSignalWaveformApi` loads VCD, FST, and GHW data and exposes
the shared waveform contracts from `rohd_waveform`.

`lib/src/waveform_client_core/` contains `SignalWaveformRepository`, which
caches loaded signals and waveform data for the viewer. Its
`RepositorySignalDataService` adapts cached data for waveform presentation.
The viewer imports `viewer_waveform_client.dart`, a compatibility seam that
will adapt the API after the reusable core moves into `rohd_waveform`.

## Runtime Data Flow

### Native file load

```text
User chooses VCD, FST, or GHW file
                |
                v
platform initialization (`main_io.dart`)
                |
                v
WellenSignalWaveformApi loads file through the native bridge
                |
                v
SignalWaveformRepository caches hierarchy, signals, and transitions
                |
       +--------+---------+
       |                  |
       v                  v
RohdModuleBloc       Signal and waveform BLoCs
       |                  |
       v                  v
hierarchy/module UI   monitored rows, values, and waveform panels
```

### VS Code webview load

```text
VS Code extension posts waveform contents
                |
                v
`main_web.dart` receives a browser message
                |
                v
WellenSignalWaveformApi WebAssembly bridge loads bytes
                |
                v
SignalWaveformRepository and BLoCs update the Flutter UI
                |
                v
Embedded ROHD Wave Viewer renders the waveform
```

The web entry point also exposes a cross-probe service. When a compatible host
is available, it sends selected signal paths to the host and accepts incoming
signal selections.

## Build Outputs

```text
rust/wellen_bridge/
        |
        +-- native library --> Flutter Linux application
        |
        +-- WASM package ---> Flutter web build ---> staged VS Code extension
                                                       |
vscode-extension/ TypeScript host ---------------------+
                                                       v
                                             slim ZIP / VSIX package
```

`make wasm` builds the WebAssembly bridge. `make web-release` builds the web
application, and `make extension` combines that application with the compiled
host from `vscode-extension/` in a generated staging directory. See
[BUILD.md](BUILD.md) for environment setup and the complete target list.

## Related Documentation

- [Hierarchy contracts](HIERARCHY.md)
- [Signal filtering](SIGNAL_FILTERING.md)

---

Copyright (C) 2023-2026 Intel Corporation
SPDX-License-Identifier: BSD-3-Clause
