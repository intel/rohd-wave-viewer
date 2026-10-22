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
real_python="$(command -v python3)"
mkdir -p \
  "$source_repo/tool" \
  "$source_repo/packages/dart_wellen/tool" \
  "$source_repo/packages/dart_wellen" \
  "$source_repo/web/pkg" \
  "$fake_bin"

cp "$repo_root/tool/prepare_release.sh" "$source_repo/tool/prepare_release.sh"
cp "$repo_root/tool/stage_hosted_viewer.sh" "$source_repo/tool/stage_hosted_viewer.sh"
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
printf 'prepared runtime\n' >"$source_repo/web/pkg/wellen_bridge_bg.wasm"

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
if [[ "${HOSTED_GET_MODE:-}" == fail ]] &&
  [[ "$PWD" == */rohd_wave_viewer_hosted ]] &&
  [[ "$*" == 'pub get' ]]; then
  echo 'hosted dependency unavailable' >&2
  exit 1
fi
if [[ "$*" == 'pub publish --dry-run' ]]; then
  if [[ "$PWD" == */rohd_wave_viewer_hosted ]]; then
    [[ ! -d packages && ! -d web/pkg ]]
    ! grep -q '^workspace:' pubspec.yaml
  fi
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
    bridge)
      echo '├── wellen_bridge_bg.wasm'
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
cat >"$fake_bin/python3" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == -c ]]; then
  exec "$REAL_PYTHON" "$@"
fi
[[ "$1" == */packages/dart_wellen/tool/bridge_artifacts.py && "$2" == prepare ]]
printf 'consumer-artifacts|%s\n' "$*" >>"$SDK_LOG"
SH
chmod +x "$fake_bin/python3"

git -C "$source_repo" init -q -b main
git -C "$source_repo" config user.email release-test@example.com
git -C "$source_repo" config user.name 'Release Test'
git -C "$source_repo" add .
git -C "$source_repo" commit -qm 'Initial release source'
git clone -q --bare "$source_repo" "$canonical_repo"

export PATH="$fake_bin:$PATH"
export SDK_LOG="$sdk_log"
export REAL_PYTHON="$real_python"
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
bash "$source_repo/tool/stage_hosted_viewer.sh" "$fixture/staged" >/dev/null
[[ ! -d "$fixture/staged/packages" && ! -d "$fixture/staged/web/pkg" ]]
! grep -q '^workspace:' "$fixture/staged/pubspec.yaml"
if bash "$source_repo/tool/stage_hosted_viewer.sh" "$fixture/staged" \
  >"$fixture/restage.txt" 2>&1; then
  echo 'Staging unexpectedly reused an existing directory.' >&2
  exit 1
fi
grep -Fq 'destination already exists' "$fixture/restage.txt"

: >"$sdk_log"
validation_output="$(run_helper --validate-only dart_wellen)"
grep -Fq 'dart_wellen=0.4.5' <<<"$validation_output"
grep -Fq 'Validation-only preparation completed' <<<"$validation_output"
[[ ! -s "$sdk_log" ]]

: >"$sdk_log"
DRY_RUN_MODE=known run_helper >"$fixture/default.txt"
grep -Fq 'dart_wellen=0.4.5' "$fixture/default.txt"
grep -Fq 'KNOWN EXCEPTION: dart_wellen' "$fixture/default.txt"
! grep -Fq 'rohd_wave_viewer=1.2.3' "$fixture/default.txt"
grep -Fq 'make|' "$sdk_log"
grep -Fq ' dart' "$sdk_log" || grep -Fq '|dart' "$sdk_log"
grep -Fq 'pub publish --dry-run' "$sdk_log"
grep -Fq 'bridge-verify' "$sdk_log"
grep -Fq \
  'https://github.com/intel/rohd-wave-viewer/releases/download/dart-wellen-0.4.5/dart_wellen-0.4.5-web.tar.gz' \
  "$sdk_log"
! grep -Fq ' test' "$sdk_log"
! grep -Fq ' pana' "$sdk_log"

cat >"$source_repo/packages/dart_wellen/tool/bridge_artifacts.json" <<'JSON'
{"version": "0.4.5", "archive_url": "https://example.invalid/fork/releases/development.tar.gz"}
JSON
git -C "$source_repo" add packages/dart_wellen/tool/bridge_artifacts.json
git -C "$source_repo" commit -qm 'Pin development consumer artifacts'

: >"$sdk_log"
run_helper dart_wellen >"$fixture/pinned.txt"
grep -Fq 'https://example.invalid/fork/releases/development.tar.gz' "$sdk_log"

: >"$sdk_log"
BRIDGE_RELEASE_URL=https://example.invalid/override.tar.gz \
  run_helper dart_wellen >"$fixture/override.txt"
grep -Fq 'https://example.invalid/override.tar.gz' "$sdk_log"

: >"$sdk_log"
DRY_RUN_MODE=known run_helper dart_wellen rohd_wave_viewer \
  >"$fixture/both.txt"
grep -Fq 'dart_wellen=0.4.5' "$fixture/both.txt"
grep -Fq 'rohd_wave_viewer=1.2.3' "$fixture/both.txt"
grep -Fq 'KNOWN EXCEPTION: dart_wellen' "$fixture/both.txt"
grep -Fq 'KNOWN EXCEPTION: rohd_wave_viewer' "$fixture/both.txt"
grep -Fq 'rohd_wave_viewer_hosted|pub publish --dry-run' "$sdk_log"

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

DRY_RUN_MODE=bridge assert_fails rohd_wave_viewer
grep -Fq 'archive duplicates independently published bridge artifacts' \
  "$fixture/failure.txt"

: >"$sdk_log"
HOSTED_GET_MODE=fail assert_fails rohd_wave_viewer
grep -Fq 'FAILED: rohd_wave_viewer hosted dependency resolution' \
  "$fixture/failure.txt"
! grep -F 'rohd_wave_viewer_hosted|analyze --fatal-infos --no-pub' "$sdk_log"

cat >"$source_repo/packages/dart_wellen/tool/bridge_artifacts.json" <<'JSON'
{"version": "0.4.4", "archive_url": "https://example.invalid/fork/releases/previous.tar.gz"}
JSON
git -C "$source_repo" add packages/dart_wellen/tool/bridge_artifacts.json
git -C "$source_repo" commit -qm 'Keep stale artifact metadata for regression test'

: >"$sdk_log"
if run_helper dart_wellen >"$fixture/stale.txt" 2>&1; then
  echo 'Release preparation reused a stale manifest URL.' >&2
  exit 1
fi
grep -Fq 'Set BRIDGE_RELEASE_URL for the new package version' "$fixture/stale.txt"
! grep -Fq 'consumer-artifacts|' "$sdk_log"

: >"$sdk_log"
BRIDGE_RELEASE_URL=https://example.invalid/new-version.tar.gz \
  run_helper dart_wellen >"$fixture/new-version.txt"
grep -Fq 'https://example.invalid/new-version.tar.gz' "$sdk_log"

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
