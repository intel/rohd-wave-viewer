#!/bin/sh

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# package_slim_zip.sh
# Packages the staged extension as a slim archive.
#
# 2026 August
# Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

# -----------------------------------------------------------------------------
# Package staged extension into a slim zip for remote installation.
# Does not create a full VSIX; just zips the staged extension directory.
# -----------------------------------------------------------------------------
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Read extension metadata
EXT_PKG="$ROOT/vscode-extension/package.json"
if [ ! -f "$EXT_PKG" ]; then
  echo "Extension package.json not found at $EXT_PKG" >&2
  exit 1
fi

NAME=$(node -p "require('$EXT_PKG').name")
VER=$(node -p "require('$EXT_PKG').version")
EXT_STAGE="$ROOT/build/extension/${NAME}-${VER}"
OUT="$ROOT/build/${NAME}-${VER}-slim.zip"

if [ ! -d "$EXT_STAGE" ]; then
  echo "Staged extension not found at $EXT_STAGE" >&2
  echo "Run 'make extension' first to stage the extension" >&2
  exit 2
fi

echo "Packaging $EXT_STAGE -> $OUT"
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
cd "$EXT_STAGE" && zip -r "$OUT" ./*
echo "Created $OUT"
