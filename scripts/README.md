# Repository Scripts

These scripts support development, builds, packaging, and diagnostics. Normal
viewer users do not need them. Run commands from the repository root after
following the [build prerequisites](../doc/BUILD.md#prerequisites).

Prefer the public [Makefile targets](../Makefile) where listed: they arrange
prerequisites and staging before calling the implementation scripts.

In the **User invoked?** column:

- **Yes** means a developer-facing command.
- **Optional** means it can be called directly, but the listed Make target is
  normally preferred.
- **No** means an internal build helper, not a standalone workflow.
- **Legacy/diagnostic** means it is outside the normal build and validation
  path; see the cautions below.

## Script Inventory

| Script | User invoked? | What it does / preferred entry point |
| --- | --- | --- |
| [build_dart_wellen_bridge.sh](build_dart_wellen_bridge.sh) | No | Generates Dart and Rust Flutter Rust Bridge bindings using the package configuration and pinned generator. Does not compile the Rust library. Use `make dart`, `make rust-native`, or `make wasm`. |
| [build_vsix.sh](build_vsix.sh) | No | Packages an already staged extension directory with the repository's pinned `@vscode/vsce`. Takes `<staged-extension-dir> <output-vsix>`; does not build or stage the application. Use `make vsix`. |
| [clean_workspace.sh](clean_workspace.sh) | Optional | Runs `flutter clean` in the root package and every declared Pub workspace member. Supports `--dry-run`. Prefer `make clean`, which also cleans extension outputs. |
| [configure_vscode_association.sh](configure_vscode_association.sh) | Legacy/diagnostic | Edits the local Linux VS Code user settings to associate `*.vcd` with the hard-coded `rohdWaveViewer.vcd` editor ID. Changes user settings; prefer selecting **ROHD Wave Viewer** through VS Code's **Open With** UI. |
| [copy_devtools_extension_assets.cjs](copy_devtools_extension_assets.cjs) | No | Resolves `rohd_devtools_widgets` through the Pub package configuration and copies its extension assets to a supplied destination. Called by extension compilation and Makefile staging. |
| [fix_bootstrap.py](fix_bootstrap.py) | No | Patches the generated Flutter web bootstrap to use local CanvasKit and remove service-worker configuration. Called after web builds. |
| [generate_coverage.sh](generate_coverage.sh) | Optional | Runs root Flutter and `dart_wellen` tests, merges LCOV data, excludes generated bridge bindings, and creates an HTML report. Use `make coverage`; direct invocation with `--generate-svg` also writes a badge to `/tmp/coverage-badge.svg` for CI. |
| [install_extension_server.sh](install_extension_server.sh) | Optional | Installs a supplied slim ZIP or VSIX into the current user's VS Code Server extension directory and updates its extension manifest when available. Requires Node 24. Prefer `make install-remote`; direct invocation takes `<path-to-zip-or-vsix>`. |
| [package_slim_zip.sh](package_slim_zip.sh) | No | Archives the staged runtime extension directory into a versioned slim ZIP, not a Marketplace VSIX. Use `make extension` or `make package` to prepare the stage and archive it. |
| [patch_wasm_binary.sh](patch_wasm_binary.sh) | No | Patches generated Wellen WASM externref table sizing and exports in source/build web outputs, using wabt tools. Called by WASM and web builds. |
| [patch_wasm_js.sh](patch_wasm_js.sh) | No | Patches generated Wellen JavaScript with a fallback for `WebAssembly.Table.grow()` failures in VS Code webviews. Called by WASM and web builds. |
| [run_coverity.sh](run_coverity.sh) | Optional | Runs configured Coverity setup, capture, analysis, and reporting, plus Dart analysis and Rust Clippy. Requires the configured Coverity installation. Use `make coverity`, `make coverity-setup`, or `make coverity-clean`; invoke directly for individual stages. |
| [run_wasm_node_test.cjs](run_wasm_node_test.cjs) | Legacy/diagnostic | CommonJS Node harness that loads generated Wellen JS/WASM in a VM and attempts to load a waveform. Accepts `TEST_FILE`; otherwise uses `surfer/examples/vhdl3.vcd`. Called by the NVM diagnostic wrapper; not the supported browser test gate. |
| [run_wasm_test_nvm.sh](run_wasm_test_nvm.sh) | Legacy/diagnostic | Attempts to select/install Node 24 through NVM, copies built web bridge artifacts back into source web staging, and runs the CommonJS harness for supplied repository-relative waveform paths. Saves logs under `build_logs/wasm_test_runs`. |
| [setup_rust_env.sh](setup_rust_env.sh) | No | Sourced by build helpers to normalize Cargo/Rustup paths, select the pinned Rust toolchain, and ensure its WASM target and components are installed. Must be sourced to affect the caller's environment; it is not just a read-only environment check. |
| [verify_extension_vsix.sh](verify_extension_vsix.sh) | Optional | Checks an existing VSIX's metadata, identity/version, and required Flutter/WASM assets without rebuilding. Use `make verify-vsix`, or pass a specific archive path directly. |
| [verify_flutter_native_dependencies.sh](verify_flutter_native_dependencies.sh) | No | Inspects supplied Flutter engine artifacts for bundled libpng/zlib versions and enforces minimums or repository exceptions. Called by web and Linux builds. |
| [verify_flutter_version.sh](verify_flutter_version.sh) | Yes | Checks that Flutter and Dart on `PATH` meet the repository's development minimums. Run `bash scripts/verify_flutter_version.sh`; also used by launchers and CI. |
| [view_coverage.sh](view_coverage.sh) | Optional | Serves the HTML coverage report on loopback, generating it first if missing. Use `make coverage-view`; `COVERAGE_PORT` overrides port 8000. Stop the foreground server with Ctrl+C. |
| [wave_dev_mode.sh](wave_dev_mode.sh) | Yes | Shows or selects hosted, Git, or local dependency sources and manages generated local overrides. Start with `bash scripts/wave_dev_mode.sh show`; see the [developer guide](../doc/DEVELOPER.md) for configuration commands. |
| [wave_run.sh](wave_run.sh) | Yes | Verifies the toolchain, resolves dependencies, builds the required bridge, and launches the selected `web-debug`, `web-release`, `linux-debug`, or `linux-release` mode. Web modes serve on loopback port 9299. |

## Building a VSIX

Use:

```bash
make vsix
make verify-vsix
```

The build stages the current extension and calls
[build_vsix.sh](build_vsix.sh) to create a proper Marketplace VSIX with the
pinned packaging tool.

## WASM Diagnostics Versus Tests

The [CommonJS Node harness](run_wasm_node_test.cjs) depends on particular
generated JavaScript globals and an external example fixture unless overridden
with `TEST_FILE`. It is an ad hoc diagnostic, not a replacement for
`make browser-test`, which exercises the bridge and viewer in Chrome through
the supported Dart web compilers.

The NVM wrapper can install Node and overwrite files in source web staging.
It logs individual test failures and continues, so a successful wrapper exit
does not establish that all tests passed.

## Related Automation

- [Build guide](../doc/BUILD.md): setup, build, test, and installation workflows.
- [Developer guide](../doc/DEVELOPER.md): dependency selection and VS Code tasks.
- [WASM patch details](../doc/WASM_WEBVIEW_PATCH.md): generated-artifact fixes.
- [CI helpers](../tool/gh_actions/): toolchain installation and CI entry points.
- [Release guide](../doc/RELEASES.md): release tooling and artifact publication.

---

Copyright (C) 2026 Intel Corporation
SPDX-License-Identifier: BSD-3-Clause
