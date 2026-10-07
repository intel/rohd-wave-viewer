#!/usr/bin/env bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# Ensures the waveform client core can move to the rohd repository without
# depending on application-specific Wave Viewer code.

set -euo pipefail

root_dir="$(cd "$(dirname "$0")/../.." && pwd)"
core_dir="$root_dir/lib/src/waveform_client_core"

invalid_imports="$(
  find "$core_dir" -name '*.dart' -print0 |
    xargs -0 awk '
    /^import / {
      line = $0
      if (line ~ /^import .dart:/ || line ~ /^import .package:rohd_hierarchy\// || line ~ /^import .package:rohd_waveform\// || line ~ /^import .package:rohd_wave_viewer\/src\/waveform_client_core\//) {
        next
      }
      print FILENAME ":" FNR ":" line
    }
  '
)"

if [[ -n "$invalid_imports" ]]; then
  printf '%s\n' \
    'error: waveform_client_core imports code outside its movable boundary:' \
    "$invalid_imports" >&2
  exit 1
fi

printf 'Waveform client core dependency boundary verified.\n'
