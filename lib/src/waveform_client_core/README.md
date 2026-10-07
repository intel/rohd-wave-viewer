# Waveform Client Core

This directory is a source-move unit intended for
`github.com/intel/rohd`'s `packages/rohd_waveform`. It contains Wave Viewer's
backend-neutral waveform client state, but it must remain independently
movable: it cannot depend on code anywhere else in
`rohd-wave-viewer`.

## Current API

`waveform_client_core.dart` exports:

- `SignalWaveform` and `MonitorValueFormat`, which represent cached waveform
  samples and monitor-row state;
- `SignalWaveformRepository`, which bridges `SignalWaveformApi` to cached
  hierarchy and waveform data; and
- `RepositorySignalDataService`, which adapts the repository to
  `SignalDataService`.

The module may import only:

- Dart SDK libraries;
- `package:rohd_hierarchy`;
- `package:rohd_waveform`; and
- another file under `waveform_client_core`.

It must not import Flutter, BLoC, file-picking, session persistence, VS Code,
or any other `rohd_wave_viewer` source. The CI
`verify_waveform_client_core.sh` check enforces this dependency boundary.

Its cache and repository APIs are migration candidates; monitor-row fields
remain here only while they share the same data model and must be separated
before a `rohd_waveform` release that omits viewer policy.

## Viewer Integration Boundary

Wave Viewer code imports `viewer_waveform_client.dart`, not this directory.
That facade is the only integration seam. It allows the viewer to retain
viewer-specific adapters when this core is moved.

## Future Migration

When `rohd_waveform` is ready for a release:

1. Copy this directory and its focused tests to `packages/rohd_waveform`.
2. Replace the `package:rohd_wave_viewer/src/waveform_client_core/` self-URI
   prefix with the new package's internal URI prefix.
3. Preserve the API contracts or provide compatibility adapters there.
4. Update `rohd_waveform` to permit `equatable ^3.0.0` after validating that
   upgrade in the ROHD repository. Its current `equatable ^2.0.5` constraint
   prevents this viewer from adopting Equatable 3 and costs the viewer Pana
   dependency-freshness points.
5. Publish that compatible `rohd_waveform` release, then update this viewer's
   `equatable` constraint to `^3.0.0`.
6. Change `viewer_waveform_client.dart` to export the migrated package API.
7. Keep only viewer-specific behavior in this repository, such as BLoCs,
   monitor-list persistence, display widgets, and VS Code integration.

Do not add new UI behavior to this directory. If a new type needs Flutter or
viewer session state, place it with the owning viewer feature instead.

---

Copyright (C) 2024-2026 Intel Corporation
SPDX-License-Identifier: BSD-3-Clause
