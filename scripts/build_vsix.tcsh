#!/usr/bin/env bash
set -euo pipefail
# Create a .vsix of the VS Code extension (POSIX sh/bourne compatible)
# NOTE: This repository uses a split layout for the VS Code extension:
# - `vscode-extension/` contains the TypeScript source and the compiled `out/` JavaScript.
# - `vscode-ext-package/extension/` contains packaging and template assets (manifest, media, README) that are copied into the package.
# The script below copies assets from `vscode-ext-package/extension/` and compiled JS from `vscode-extension/out/` into the package directory.

PKG_DIR=$(mktemp -d)
if [ ! -d "$PKG_DIR" ]; then
  echo "Failed to create temp dir" >&2
  exit 1
fi

cleanup() {
  rm -rf "$PKG_DIR"
}
trap cleanup EXIT

# Copy extension package files
mkdir -p "$PKG_DIR/extension"
cp -r vscode-ext-package/extension/* "$PKG_DIR/extension/"

# Copy compiled JS if available
mkdir -p "$PKG_DIR/out"
if [ -f vscode-extension/out/extension.js ]; then
  cp -r vscode-extension/out/* "$PKG_DIR/out/"
fi

# Copy web build if available
if [ -d build/web ]; then
  mkdir -p "$PKG_DIR/media"
  cp -r build/web "$PKG_DIR/media/flutter_web"
fi

OLDPWD=$(pwd)
# Change into the copied extension directory and zip its contents so the
# packaged .vsix has files (package.json, out/, media/) at the archive root.
cd "$PKG_DIR/extension"
zip -r "$OLDPWD/rohd-wave-viewer.vsix" . > /dev/null
rc=$?
cd "$OLDPWD"

if [ -f rohd-wave-viewer.vsix ]; then
  ls -lh rohd-wave-viewer.vsix
else
  echo "Failed to create rohd-wave-viewer.vsix" >&2
  exit 1
fi
