# Releases

## Release Inventory

The repository produces independently releasable packages and applications.
The root `rohd_wave_viewer` Pub package and ROHD Wave Viewer VSIX are a
matched release pair: they share the root `pubspec.yaml` version and use the
same `v<version>` release tag. Other components can release independently,
except where one selected package has a hosted dependency on another.

| Component | Distribution | Version source | Release relationship |
| --- | --- | --- | --- |
| `dart_wellen` | pub.dev package from `packages/dart_wellen` | `packages/dart_wellen/pubspec.yaml` | Publish before any new `rohd_wave_viewer` version that depends on it. Native and WebAssembly callers must also stage the matching bridge artifact. |
| `rohd_wave_viewer` | Embeddable pub.dev Flutter package from the repository root | Root `pubspec.yaml` | Requires its declared `dart_wellen` constraint to resolve from pub.dev. Its version must match the companion VSIX. |
| Hosted Wave Viewer | GitHub Pages application built by `.github/workflows/app.yml` | Deployment source commit; no independent package version | Deploys workspace source and does not prove pub.dev readiness. |
| Linux Wave Viewer | Flutter Linux application bundle under `build/linux` | Root application metadata at the selected source commit | Build and distribute when a Linux application release is wanted; it does not force either Pub package or other application distributions to release. |
| ROHD Wave Viewer extension | Slim ZIP or VSIX built from `vscode-extension` | Root `pubspec.yaml`, mirrored in `vscode-extension/package.json` and `package-lock.json` | Ships with the matching `rohd_wave_viewer` Pub version. Packaging and CI fail if either extension manifest drifts from `pubspec.yaml`. |

## Non-Publishing Preparation

Run preparation from a clean release commit that contains current canonical
`main`:

```bash
# The first package in dependency order (dart_wellen).
tool/prepare_release.sh

# Explicit package selection.
tool/prepare_release.sh dart_wellen
tool/prepare_release.sh rohd_wave_viewer

# Optional local repetitions of the full suites and Pana.
tool/prepare_release.sh --run-tests dart_wellen
tool/prepare_release.sh --run-pana dart_wellen
tool/prepare_release.sh --run-tests --run-pana rohd_wave_viewer
```

Keep the checked-in workspace `pubspec.lock` resolved against hosted external
dependencies. Local development overrides are ignored by Git, but Pub records
their absolute paths in that tracked lockfile; do not commit those paths.
Before signing a release-preparation commit, resolve in a disposable checkout
without local overrides and include its hosted lockfile. CI dependency
installation must leave the committed lockfile unchanged, otherwise the
clean-source provenance check stops preparation before building a bundle.

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
same preparation in CI with independent test and Pana inputs. Release Checks
is not triggered by branch pushes. Its optional manual-dispatch
`publish_bundle` input enables a separate CI job that publishes only the
verified bridge bundle to the pinned GitHub release URL. It defaults to off;
it does not publish Pub packages, Pages, Linux archives, or VSIX packages.

The no-argument default prepares only `dart_wellen`. This avoids implying that
the root package is release-ready before its first hosted dependency exists.
After `dart_wellen` is published, select `rohd_wave_viewer` explicitly.

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
6. Stage the embedding package without its independently published bridge:

   ```bash
   bash tool/stage_hosted_viewer.sh
   cd build/pub/rohd_wave_viewer
   flutter pub publish --dry-run
   ```

   Manually publish from that staging directory, not the workspace root.
   The helper refuses an existing destination to prevent stale publication
   files; choose a new destination for a subsequent staging run.

The exact `flutter_rust_bridge` constraint intentionally matches the generated
Dart/Rust bridge version. Preparation narrowly recognizes Pub's corresponding
single-version warning; any additional publication warning still fails.

Publishing `dart_wellen` distributes its Dart API, generated bindings, and
matching JavaScript/WebAssembly runtime under `web/pkg`, including license
notices. Native applications must additionally stage the matching native library.
Hosts that embed
`EmbeddedWaveViewer` with their own `SignalWaveformApi` do not initialize the
Wellen bridge.

### Consumer Web Artifacts: Local, Git, and Hosted

The viewer owns bridge compilation and version selection, not embedding apps.
After producing a validated bridge release set, prepare its consumer package:

```bash
make consumer-artifacts \
   BRIDGE_RELEASE_URL=https://github.com/intel/rohd-wave-viewer/releases/download/dart-wellen-0.1.2/dart_wellen-0.1.2-web.tar.gz
```

Use the selected package's version in the URL; it is not the bridge version.
The target validates generated Dart, Rust, native, and WASM versions/content
hashes before packaging the existing files. The checked-in
`packages/dart_wellen/tool/bridge_artifacts.json` is the source contract:
package/bridge versions, file inventory, and an explicit versioned release URL.
It does not contain compiled-binary checksums.
The contract explicitly identifies the WASM profile as `release`; Flutter
debug and release hosts both consume this prebuilt runtime. Debugger build
mode never changes the Rust profile or triggers a Cargo build.
Commit this small contract and the installer, **not** generated artifacts.
Review the contract whenever versions, inventory, or distribution URLs change.

Preparation writes actual archive/file SHA-256 checksums and the producer
checkout's commit to ignored `tool/bridge_artifacts.build.json` inside
`dart_wellen`. That generated metadata belongs to the built package, not the
source commit. Equal bridge API/content hashes do not guarantee byte-identical
WASM from different runners or toolchains. Repackaging the same input files is
deterministic; recompiling them is not assumed to be.

Release preparation performs this packaging step too. Its final clean-source
check requires the source contract to remain unchanged; generated checksums
are not compared with a local developer's build. Preparation preserves the
committed contract's versioned download URL only for the same package version.
The canonical contract points to
`intel/rohd-wave-viewer` and must name the same repository as the publication
workflow. A fork that publishes a bundle must commit a matching versioned fork
URL on its own branch and must not merge that fork-specific contract upstream.
General and Release Checks validate the contract against their repository
before building artifacts. Set `BRIDGE_RELEASE_URL` explicitly when changing
the package version; it also overrides the saved URL when selecting a different
release for that version.
The **General** workflow runs validation for every push, including `main`.
It prepares and uploads the complete `dart-wellen-consumer-artifacts` payload
for the checked commit. Development consumers can download that ephemeral
artifact by selecting CI source mode, which verifies that the artifact commit
matches their resolved Git dependency. General never creates a GitHub Release.
After General succeeds, manually dispatch
**Release Checks** for `dart_wellen` with `publish_bundle` enabled. The
publication job runs only after all selected checks succeed, matches build
metadata to the source contract and checked-out commit, and rechecks the
archive SHA-256 before contacting GitHub.

The publication job creates the missing
`dart-wellen-<package-version>` GitHub Release at the checked commit and
uploads the archive plus its JSON checksum sidecar. A package version with a
SemVer prerelease suffix creates a GitHub prerelease; every other package
version creates a regular release without changing the repository's latest
release. The publication job is the only job given `contents: write`. It
never moves an existing tag or replaces an asset with different bytes.
Neither General nor Release Checks publishes to pub.dev.

Consumer installation, after Pub selects the package, is:

```bash
python3 <resolved-dart_wellen-root>/tool/bridge_artifacts.py install
```

- Prepared local checkouts and hosted Pub archives already contain the files;
  installation verifies them against their included
  `tool/bridge_artifacts.build.json` without network access.
- Git dependencies contain the installer and manifest, not compiled objects.
  They must resolve to a released `dart_wellen` version. The installer uses
  that version's release URL from the manifest, retrieves its JSON sidecar over
  HTTPS, validates the package contract, then validates the archive and every
  extracted file against the producer's checksums. It caches the verified build
  metadata for offline reinstallation. It never invokes Cargo or code
  generation.
- Branch-CI consumers resolve the same package source from Git, then download
  General's `dart-wellen-consumer-artifacts` payload for the exact resolved
  commit. This mode is intended for development branches and requires an
  Actions artifact token when GitHub does not allow anonymous downloads.
- Missing manifests, stale versions, unavailable versioned releases, and
  checksum failures fail explicitly. There is no fallback to an older runtime
  or a source build.

Hosts stage `web/pkg` from that resolved package, including notices, into their
own ignored web output. They must refresh it when switching dependency sources
or versions, not maintain an independent bridge pin or vendored WASM copy.

### Git Dependency Release Test

Git dependencies are supported only after the selected package version has a
matching versioned bridge release:

1. In the producer checkout, prepare the existing validated bridge outputs
   with the archive URL from the checked-in contract. This command packages
   existing files; it does not compile Rust or a viewer application:

   ```bash
   python3 packages/dart_wellen/tool/bridge_artifacts.py prepare \
       --release-url https://github.com/intel/rohd-wave-viewer/releases/download/dart-wellen-0.1.2/dart_wellen-0.1.2-web.tar.gz
   ```

2. Review, sign, commit, and push the installer, manifest, packaging rules,
   tests, documentation, and hosted workspace lockfile. Keep the package's
   release contract canonical.
   Do not commit local-path lockfile entries, generated bindings, `web/pkg`,
   generated `bridge_artifacts.build.json`, or the bundle.
   This procedure does not perform commits or pushes automatically.
3. Require General to pass for that commit, then dispatch **Release Checks**
   with `package: dart_wellen` and `publish_bundle: true`. This creates the
   matching `dart-wellen-<package-version>` release. Publish the Dart package
   to pub.dev separately when a hosted release is required.
4. In the embedding app, select **both** `rohd_wave_viewer` at repository
   root and `dart_wellen` at `packages/dart_wellen` from the same repository
   URL and versioned release tag or commit. A package's own
   `dependency_overrides` do not propagate to its consumers, so overriding
   only the root viewer is insufficient while its hosted `dart_wellen`
   dependency is unpublished.
5. Run Pub, then the resolved `dart_wellen` installer. A clean Git checkout
   lacks generated bindings and WASM; the installer downloads the matching
   versioned bundle and validates its hashes before the host compiles. If Pub
   still locks the previous release, explicitly upgrade `rohd_wave_viewer` and
   `dart_wellen` together, then check `resolved-ref`.

Success requires Pub's package configuration to identify Git-cache locations
for both packages, a real versioned-bundle download on the first installation,
verified runtime checksums, and successful host startup. A subsequent install
should verify the cached files without downloading or compiling anything.

For pub.dev, publish `dart_wellen` **with** the generated files, `web/pkg`,
and `tool/bridge_artifacts.build.json`
included by its `.pubignore`, then publish `rohd_wave_viewer` against that
hosted version. The root viewer archive should not carry another copy of the
bridge. Hosts use the same package-relative artifact location and installation
step; verification succeeds offline because Pub already delivered the files.
`tool/stage_hosted_viewer.sh` provides the isolated embedding package used by
both release checks and manual publication; it excludes the nested package
and standalone runtime without hiding `dart_wellen` from its own publication.

## Required CI and Manual Publication

Before either manual publication:

1. Require the **General** workflow to pass for the exact release commit.
2. Run **Release Checks** for the selected package and require it to pass.
3. Review the dry-run archive and its narrowly documented exception, if any.
4. Publish using the authorized pub.dev publisher account.

Pub publication, commits, pushes, Pages deployments, Linux archives, and VSIX
publication remain explicit maintainer actions outside the helper. GitHub
bridge release publication is explicit: after General passes, enable
`publish_bundle` on Release Checks to create the versioned `dart_wellen`
release. Neither workflow publishes to pub.dev, and the publication job never
moves an existing tag.

---

Copyright (C) 2026 Intel Corporation
SPDX-License-Identifier: BSD-3-Clause
