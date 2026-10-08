#!/usr/bin/env bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# prepare_release.sh
# Validates and dry-runs selected Wave Viewer packages without publishing.
#
# 2026 October 07
# Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

set -euo pipefail

export DART_SUPPRESS_ANALYTICS=true
export FLUTTER_SUPPRESS_ANALYTICS=true

usage() {
  cat <<'USAGE'
Usage: tool/prepare_release.sh [options] [package ...]

Packages:
  dart_wellen
  rohd_wave_viewer

No package names selects `dart_wellen`, the first package in publication order.
Select `rohd_wave_viewer` explicitly after its hosted `dart_wellen` dependency
is available. Each package keeps the version declared in its own manifest.

Options:
  --validate-only  Validate selection, metadata, and source provenance only.
  --run-tests      Run the complete local Dart, Flutter, Rust, and browser tests.
  --run-pana       Run the repository's isolated hosted-dependency/Pana gate.
  -h, --help       Show this help.

The helper may fetch canonical main and create ignored build outputs and
temporary directories. It never uploads, publishes, commits, tags, pushes,
merges, rebases, or rewrites package versions.
USAGE
}

fail() {
  echo "Release preparation: $*" >&2
  exit 1
}

run_stage() {
  local label="$1"
  shift
  local status
  printf '\n=== %s ===\n' "$label"
  set +e
  (
    set -euo pipefail
    "$@"
  )
  status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    echo "PASSED: $label"
  else
    echo "FAILED: $label (exit $status)" >&2
    exit "$status"
  fi
}

manifest_value() {
  local manifest="$1"
  local key="$2"
  sed -n \
    "s/^${key}:[[:space:]]*[\"']\\{0,1\\}\\([^\"']*\\)[\"']\\{0,1\\}[[:space:]]*$/\\1/p" \
    "$manifest" |
    head -n 1
}

package_directory() {
  case "$1" in
    dart_wellen) printf '%s/packages/dart_wellen' "$repo_root" ;;
    rohd_wave_viewer) printf '%s' "$repo_root" ;;
    *) return 2 ;;
  esac
}

package_sdk() {
  case "$1" in
    dart_wellen) printf 'dart' ;;
    rohd_wave_viewer) printf 'flutter' ;;
    *) return 2 ;;
  esac
}

validate_package_metadata() {
  local package="$1"
  local directory
  directory="$(package_directory "$package")"
  local manifest="$directory/pubspec.yaml"
  local version
  local name
  local description
  local homepage
  local repository
  local issue_tracker

  [[ -f "$manifest" ]] || fail "$package is missing pubspec.yaml"
  [[ -f "$directory/README.md" ]] || fail "$package is missing README.md"
  [[ -f "$directory/CHANGELOG.md" ]] || fail "$package is missing CHANGELOG.md"
  [[ -f "$directory/LICENSE" ]] || fail "$package is missing LICENSE"

  name="$(manifest_value "$manifest" name)"
  version="$(manifest_value "$manifest" version)"
  description="$(manifest_value "$manifest" description)"
  homepage="$(manifest_value "$manifest" homepage)"
  repository="$(manifest_value "$manifest" repository)"
  issue_tracker="$(manifest_value "$manifest" issue_tracker)"

  [[ "$name" == "$package" ]] ||
    fail "$manifest declares name '$name'; expected '$package'"
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]] ||
    fail "$manifest needs a semantic version; found '$version'"
  [[ -n "$description" ]] || fail "$manifest needs a description"
  [[ "$homepage" =~ ^https:// ]] || fail "$manifest needs an HTTPS homepage"
  [[ "$repository" == 'https://github.com/intel/rohd-wave-viewer' ]] ||
    fail "$manifest has unexpected repository '$repository'"
  [[ "$issue_tracker" == 'https://github.com/intel/rohd-wave-viewer/issues' ]] ||
    fail "$manifest has unexpected issue tracker '$issue_tracker'"
  ! grep -Eq '^publish_to:[[:space:]]*["'\'']?none["'\'']?[[:space:]]*$' \
    "$manifest" ||
    fail "$manifest disables publication"
  grep -Eq '^[[:space:]]+sdk:[[:space:]]*' "$manifest" ||
    fail "$manifest has no Dart SDK constraint"
  grep -Eq "^##[[:space:]]+$version([[:space:]]*)$" "$directory/CHANGELOG.md" ||
    fail "$directory/CHANGELOG.md has no release heading for $version"

  echo "$package: version $version metadata validated"
}

validate_source_provenance() {
  local dirty
  dirty="$(git -C "$repo_root" status --porcelain --untracked-files=all)"
  if [[ -n "$dirty" ]]; then
    echo "$dirty" >&2
    fail 'the release source must be a clean Git worktree'
  fi

  source_commit="$(git -C "$repo_root" rev-parse HEAD)"
  echo "Fetching canonical main from $release_repository..."
  git -C "$repo_root" fetch --quiet --no-tags \
    "$release_repository" refs/heads/main
  main_commit="$(git -C "$repo_root" rev-parse FETCH_HEAD)"
  git -C "$repo_root" merge-base --is-ancestor \
    "$main_commit" "$source_commit" ||
    fail "release source $source_commit does not contain canonical main $main_commit"

  echo "Release source: $source_commit"
  echo "Canonical main: $main_commit"
}

resolve_and_analyze_package() {
  local package="$1"
  local directory
  local sdk
  directory="$(package_directory "$package")"
  sdk="$(package_sdk "$package")"

  (
    cd "$directory"
    "$sdk" pub get
    dart format --output=none --set-exit-if-changed .
    if [[ "$package" == rohd_wave_viewer ]]; then
      flutter analyze --fatal-infos --no-pub
    else
      dart analyze --fatal-infos
    fi
  )
}

verify_root_hosted_resolution() {
  local hosted_root="$temp_dir/rohd_wave_viewer_hosted"
  mkdir -p "$hosted_root"
  tar -C "$repo_root" \
    --exclude=.git \
    --exclude=.dart_tool \
    --exclude=.flutter-plugins \
    --exclude=.flutter-plugins-dependencies \
    --exclude=build \
    --exclude=coverage \
    --exclude=node_modules \
    --exclude=packages \
    --exclude=pubspec.lock \
    --exclude=pubspec_overrides.yaml \
    --exclude='pubspec_overrides.yaml.disabled*' \
    --exclude=rust/wellen_bridge/target \
    --exclude=vscode-extension/node_modules \
    -cf - . |
    tar -C "$hosted_root" -xf -

  awk '
    /^workspace:[[:space:]]*$/ { skipping = 1; next }
    skipping && /^[^[:space:]#]/ { skipping = 0 }
    !skipping { print }
  ' "$hosted_root/pubspec.yaml" >"$hosted_root/pubspec.yaml.hosted"
  mv "$hosted_root/pubspec.yaml.hosted" "$hosted_root/pubspec.yaml"

  (
    cd "$hosted_root"
    flutter pub get
    flutter analyze --fatal-infos --no-pub
  )
}

run_complete_tests() {
  make -C "$repo_root" test
  make -C "$repo_root" rust-test
  make -C "$repo_root" browser-test
}

run_pana() {
  PATH="$PATH:${PUB_CACHE:-$HOME/.pub-cache}/bin" \
    make -C "$repo_root" pana
}

run_pub_dry_run() {
  local package="$1"
  local directory
  local sdk
  local output="$temp_dir/${package}_publish.txt"
  local status
  local issue_count
  directory="$(package_directory "$package")"
  sdk="$(package_sdk "$package")"

  set +e
  (
    cd "$directory"
    "$sdk" pub publish --dry-run </dev/null
  ) 2>&1 | tee "$output"
  status="${PIPESTATUS[0]}"
  set -e

  if [[ "$package" == rohd_wave_viewer ]] &&
    grep -Eq 'vscode-extension|Waveform\.mp4|waveform-demo\.mp4' "$output"; then
    echo 'rohd_wave_viewer archive contains independent extension or demo-video payload.' >&2
    return 1
  fi

  if [[ "$status" -eq 0 ]]; then
    return
  fi

  issue_count="$(grep -c '^\* ' "$output" || true)"
  if [[ "$status" -eq 65 ]] &&
    [[ "$issue_count" -eq 1 ]] &&
    grep -Fq \
      'Your dependency on "flutter_rust_bridge" should allow more than one version.' \
      "$output" &&
    grep -Fq 'Package has 1 warning.' "$output"; then
    echo "KNOWN EXCEPTION: $package pins flutter_rust_bridge to its generated bridge version."
    return
  fi

  echo "$package publication dry run failed with $issue_count issue(s)." >&2
  return "$status"
}

validate_only=false
run_tests=false
run_pana_gate=false
packages=()
for argument in "$@"; do
  case "$argument" in
    --validate-only) validate_only=true ;;
    --run-tests) run_tests=true ;;
    --run-pana) run_pana_gate=true ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      echo "Unsupported option: $argument" >&2
      usage >&2
      exit 2
      ;;
    *) packages+=("$argument") ;;
  esac
done

if [[ "${#packages[@]}" -eq 0 ]]; then
  packages=(dart_wellen)
fi

selected_packages=()
for package in "${packages[@]}"; do
  case "$package" in
    dart_wellen|rohd_wave_viewer) ;;
    *)
      echo "Unsupported package: $package" >&2
      usage >&2
      exit 2
      ;;
  esac
  if [[ " ${selected_packages[*]} " != *" $package "* ]]; then
    selected_packages+=("$package")
  fi
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
release_repository="${ROHD_WAVE_RELEASE_REPOSITORY:-https://github.com/intel/rohd-wave-viewer.git}"
source_commit=''
main_commit=''
package_versions=()
temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/rohd-wave-release.XXXXXXXX")"
trap 'rm -rf "$temp_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

command -v git >/dev/null || fail 'git is required'
command -v dart >/dev/null || fail 'dart is required'
for package in "${selected_packages[@]}"; do
  command -v "$(package_sdk "$package")" >/dev/null ||
    fail "$(package_sdk "$package") is required for $package"
done

run_stage 'Source provenance' validate_source_provenance
source_commit="$(git -C "$repo_root" rev-parse HEAD)"
main_commit="$(git -C "$repo_root" rev-parse FETCH_HEAD)"
for package in "${selected_packages[@]}"; do
  run_stage "$package metadata" validate_package_metadata "$package"
  package_versions+=(
    "$package=$(manifest_value "$(package_directory "$package")/pubspec.yaml" version)"
  )
done

printf '\nSelected package inventory:\n'
printf '  %s\n' "${package_versions[@]}"

if [[ "$validate_only" == true ]]; then
  echo 'Validation-only preparation completed; no builds or dry runs were run.'
  exit 0
fi

run_stage 'Generate Flutter Rust Bridge bindings' make -C "$repo_root" dart
run_stage 'Build native Wellen bridge' make -C "$repo_root" rust-native
run_stage 'Build WebAssembly Wellen bridge' make -C "$repo_root" wasm
run_stage 'Validate matching bridge release set' \
  "$script_dir/verify_bridge_release.sh"

for package in "${selected_packages[@]}"; do
  run_stage "$package dependency resolution, formatting, and analysis" \
    resolve_and_analyze_package "$package"
done

if [[ " ${selected_packages[*]} " == *' rohd_wave_viewer '* ]]; then
  run_stage 'rohd_wave_viewer hosted dependency resolution' \
    verify_root_hosted_resolution
fi

if [[ "$run_tests" == true ]]; then
  run_stage 'Complete local test suites' run_complete_tests
else
  echo 'Complete local tests skipped; use --run-tests to include them.'
fi

if [[ "$run_pana_gate" == true ]]; then
  PATH="$PATH:${PUB_CACHE:-$HOME/.pub-cache}/bin" \
    command -v pana >/dev/null 2>&1 ||
    fail 'Pana is required; run tool/gh_actions/install_pana.sh first'
  run_stage 'Hosted dependency and Pana gate' run_pana
else
  echo 'Pana skipped; use --run-pana to include it.'
fi

for package in "${selected_packages[@]}"; do
  run_stage "$package publication dry run" run_pub_dry_run "$package"
done

run_stage 'Release source remained unchanged' \
  git -C "$repo_root" diff --exit-code
[[ -z "$(git -C "$repo_root" status --porcelain --untracked-files=all)" ]] ||
  fail 'release preparation left untracked or modified source files'

printf '\nRelease preparation PASSED for source %s:\n' "$source_commit"
printf '  %s\n' "${package_versions[@]}"
echo 'No packages were uploaded and no Git history or refs were changed.'
