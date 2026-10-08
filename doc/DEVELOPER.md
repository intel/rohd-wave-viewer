# Developer Guide

This guide covers local development arrangements that are not needed to use
ROHD Wave Viewer as an application or widget.

## Flutter and Dart Toolchain

GitHub Actions and the development container explicitly pin the same Flutter
version. Flutter provides its own Dart SDK, so CI does not install a separate
Dart toolchain that could conflict with Flutter.

The root `pubspec.yaml` declares package compatibility, while
`scripts/verify_flutter_version.sh` defines the development compatibility
check. Check the active Flutter and Dart pair with:

```bash
bash scripts/verify_flutter_version.sh
```

When the CI pin changes, update the three GitHub Actions workflows and
`tool/gh_codespaces/install_flutter.sh` together.

## Pub Workspace

The repository is one Pub workspace containing:

- the root `rohd_wave_viewer` Flutter application;
- `packages/dart_wellen`.

Run `flutter pub get` once from the repository root. Pub resolves the
packages into the root `.dart_tool/package_config.json` and `pubspec.lock`.
Workspace members do not maintain separate lockfiles or dependency overrides.
The root application uses a version constraint for `dart_wellen`; Pub selects
its workspace copy automatically.

For a multi-root VS Code view matching the package layout, open
`rohd-wave-viewer-multipackage.code-workspace`. It exposes the application and
the workspace member as top-level folders while retaining the shared
repository configuration.

## Dependency Sources

The viewer can resolve its ROHD dependencies from pub.dev, Git, or a compatible
local ROHD checkout. Use the supplied scripts and VS Code tasks instead of
editing `pubspec.yaml` or `pubspec_overrides.yaml` by hand.

| VS Code task | Dependencies configured |
| --- | --- |
| `Configure ROHD Dependency` | `rohd` |
| `Configure ROHD Package Dependencies` | `rohd_hierarchy`, `rohd_waveform`, `rohd_devtools_widgets` |
| `Configure Wave Viewer Package Dependencies` | Repository packages, currently `dart_wellen` |
| `Configure All ROHD Dependencies` | `rohd` and all ROHD companion packages; leaves Wave Viewer packages unchanged |

Each task prompts for `hosted`, `git`, or `local`. Hosted is the default and
uses the versions declared in `pubspec.yaml`. ROHD Git sources default to
`https://github.com/intel/rohd.git` at `main`, and local ROHD sources default
to `~/release/rohd`. After selecting Git or local, the task prompts for the
applicable repository and ref or checkout path. All Git-backed ROHD bundles
share the same repository and ref, and all local ROHD bundles share the same
checkout root. Wave Viewer Git sources default to this checkout's origin and
current branch; local Wave Viewer packages use the Pub workspace and need no
path prompt. The selected sources and shared settings persist across task
runs, allowing one dependency bundle to be changed without resetting the
others. The root application always remains local.

## Select Dependency Sources

Run a VS Code configuration task, or use the script directly:

```bash
# Use hosted ROHD dependencies and workspace-local dart_wellen.
bash scripts/wave_dev_mode.sh manifest

# Configure every ROHD dependency from pub.dev without changing dart_wellen.
bash scripts/wave_dev_mode.sh configure-group all hosted

# Configure the ROHD companion packages from the ROHD main branch.
WAVE_SOURCE_VALUE=github.com/intel/rohd:main \
  bash scripts/wave_dev_mode.sh configure-group rohd-packages git

# Configure the ROHD companion packages from a local checkout.
WAVE_SOURCE_VALUE=~/release/rohd \
  bash scripts/wave_dev_mode.sh configure-group rohd-packages local

# Use this checkout's Wave Viewer packages, including dart_wellen.
bash scripts/wave_dev_mode.sh configure-group viewer-packages local

# Resolve Wave Viewer packages from the current Git origin and branch.
bash scripts/wave_dev_mode.sh configure-group viewer-packages git

# Resolve Wave Viewer packages from another Git repository and ref.
WAVE_SOURCE_VALUE=github.com/desmonddak/rohd-wave-viewer:modernize \
  bash scripts/wave_dev_mode.sh configure-group viewer-packages git

# Resolve packages after changing modes.
flutter pub get
```

The committed manifests use published `rohd`, `rohd_hierarchy`,
`rohd_waveform`, and `rohd_devtools_widgets` packages.
`lib/src/waveform_client_core/` contains backend-neutral Wave Viewer client
state and depends on the published `rohd_waveform` service contracts. Its
README defines the boundary for eventual migration into `rohd_waveform`.
Any selection that differs from the manifest baseline writes one ignored
override at the workspace root, which applies to every member. Selecting
hosted or Git Wave Viewer packages also disables the local Pub workspace so
`dart_wellen` can resolve from the selected external source. That source must
contain or publish a compatible `dart_wellen` version.

Set `ROHD_LOCAL_PATH` to use a different compatible ROHD checkout containing:

- `packages/rohd_hierarchy`
- `packages/rohd_waveform`
- `packages/rohd_devtools_widgets`

For compatibility with checkouts made before the package move, local mode also
recognizes
`rohd_devtools_extension/packages/rohd_devtools_widgets`. Git mode uses the
current `packages/rohd_devtools_widgets` layout.

For non-interactive use, set `WAVE_SOURCE_VALUE` to `repository:ref` for Git or
to a checkout path for local ROHD packages. The existing `ROHD_GIT_URL`,
`ROHD_GIT_REF`, `ROHD_LOCAL_PATH`, `WAVE_VIEWER_GIT_URL`, and
`WAVE_VIEWER_GIT_REF` variables remain supported. The generated overrides point
directly to Git or the local checkout; no repository-local symlink is created.
The helper records the selected bundle modes in the ignored
`.wave_dependency_sources` file. Before replacing a generated override, it
preserves the previous file as `pubspec_overrides.yaml.disabled` (then
`.disabled.1`, `.disabled.2`, and so on). It refuses to replace an unmanaged
override.
Inspect the saved sources and generated files with:

```bash
bash scripts/wave_dev_mode.sh show
```

## Run Targets

Configure dependency sources separately, then use `wave_run.sh` to resolve the
current configuration and start the requested target:

```bash
# Browser web server on http://localhost:9299
bash scripts/wave_run.sh web-debug

# Release web server
bash scripts/wave_run.sh web-release

# Native Linux application
bash scripts/wave_run.sh linux-debug

# Release Linux application
bash scripts/wave_run.sh linux-release
```

The matching VS Code tasks are named `ROHD Wave Viewer: Web Debug`,
`ROHD Wave Viewer: Web Release WASM`, and the corresponding Linux tasks.

## Validation

Run focused checks before a broader test suite:

```bash
flutter analyze
tool/gh_actions/generate_documentation.sh
make test
make pana
```

The documentation script generates the public API for both
`rohd_wave_viewer` and `dart_wellen` and fails on DartDoc warnings.

`make test` builds the native Wellen bridge, runs the root Flutter tests, and
then runs each workspace member's tests. Pass `ARGS` to select only root-package
tests:

```bash
make test ARGS=test/services/signal_data_service_test.dart
```

`make pana` copies the workspace to an isolated directory, verifies both the
normal and downgraded hosted dependency resolutions with the analyzer, and
then analyzes the independently publishable `dart_wellen` package. It checks
the root Flutter package too once `dart_wellen` is available on pub.dev; until
then, it reports that the root check was skipped. The script probes pub.dev for
the version declared by the root manifest before running the root analysis.

## Publishing

The release set contains two independently versioned pub.dev packages. Prepare
and publish them in dependency order:

1. `packages/dart_wellen`
2. the root `rohd_wave_viewer` package

Use the non-publishing release helper from a clean release commit:

```bash
tool/prepare_release.sh dart_wellen
tool/prepare_release.sh rohd_wave_viewer
```

Full local tests and Pana are independent opt-ins:

```bash
tool/prepare_release.sh --run-tests dart_wellen
tool/prepare_release.sh --run-pana rohd_wave_viewer
```

The root preparation must wait until its declared `dart_wellen` version is
available from pub.dev. Publish manually only after required General and Release
Checks CI pass for the release commit. See [RELEASES.md](RELEASES.md) for the
complete inventory, bridge-artifact requirements, and manual order.

---

Copyright (C) 2024-2026 Intel Corporation
SPDX-License-Identifier: BSD-3-Clause
