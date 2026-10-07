# Hierarchy and Waveform Contracts

ROHD Wave Viewer uses the published `rohd_hierarchy` and `rohd_waveform`
packages for shared hierarchy, signal, and waveform contracts. They are
declared in the root `pubspec.yaml`; neither package is a directory in this
repository's Pub workspace.

The local workspace members are:

```text
packages/dart_wellen
```

`dart_wellen` parses VCD, FST, and GHW files through the Wellen bridge. The
viewer keeps its backend-neutral waveform client state in
`lib/src/waveform_client_core/`; it is isolated for eventual migration to
`rohd_waveform`.

## Using the Contracts

Consumers should declare the published packages in their own `pubspec.yaml`,
using constraints compatible with the root application manifest.

Run `flutter pub get` or `dart pub get` after changing dependencies.

The contract packages define the shared models used to represent module
hierarchy and signal occurrences. The viewer receives a module structure from
its waveform API, uses it to populate the hierarchy and signal panes, and
uses the selected signal occurrences to retrieve waveform data from its
repository-backed service.

## Viewer Integration

The relevant local code is:

| Path | Responsibility |
| --- | --- |
| `packages/dart_wellen/` | Wellen-backed waveform loading for native and web targets |
| `lib/src/waveform_client_core/waveform_repository.dart` | Cached waveform and signal state |
| `lib/src/waveform_client_core/signal_data_service_impl.dart` | Repository-backed signal-data adapter |
| `lib/src/viewer_waveform_client.dart` | Viewer-owned migration and compatibility seam |
| `lib/src/modules/rohd_module/` | Loaded hierarchy and module-selection state |
| `lib/src/modules/hierarchy/` | Hierarchy presentation |
| `lib/src/modules/signal/` | Signal selection and monitored rows |

For the current application-level flow and diagrams, see
[ARCHITECTURE.md](ARCHITECTURE.md).

## Local ROHD Development

The application can resolve compatible ROHD dependencies from pub.dev, Git, or
a local ROHD checkout. Use `scripts/wave_dev_mode.sh` rather than manually
adding path overrides:

```bash
# Display the selected sources.
bash scripts/wave_dev_mode.sh show

# Select published packages for all configurable ROHD dependencies.
bash scripts/wave_dev_mode.sh configure-group all hosted
```

See [DEVELOPER.md](DEVELOPER.md) for the supported dependency groups and
environment variables.

## Signal Filtering

The viewer's module-signal filter is a UI feature, not a general hierarchy API.
It supports case-insensitive prefix matching and `*`/`?` wildcards. See
[SIGNAL_FILTERING.md](SIGNAL_FILTERING.md) for its exact behavior.

---

Copyright (C) 2023-2026 Intel Corporation
SPDX-License-Identifier: BSD-3-Clause
