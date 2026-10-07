# Contributing to ROHD Wave Viewer

Thank you for contributing to ROHD Wave Viewer. Bug reports, documentation,
tests, and implementation improvements are all welcome.

## Code of Conduct

ROHD Wave Viewer follows the
[Contributor Covenant](https://www.contributor-covenant.org/) v2.1. See
[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## Getting Help

- Join the ROHD community on
  [Discord](https://discord.com/invite/jubxF84yGw).
- Use [GitHub Discussions](https://github.com/intel/rohd-wave-viewer/discussions)
  for questions, ideas, and general discussion.
- Ask development questions on
  [Stack Overflow](https://stackoverflow.com/questions/tagged/rohd) with the
  `rohd` tag.
- Join a periodic [ROHD Forum](https://intel.github.io/rohd-website/forum/rohd-forum/)
  meeting.

## Development Setup

The repository pins the toolchain used by CI. Flutter alone is not sufficient
for every target: native bridge, WebAssembly, and VS Code extension work also
requires Rust, WASM tools, native Linux build tools, and Node.js.

Follow the [build guide](doc/BUILD.md) to set up the development environment,
resolve the Pub workspace, and use the supported build and run targets.

GitHub Codespaces uses the same repository setup:

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://github.com/codespaces/new?hide_repo_select=true&ref=main&repo=781703435)

## Reporting Issues

Report vulnerabilities through the process in [SECURITY.md](SECURITY.md).
Create other bug reports and feature requests with the repository's
[issue forms](https://github.com/intel/rohd-wave-viewer/issues/new/choose).

A useful bug report includes:

- the ROHD Wave Viewer version and how it was installed or run;
- output from `flutter --version`;
- the command that failed and its complete output;
- the relevant dependency configuration;
- minimal reproduction steps or code; and
- the expected and observed behavior.

## Pull Requests

Keep pull requests focused and include tests for behavior changes. Before
requesting review, run the CI-equivalent checks relevant to the change:

```bash
bash scripts/verify_flutter_version.sh
flutter analyze
make test
```

`make test` prepares the native Wellen bridge and tests both the root Flutter
package and workspace members; `flutter test` alone does not cover that full
set. Use the repository scripts for the remaining release checks:

```bash
tool/gh_actions/verify_formatting.sh
tool/gh_actions/generate_documentation.sh
make rust-test
```

Run platform builds that your change affects. In particular, use `make wasm`
for bridge changes, `make linux-release` for native application changes, and
`make extension` for extension or webview changes.

Every authored Dart source file should carry the full repository header:

```dart
// Copyright (C) <creation-year>[-<current-year>] Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// file_name.dart
// Brief description of the file.
//
// YYYY Month [day]
// Author: Name <email@example.com>
```

Generated Dart bindings receive their copyright and SPDX lines from the
Flutter Rust Bridge configuration and retain their generator-owned header.
Verify all Dart headers with:

```bash
dart run tool/gh_actions/verify_dart_headers.dart
```

## Style

ROHD Wave Viewer follows
[Effective Dart](https://dart.dev/effective-dart) and the lints configured by
the repository. Prefer the formatter and analyzer over manual formatting.
Public Dart APIs require API documentation, and user-visible behavior changes
should update the relevant Markdown and in-application help.

---

Copyright (C) 2024-2026 Intel Corporation
SPDX-License-Identifier: BSD-3-Clause
