#!/bin/sh

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# install_extension_server.sh
# Installs the Wave Viewer extension on a VS Code remote server.
#
# 2026 August
# Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

# -----------------------------------------------------------------------------
# Install rohd-wave-viewer extension to VS Code remote server.
# Accepts either a slim zip or a VSIX package.
# -----------------------------------------------------------------------------
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$1"

if [ -x /usr/bin/node ] && [ "$(/usr/bin/node -p "process.versions.node.split('.')[0]")" -eq 24 ]; then
  PATH="/usr/bin:$PATH"
fi

if command -v node >/dev/null 2>&1; then
  NODE_MAJOR=$(node -p "process.versions.node.split('.')[0]")
else
  NODE_MAJOR=0
fi

if [ "$NODE_MAJOR" -ne 24 ] && [ -s "$HOME/.nvm/nvm.sh" ]; then
  # Keep the remote install path aligned with the repo's .nvmrc expectation.
  . "$HOME/.nvm/nvm.sh"
  nvm use --silent 24 >/dev/null 2>&1 || true
fi

if ! command -v node >/dev/null 2>&1; then
  echo "Node.js not found; expected Node 24 to install the extension" >&2
  exit 6
fi

NODE_BIN=$(command -v node)
NODE_MAJOR=$($NODE_BIN -p "process.versions.node.split('.')[0]")
if [ "$NODE_MAJOR" -ne 24 ]; then
  echo "Node $($NODE_BIN -v) is active; expected Node 24 to install the extension" >&2
  exit 6
fi

if [ -z "$PKG" ]; then
  echo "Usage: $0 <path-to-zip-or-vsix>" >&2
  exit 2
fi
if [ ! -f "$PKG" ]; then
  echo "Package $PKG not found" >&2
  exit 3
fi

# Read extension metadata from the canonical extension manifest.
EXT_PKG="$ROOT/vscode-extension/package.json"
if [ ! -f "$EXT_PKG" ]; then
  echo "Extension package.json not found at $EXT_PKG" >&2
  exit 4
fi

PUBLISHER=$($NODE_BIN -p "require('$EXT_PKG').publisher || 'intel'")
NAME=$($NODE_BIN -p "require('$EXT_PKG').name")
VER=$($NODE_BIN -p "require('$EXT_PKG').version")
EXT_DIR="$HOME/.vscode-server/extensions/${PUBLISHER}.${NAME}-${VER}"
echo "Installing $PKG -> $EXT_DIR"
mkdir -p "$EXT_DIR"

# Detect if file looks like a VSIX (contains 'extension/' or 'extension/package.json')
if unzip -l "$PKG" | grep -q "extension/package.json" 2>/dev/null; then
  echo "Detected VSIX package; extracting package contents"
  TMPDIR=$(mktemp -d /tmp/vsix_pkg_XXXX)
  unzip -o "$PKG" -d "$TMPDIR"
  # Move package contents (usually under 'extension/') into EXT_DIR
  if [ -d "$TMPDIR/extension" ]; then
    rm -rf "$EXT_DIR"/* || true
    cp -a "$TMPDIR/extension/." "$EXT_DIR/"
  else
    echo "VSIX did not contain expected 'extension/' folder; aborting" >&2
    rm -rf "$TMPDIR"
    exit 5
  fi
  rm -rf "$TMPDIR"
else
  echo "Assuming slim package (runtime zip); extracting into extension dir"
  unzip -o "$PKG" -d "$EXT_DIR"
fi

echo "Installed to $EXT_DIR"

# ---------------------------------------------------------------------------
# Update VS Code's extensions.json manifest so the new version is recognised
# after a window reload without requiring a full restart.
# ---------------------------------------------------------------------------
EXT_ID="${PUBLISHER}.${NAME}"
MANIFEST="$HOME/.vscode-server/extensions/extensions.json"

if [ -f "$MANIFEST" ] && command -v python3 >/dev/null 2>&1; then
  python3 - "$MANIFEST" "$EXT_ID" "$VER" "$EXT_DIR" <<'PYEOF'
import json, sys, os, time

manifest_path, ext_id, ver, ext_dir = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

with open(manifest_path) as f:
    data = json.load(f)

found = False
for ext in data:
    ident = ext.get("identifier", {}).get("id", "")
    if ident == ext_id:
        ext["version"] = ver
        loc = ext.get("location", {})
        if isinstance(loc, dict) and "path" in loc:
            loc["path"] = ext_dir
        else:
            ext["location"] = {"$mid": 1, "path": ext_dir, "scheme": "file"}
        if "relativeLocation" in ext:
            ext["relativeLocation"] = os.path.basename(ext_dir)
        found = True
        break

if not found:
    # Add a new entry matching VS Code's expected schema
    data.append({
        "identifier": {"id": ext_id},
        "version": ver,
        "location": {"$mid": 1, "path": ext_dir, "scheme": "file"},
        "relativeLocation": os.path.basename(ext_dir),
        "metadata": {
            "installedTimestamp": int(time.time() * 1000)
        }
    })

with open(manifest_path, "w") as f:
    json.dump(data, f, indent="\t")
    f.write("\n")

action = "Updated" if found else "Added"
print(f"{action} {ext_id} v{ver} in extensions.json")
PYEOF
else
  echo "Warning: could not update extensions.json (python3 or manifest not found)"
fi

exit 0
