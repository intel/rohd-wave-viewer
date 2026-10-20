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
same preparation in CI with independent test and Pana inputs. Pushes to the
development branch `shared-packages-020` also run preparation for `dart_wellen`
with publication disabled, allowing branch CI testing before a production
release or default-branch workflow update. Its optional manual-dispatch
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
  BRIDGE_RELEASE_URL=https://github.com/intel/rohd-wave-viewer/releases/download/dart-wellen-0.1.1/dart_wellen-0.1.1-web.tar.gz
```

Use the selected package's version in the URL; it is not the bridge version.
The target validates generated Dart, Rust, native, and WASM versions/content
hashes before preparing the reproducible bundle. It writes
`packages/dart_wellen/tool/bridge_artifacts.json` with the exact package/bridge
versions, file checksums, immutable HTTPS download URL, and archive checksum.
The manifest explicitly identifies the WASM profile as `release`; Flutter
debug and release hosts both consume this prebuilt runtime. Debugger build
mode never changes the Rust profile or triggers a Cargo build.
Commit this small manifest and the installer, **not** the generated artifacts.
Regenerate and review the manifest whenever bridge inputs or version change.

Release preparation performs this packaging step too. Its final clean-source
check requires the prepared manifest to already match the release commit.
Preparation preserves the committed manifest's download URL (including fork
and development-release URLs) only for the same package version.
Set `BRIDGE_RELEASE_URL` explicitly when changing the package version; it also
overrides the saved URL when selecting a different release for that version.
Release Checks retains the bundle and manifest as CI artifacts. Enable its
`publish_bundle` input to have CI publish the exact verified bundle at the
manifest's URL; no manual file upload is needed. The publication job runs only
after all selected checks succeed, compares the prepared manifest to the
checked-out commit, and rechecks the archive SHA-256 before contacting GitHub.
The URL must belong to the repository running the workflow, including forks.

Only that publication job receives `contents: write`. It creates a missing
release at the checked commit and never moves an existing tag. Development or
custom tags create prereleases; a stable `dart-wellen-<package-version>` tag
creates a regular release without changing the repository's latest release.
An existing identical asset is verified and reused. Different bytes cause an
explicit failure: choose a new URL and commit the regenerated manifest rather
than replacing an immutable asset. Existing draft releases also fail because
anonymous consumers cannot install from them.

Consumer installation, after Pub selects the package, is:

```bash
python3 <resolved-dart_wellen-root>/tool/bridge_artifacts.py install
```

- Prepared local checkouts and hosted Pub archives already contain the files;
  installation verifies them without network access.
- Git dependencies contain the installer and manifest, not compiled objects.
  Installation downloads the pinned bundle and validates both archive and file
  checksums before installing generated bindings and runtime into the resolved
  package directory. It never invokes Cargo or code generation.
- Missing manifests, stale versions, unavailable releases, and checksum failures
  fail explicitly. There is no fallback to an older runtime or a source build.

Hosts stage `web/pkg` from that resolved package, including notices, into their
own ignored web output. They must refresh it when switching dependency sources
or versions, not maintain an independent bridge pin or vendored WASM copy.

### First GitHub Branch Test

For development, the artifact can be a prerelease on a fork. Neither consumer
needs a local viewer checkout or a Pub release:

1. In this repository, prepare the existing validated bridge outputs with a
   prerelease URL belonging to the fork. This command packages existing files;
   it does not compile Rust or a viewer application:

   ```bash
   python3 packages/dart_wellen/tool/bridge_artifacts.py prepare \
     --release-url https://github.com/desmonddak/rohd-wave-viewer/releases/download/dart-wellen-0.1.1-dev/dart_wellen-0.1.1-web.tar.gz
   ```

2. Review, sign, commit, and push the installer, manifest, packaging rules,
   tests, and documentation to `shared-packages-020`. Do not commit
   `pubspec.lock` changes, generated bindings, `web/pkg`, or the bundle.
   This procedure does not perform commits or pushes automatically.
3. In `desmonddak/rohd-wave-viewer`, dispatch **Release Checks** on the pushed
   branch, select `dart_wellen`, and enable **Publish the verified bridge bundle
   at its pinned GitHub release URL** (`publish_bundle`). After preparation
   succeeds, CI creates the `dart-wellen-0.1.1-dev` prerelease and uploads the
   matching archive. A branch push alone does not start publication.
   The built manifest must match the signed commit; if a clean CI build
   produces different bytes, publication fails rather than changing the pin.
   The workflow must exist on the repository's default branch for GitHub to
   expose its manual dispatch UI; once available, select the development
   branch to run its version of the workflow. The non-publishing branch-push
   checks do not have that restriction and run before manual dispatch is
   available.
4. In the embedding app, select **both** `rohd_wave_viewer` at repository
   root and `dart_wellen` at `packages/dart_wellen` from the same repository
   URL and Git ref. A package's own `dependency_overrides` do not propagate
   to its consumers, so overriding only the root viewer is insufficient
   while its hosted `dart_wellen` dependency is unpublished.
5. Run Pub, then the resolved `dart_wellen` installer. A clean Git checkout
   lacks generated bindings and WASM; the installer must download the bundle
   and validate the archive/file hashes before the host compiles.

Success requires Pub's package configuration to identify Git-cache locations
for both packages, a real release download on the first installation, verified
runtime checksums, and successful host startup. A subsequent install should
verify the cached files without downloading or compiling anything.

For pub.dev, publish `dart_wellen` **with** the generated files and `web/pkg`
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
bridge release creation and asset upload are CI-managed only when a maintainer
explicitly enables `publish_bundle` on Release Checks; ordinary checks do not
publish or move tags.

---

Copyright (C) 2026 Intel Corporation
SPDX-License-Identifier: BSD-3-Clause
