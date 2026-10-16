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
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! -f "$stage_dir/package.json" ]]; then
  printf 'error: staged extension manifest not found: %s/package.json\n' \
    "$stage_dir" >&2
  exit 1
fi

vsce="$root_dir/vscode-extension/node_modules/.bin/vsce"
if [[ ! -x "$vsce" ]]; then
  printf 'error: pinned @vscode/vsce is not installed; run npm ci in vscode-extension\n' >&2
  exit 1
fi

mkdir -p "$(dirname "$output_vsix")"
(
  cd "$stage_dir"
  "$vsce" package --no-dependencies --out "$output_vsix"
)

printf 'Created %s\n' "$output_vsix"
