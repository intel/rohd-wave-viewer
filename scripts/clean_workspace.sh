#!/usr/bin/env bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# Cleans the root Flutter package and every Pub workspace member declared in
# the root pubspec.yaml.

set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
flutter_bin="${FLUTTER:-flutter}"
dry_run=false

if [[ "${1:-}" == "--dry-run" ]]; then
  dry_run=true
  shift
fi

if (($# != 0)); then
  printf 'usage: %s [--dry-run]\n' "$0" >&2
  exit 64
fi

workspace_members=()
while IFS= read -r member; do
  workspace_members+=("$member")
done < <(
  awk '
    /^workspace:[[:space:]]*$/ {
      in_workspace = 1
      next
    }
    in_workspace && /^[^[:space:]]/ {
      exit
    }
    in_workspace && /^[[:space:]]*-[[:space:]]+/ {
      sub(/^[[:space:]]*-[[:space:]]*/, "")
      print
    }
  ' "$root_dir/pubspec.yaml"
)

clean_package() {
  local package_dir="$1"

  if [[ ! -f "$package_dir/pubspec.yaml" ]]; then
    printf 'error: workspace package has no pubspec.yaml: %s\n' \
      "$package_dir" >&2
    exit 1
  fi

  printf 'Cleaning %s\n' "${package_dir#"$root_dir"/}"
  if ! "$dry_run"; then
    (
      cd "$package_dir"
      "$flutter_bin" clean
    )
  fi
}

clean_package "$root_dir"
for member in "${workspace_members[@]}"; do
  clean_package "$root_dir/$member"
done
