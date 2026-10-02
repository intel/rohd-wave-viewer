#!/usr/bin/env bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# Runs Pana for every publishable package that can resolve from pub.dev.

set -euo pipefail

export PATH="$PATH:${PUB_CACHE:-$HOME/.pub-cache}/bin"

if ! command -v pana >/dev/null 2>&1; then
  echo "Pana is required; run tool/gh_actions/install_pana.sh first." >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

flutter_root="${FLUTTER_ROOT:-}"
if [[ -z "$flutter_root" ]]; then
  flutter_executable="$(command -v flutter)"
  flutter_root="$(dirname "$(dirname "$(readlink -f "$flutter_executable")")")"
fi

temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/rohd-wave-pana.XXXXXXXX")"
trap 'rm -rf "$temp_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir "$temp_dir/package"

# Analyze an isolated workspace so generated state, dependency overrides, and
# the tracked lockfile cannot hide lower-bound dependency incompatibilities.
tar -C . \
  --exclude=.git --exclude=.dart_tool --exclude=.packages \
  --exclude=build --exclude=coverage --exclude=node_modules \
  --exclude=rust/wellen_bridge/target --exclude=web/pkg \
  --exclude=vscode-extension/node_modules --exclude=vscode-extension/out \
  --exclude=pubspec.lock --exclude=pubspec_overrides.yaml \
  --exclude='pubspec_overrides.yaml.disabled*' \
  --exclude=.flutter-plugins --exclude=.flutter-plugins-dependencies \
  --exclude=.wave_dependency_sources \
  -cf - . | tar -C "$temp_dir/package" -xf -

cd "$temp_dir/package"
if grep -Eq '^[[:space:]]*dependency_overrides[[:space:]]*:' pubspec.yaml; then
  echo "Move inline dependency overrides to pubspec_overrides.yaml before hosted checks." >&2
  exit 2
fi

echo "=== Hosted dependency compatibility ==="
flutter pub get
make dart
flutter analyze --fatal-infos --no-pub
flutter pub downgrade
flutter analyze --fatal-infos --no-pub

run_pana() {
  local package="$1"
  echo "=== Pana: $package ==="
  pana --exit-code-threshold "${PANA_SCORE_THRESHOLD:-30}" \
    --flutter-sdk "$flutter_root" "$package"
}

run_pana packages/dart_wellen

dart_wellen_version=''
while IFS=':' read -r key value; do
  if [[ "$key" == 'version' ]]; then
    dart_wellen_version="${value//[[:space:]]/}"
    break
  fi
done < packages/dart_wellen/pubspec.yaml

if [[ -z "$dart_wellen_version" ]]; then
  echo 'Could not read dart_wellen version from its pubspec.yaml.' >&2
  exit 2
fi

if dart pub cache add dart_wellen --version "$dart_wellen_version"; then
  run_pana .
else
  echo '=== Pana: . (skipped; dart_wellen is not available on pub.dev) ==='
fi
