# Changelog

## 0.1.1

- Prevent stale registration results from hiding Send Signal after a receiver appears, and accept numeric source coordinates from the Wasm host.
- Preserve already-decoded host messages and replay queued waveform loads, and deliver readiness metadata directly through the typed JavaScript callback.
- Fix incoming cross-probe signal selections in the Wasm viewer by decoding JavaScript host messages into Dart maps and lists, and distinguish empty selections from self-originated messages in diagnostics.
- Broaden the hierarchy and waveform dependency constraints to accept 0.1.x and 0.2.x, and require `dart_wellen` 0.1.1 for the same compatibility.
- Accept DevTools widgets 0.1.1 through 0.2.x without requiring the new widgets release first.
- Accept ROHD 0.6.11 and 0.7.x, and Equatable 2.x and 3.x.
- Update Flutter Rust Bridge and its generator to 2.7.1.
- Accept Cupertino Icons 1.x and 2.x and retain flexible Material UI 1.x constraints, allowing both the published widgets' older UI stack and Material UI 1.7.0 with widgets 0.2.0 without increasing the Dart or Flutter lower bounds.
- Extension compatible with Microsoft MarketPlace.
- Publish coverage badges from an isolated checkout so generated build changes cannot prevent updates to the badges branch.
- Fix structure and array chevrons in Selected Signals to track expansion per monitor row and collapse their generated fields.

## 0.1.0

This release advances the mock-backed `0.0.1` Flutter prototype into a fully-featured file-backed waveform analysis application, VS Code extension, and reusable Flutter package.

## 0.0.1

- Original ROHD Wave Viewer mockup released in `intel/rohd-wave-viewer`.
