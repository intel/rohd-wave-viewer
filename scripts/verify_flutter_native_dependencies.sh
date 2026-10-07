#!/usr/bin/env bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# verify_flutter_native_dependencies.sh
# Verifies native library versions in Flutter build artifacts.
#
# 2026 August
# Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

set -euo pipefail

minimum_libpng='1.6.58'
excepted_libpng='1.6.54'
minimum_zlib='1.3.2'
excepted_zlib='1.3.1'
exception_file='security/native-dependency-exceptions.json'

if [[ "$#" -eq 0 ]]; then
  echo "usage: $0 <Flutter engine artifact> [...]" >&2
  exit 64
fi

version_at_least() {
  local actual="$1"
  local minimum="$2"
  [[ "$(printf '%s\n%s\n' "$minimum" "$actual" | sort -V | head -n1)" == "$minimum" ]]
}

extract_version() {
  local artifact="$1"
  local pattern="$2"
  strings "$artifact" | grep -E -m1 "$pattern" || true
}

for artifact in "$@"; do
  if [[ ! -f "$artifact" ]]; then
    echo "error: Flutter engine artifact not found: $artifact" >&2
    exit 1
  fi

  libpng_version="$(extract_version "$artifact" '^1\.6\.[0-9]+$')"
  zlib_version="$(extract_version "$artifact" '^1\.3\.[0-9]+$')"

  if [[ -z "$libpng_version" ]]; then
    echo "error: could not identify libpng in $artifact." >&2
    exit 1
  fi
  if ! version_at_least "$libpng_version" "$minimum_libpng"; then
    if [[ "$libpng_version" != "$excepted_libpng" || ! -f "$exception_file" ]]; then
      echo "error: $artifact requires libpng $minimum_libpng or newer; found $libpng_version." >&2
      exit 1
    fi
    echo "warning: accepting Flutter libpng $libpng_version under $exception_file."
  fi

  if [[ -z "$zlib_version" ]]; then
    echo "error: could not identify zlib in $artifact." >&2
    exit 1
  fi
  if ! version_at_least "$zlib_version" "$minimum_zlib"; then
    if [[ "$zlib_version" != "$excepted_zlib" || ! -f "$exception_file" ]]; then
      echo "error: $artifact requires zlib $minimum_zlib or newer; found $zlib_version." >&2
      exit 1
    fi
    echo "warning: accepting Flutter Chromium zlib $zlib_version under $exception_file."
  fi

  echo "$artifact: libpng $libpng_version, zlib $zlib_version"
done
