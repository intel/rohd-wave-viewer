# Changelog

## 0.1.0

This release advances the mock-backed `0.0.1` Flutter prototype into a fully-featured file-backed waveform analysis application, VS Code extension, and reusable Flutter package.

### Added

- Loads VCD, FST, and GHW waveforms on native and web platforms through the new `dart_wellen` package, a Rust Wellen bridge, and WebAssembly support.
- Adds a Visual Studio Code custom editor for `.vcd`, `.fst`, and `.ghw` files, a hosted browser application with local file selection, and a Linux desktop application that accepts a waveform path on the command line.
- Adds hierarchy navigation, internal-signal visibility controls, and case-insensitive signal filtering by name or hierarchy path with `*` and `?` wildcards and `Tab` completion.
- Adds single, range, and toggle selection; duplicate monitor rows; multi-row drag reorder; monitor-list undo and redo; and consistent waveform, binary, hexadecimal, octal, decimal, signed-decimal, and ASCII display formats.
- Adds structured-signal inspection for arrays, structures, named fields, bits, slices, and custom-width ranges when hierarchy metadata is available.
- Adds waveform panning, focal and region zoom, fit-to-view, transition navigation, rising-edge, falling-edge, value, and change searches, plus a primary marker and a measurement marker with delta-time and frequency.
- Adds versioned JSON session save and restore for monitored signals, display formats, groups, markers, filters, pane layout, row scale, and viewport. Reload preserves the active view, and visible panes can be exported as PNG.
- Adds host integration for incremental waveform updates, design snapshots, live tracking, ROHD and generated-source navigation, and bidirectional signal cross-probing with compatible viewers such as ROHD Schematic Viewer.
- Adds resizable and pinnable panes, light and dark themes, in-application help, and keyboard and mouse workflows for common analysis operations.
- Adds reproducible native, web, WebAssembly, Linux, and VS Code extension builds with package documentation and automated release-quality checks.

### Changed

- Replaces the mock-only `module_structure_api` and `module_structure_repository` packages with shared `rohd_hierarchy`, `rohd_waveform`, and `rohd_devtools_widgets` contracts centered on `SignalWaveformApi`.
- Defines the supported package surface around `EmbeddedWaveViewer`, `WaveViewerThemeMode`, and `WaveViewerHelpButton`; test mocks use the separate `testing.dart` entry point, while repositories, BLoCs, Cubits, painters, application-shell types, and mutable caches remain internal.
- Focuses standalone native application support on Linux and removes unused Android, iOS, macOS, and Windows runner scaffolding.

## 0.0.1

- Original ROHD Wave Viewer prototype released in `intel/rohd-wave-viewer`.
- Provides the initial resizable module, signal, selected-signal, value, and waveform panes.
- Uses `MockModuleStructureApi` and local `module_structure_api` and `module_structure_repository` packages to demonstrate hierarchy, signal selection, and waveform rendering with sample data.
