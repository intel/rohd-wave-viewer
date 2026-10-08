#!/usr/bin/env bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# prepare_release_test.sh
# Tests release preparation using local Git fixtures and fake build tools.
#
# 2026 October 07
# Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/rohd-wave-release-test.XXXXXXXX")"
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

source_repo="$fixture/source"
canonical_repo="$fixture/canonical.git"
fake_bin="$fixture/bin"
sdk_log="$fixture/sdk.log"
mkdir -p \
  "$source_repo/tool" \
  "$source_repo/packages/dart_wellen" \
  "$fake_bin"

cp "$repo_root/tool/prepare_release.sh" "$source_repo/tool/prepare_release.sh"
cat >"$source_repo/tool/verify_bridge_release.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'bridge-verify\n' >>"$SDK_LOG"
SH
chmod +x \
  "$source_repo/tool/prepare_release.sh" \
  "$source_repo/tool/verify_bridge_release.sh"

cat >"$source_repo/pubspec.yaml" <<'YAML'
name: rohd_wave_viewer
description: "Embeddable waveform viewer."
homepage: https://intel.github.io/rohd-website/
repository: https://github.com/intel/rohd-wave-viewer
version: 1.2.3
issue_tracker: https://github.com/intel/rohd-wave-viewer/issues
environment:
  sdk: '>=3.6.0 <4.0.0'
  flutter: '>=3.44.0'
workspace:
  - packages/dart_wellen
dependencies:
  dart_wellen: ^0.4.5
  flutter:
    sdk: flutter
YAML
cat >"$source_repo/packages/dart_wellen/pubspec.yaml" <<'YAML'
name: dart_wellen
description: "Wellen bindings."
homepage: https://intel.github.io/rohd-website/
repository: https://github.com/intel/rohd-wave-viewer
version: 0.4.5
issue_tracker: https://github.com/intel/rohd-wave-viewer/issues
resolution: workspace
environment:
  sdk: '>=3.6.0 <4.0.0'
YAML
for directory in "$source_repo" "$source_repo/packages/dart_wellen"; do
  printf '# Package\n' >"$directory/README.md"
  printf 'license\n' >"$directory/LICENSE"
done
printf '# Changelog\n\n## 1.2.3\n' >"$source_repo/CHANGELOG.md"
printf '# Changelog\n\n## 0.4.5\n' \
  >"$source_repo/packages/dart_wellen/CHANGELOG.md"

cat >"$fake_bin/dart" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'dart|%s|%s\n' "$PWD" "$*" >>"$SDK_LOG"
if [[ "$*" == 'pub publish --dry-run' ]]; then
  case "${DRY_RUN_MODE:-success}" in
    known)
      cat <<'OUTPUT'
Package validation found the following 1 potential issue:
* Your dependency on "flutter_rust_bridge" should allow more than one version.
Package has 1 warning.
OUTPUT
      exit 65
      ;;
    other)
      cat <<'OUTPUT'
Package validation found the following 1 potential issue:
* README.md is missing required release information.
Package has 1 warning.
OUTPUT
      exit 65
      ;;
    payload)
      echo '├── vscode-extension'
      ;;
  esac
fi
SH
cat >"$fake_bin/flutter" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'flutter|%s|%s\n' "$PWD" "$*" >>"$SDK_LOG"
if [[ "$*" == 'pub publish --dry-run' ]]; then
  case "${DRY_RUN_MODE:-success}" in
    known)
      cat <<'OUTPUT'
Package validation found the following 1 potential issue:
* Your dependency on "flutter_rust_bridge" should allow more than one version.
Package has 1 warning.
OUTPUT
      exit 65
      ;;
    other)
      cat <<'OUTPUT'
Package validation found the following 1 potential issue:
* README.md is missing required release information.
Package has 1 warning.
OUTPUT
      exit 65
      ;;
    payload)
      echo '├── vscode-extension'
      ;;
  esac
fi
SH
cat >"$fake_bin/make" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'make|%s|%s\n' "$PWD" "$*" >>"$SDK_LOG"
SH
cat >"$fake_bin/pana" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$fake_bin"/*

git -C "$source_repo" init -q -b main
git -C "$source_repo" config user.email release-test@example.com
git -C "$source_repo" config user.name 'Release Test'
git -C "$source_repo" add .
git -C "$source_repo" commit -qm 'Initial release source'
git clone -q --bare "$source_repo" "$canonical_repo"

export PATH="$fake_bin:$PATH"
export SDK_LOG="$sdk_log"
export ROHD_WAVE_RELEASE_REPOSITORY="$canonical_repo"

run_helper() {
  (
    cd "$source_repo"
    tool/prepare_release.sh "$@"
  )
}

assert_fails() {
  local output="$fixture/failure.txt"
  set +e
  run_helper "$@" >"$output" 2>&1
  local status=$?
  set -e
  [[ "$status" -ne 0 ]]
}

run_helper --help >/dev/null

: >"$sdk_log"
validation_output="$(run_helper --validate-only dart_wellen)"
grep -Fq 'dart_wellen=0.4.5' <<<"$validation_output"
grep -Fq 'Validation-only preparation completed' <<<"$validation_output"
[[ ! -s "$sdk_log" ]]

: >"$sdk_log"
DRY_RUN_MODE=known run_helper >"$fixture/default.txt"
grep -Fq 'dart_wellen=0.4.5' "$fixture/default.txt"
grep -Fq 'rohd_wave_viewer=1.2.3' "$fixture/default.txt"
grep -Fq 'KNOWN EXCEPTION: dart_wellen' "$fixture/default.txt"
grep -Fq 'KNOWN EXCEPTION: rohd_wave_viewer' "$fixture/default.txt"
grep -Fq 'make|' "$sdk_log"
grep -Fq ' dart' "$sdk_log" || grep -Fq '|dart' "$sdk_log"
grep -Fq 'pub publish --dry-run' "$sdk_log"
grep -Fq 'bridge-verify' "$sdk_log"
! grep -Fq ' test' "$sdk_log"
! grep -Fq ' pana' "$sdk_log"

: >"$sdk_log"
run_helper --run-tests --run-pana dart_wellen >"$fixture/options.txt"
grep -Fq ' test' "$sdk_log"
grep -Fq ' rust-test' "$sdk_log"
grep -Fq ' browser-test' "$sdk_log"
grep -Fq ' pana' "$sdk_log"

assert_fails unsupported_package
grep -Fq 'Unsupported package: unsupported_package' "$fixture/failure.txt"

DRY_RUN_MODE=other assert_fails dart_wellen
grep -Fq 'FAILED: dart_wellen publication dry run' "$fixture/failure.txt"

DRY_RUN_MODE=payload assert_fails rohd_wave_viewer
grep -Fq 'archive contains independent extension or demo-video payload' \
  "$fixture/failure.txt"

touch "$source_repo/untracked.txt"
assert_fails --validate-only dart_wellen
grep -Fq 'clean Git worktree' "$fixture/failure.txt"
rm "$source_repo/untracked.txt"

canonical_work="$fixture/canonical-work"
git clone -q "$canonical_repo" "$canonical_work"
git -C "$canonical_work" config user.email release-test@example.com
git -C "$canonical_work" config user.name 'Release Test'
printf 'new main\n' >"$canonical_work/main.txt"
git -C "$canonical_work" add main.txt
git -C "$canonical_work" commit -qm 'Advance canonical main'
git -C "$canonical_work" push -q origin main

assert_fails --validate-only dart_wellen
grep -Fq 'does not contain canonical main' "$fixture/failure.txt"

echo 'Release preparation helper checks passed.'
