#!/bin/bash

# Copyright (C) 2022-2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# generate_documentation.sh
# GitHub Actions step: Generate project documentation.
#
# 2022 October 10
# Author: Chykon

set -euo pipefail

# Output parsing is required because "dart doc" is not capable of
# signaling a warning with an exit code:
#   https://github.com/dart-lang/dartdoc/issues/2846
#   https://github.com/dart-lang/dartdoc/issues/2907
#   https://github.com/dart-lang/dartdoc/issues/1959

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

run_dartdoc() {
  local label="$1"
  shift

  local output
  if ! output=$("$@" 2>&1 | tee); then
    printf '%s\n' "$output"
    echo "Documentation generation failed: $label" >&2
    return 1
  fi

  if grep --quiet -E 'warning:|Found [1-9][0-9]* warnings' <<<"$output"; then
    printf '%s\n' "$output"
    echo "Documentation contains warnings: $label" >&2
    return 1
  fi

  if grep --quiet -E 'no issues found|Found 0 warnings and 0 errors' \
    <<<"$output"; then
    echo "Documentation check passed: $label"
    return
  fi

  printf '%s\n' "$output"
  echo "Documentation result was not recognized: $label" >&2
  return 1
}

# Set DARTDOC_OUTPUT to write root documentation somewhere other than
# dartdoc's default doc/api directory.
root_args=(dart doc)
if [[ -n "${DARTDOC_OUTPUT:-}" ]]; then
  root_args+=(--output "${DARTDOC_OUTPUT}")
fi

# Disabling --validate-links due to https://github.com/dart-lang/dartdoc/issues/3584
run_dartdoc rohd_wave_viewer "${root_args[@]}"
run_dartdoc dart_wellen dart doc packages/dart_wellen \
  --output packages/dart_wellen/doc/api
