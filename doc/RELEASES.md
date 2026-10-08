# Releases

## Release Inventory

The repository produces independently releasable packages and applications.
They do not need to share a version or ship together. A release selects only
the components that changed, except where one selected package has a hosted
dependency on another.

| Component | Distribution | Version source | Release relationship |
| --- | --- | --- | --- |
| `dart_wellen` | pub.dev package from `packages/dart_wellen` | `packages/dart_wellen/pubspec.yaml` | Publish before any new `rohd_wave_viewer` version that depends on it. Native and WebAssembly callers must also stage the matching bridge artifact. |
| `rohd_wave_viewer` | Embeddable pub.dev Flutter package from the repository root | Root `pubspec.yaml` | Requires its declared `dart_wellen` constraint to resolve from pub.dev. It can be released without Pages, Linux, or VSIX releases. |
| Hosted Wave Viewer | GitHub Pages application built by `.github/workflows/app.yml` | Deployment source commit; no independent package version | Deploys workspace source and does not prove pub.dev readiness. |
| Linux Wave Viewer | Flutter Linux application bundle under `build/linux` | Root application metadata at the selected source commit | Build and distribute when a Linux application release is wanted; it does not force either Pub package or other application distributions to release. |
| ROHD Wave Viewer extension | Slim ZIP or VSIX built from `vscode-extension` | `vscode-extension/package.json` | Versioned and released independently. `package-lock.json` must match the extension manifest; packaging never rewrites it from the root Pub version. |

## Non-Publishing Preparation

Run preparation from a clean release commit that contains current canonical
`main`:

```bash
# Both Pub packages, using their independent manifest versions.
tool/prepare_release.sh

# One selected package.
tool/prepare_release.sh dart_wellen
tool/prepare_release.sh rohd_wave_viewer

# Optional local repetitions of the full suites and Pana.
tool/prepare_release.sh --run-tests dart_wellen
tool/prepare_release.sh --run-pana dart_wellen
tool/prepare_release.sh --run-tests --run-pana rohd_wave_viewer
```

The helper:

- validates package metadata and changelog headings;
- fetches canonical `main` and verifies source ancestry;
- generates Flutter Rust Bridge bindings;
- builds and validates matching native and WebAssembly bridge artifacts;
- resolves, formats, and analyzes selected packages;
- verifies hosted-only root resolution when `rohd_wave_viewer` is selected;
- runs publication dry runs only for selected packages; and
- reports each stage independently.

It never uploads packages or artifacts and never commits, tags, pushes, merges,
rebases, or rewrites package versions. Full tests and Pana remain independent
local opt-ins. The manually dispatched **Release Checks** workflow runs the
same preparation in CI with independent test and Pana inputs.

## Pub.dev Order

Publish the two packages in dependency order:

1. Run preparation and required CI for `dart_wellen`.
2. Manually publish `dart_wellen` from its package directory.
3. Wait until the exact version is visible on pub.dev.
4. Verify availability with:

   ```bash
   dart pub cache add dart_wellen --version <version>
   ```

5. Run preparation and required CI for `rohd_wave_viewer`. Its hosted-only
   resolution must now pass.
6. Manually publish `rohd_wave_viewer` from the repository root.

The exact `flutter_rust_bridge` constraint intentionally matches the generated
Dart/Rust bridge version. Preparation narrowly recognizes Pub's corresponding
single-version warning; any additional publication warning still fails.

Publishing `dart_wellen` distributes its Dart API and generated bindings.
Applications that call its Wellen-backed reader must additionally stage the
matching native library or WebAssembly JavaScript/module pair. Hosts that embed
`EmbeddedWaveViewer` with their own `SignalWaveformApi` do not initialize the
Wellen bridge.

## Required CI and Manual Publication

Before either manual publication:

1. Require the **General** workflow to pass for the exact release commit.
2. Run **Release Checks** for the selected package and require it to pass.
3. Review the dry-run archive and its narrowly documented exception, if any.
4. Publish using the authorized pub.dev publisher account.

Publication, commits, tags, pushes, GitHub releases, Pages deployments, Linux
archives, and VSIX publication remain explicit maintainer actions outside the
helper.

---

Copyright (C) 2026 Intel Corporation
SPDX-License-Identifier: BSD-3-Clause
