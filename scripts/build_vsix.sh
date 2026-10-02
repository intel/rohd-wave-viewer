#!/usr/bin/env bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# Packages an already staged extension directory as a VSIX archive.

set -euo pipefail

if (($# != 2)); then
  printf 'usage: %s <staged-extension-dir> <output-vsix>\n' "$0" >&2
  exit 64
fi

stage_dir="$1"
output_vsix="$2"

if [[ ! -f "$stage_dir/package.json" ]]; then
  printf 'error: staged extension manifest not found: %s/package.json\n' \
    "$stage_dir" >&2
  exit 1
fi

package_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$package_dir"
}
trap cleanup EXIT

mkdir -p "$package_dir/extension"
cp -a "$stage_dir/." "$package_dir/extension/"
mkdir -p "$(dirname "$output_vsix")"
rm -f "$output_vsix"

(
  cd "$package_dir"
  zip -qr "$output_vsix" extension
)

printf 'Created %s\n' "$output_vsix"
