#!/bin/bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# patch_wasm_js.sh
# Patch wellen_bridge.js to handle Table.grow() failures in VS Code Remote webviews
# See doc/WASM_WEBVIEW_PATCH.md for details
#
# 2026 January
# Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Check both source and build locations
JS_FILES=(
    "$ROOT_DIR/web/pkg/wellen_bridge.js"
    "$ROOT_DIR/build/web/pkg/wellen_bridge.js"
)

patched=0
for JS_FILE in "${JS_FILES[@]}"; do
    if [ ! -f "$JS_FILE" ]; then
        echo "[patch_wasm_js] Skipping $JS_FILE (not found)"
        continue
    fi

    # Check if already patched
    if grep -q "Table.grow.*failed, using fallback" "$JS_FILE" 2>/dev/null; then
        echo "[patch_wasm_js] $JS_FILE already patched"
        rm -f "${JS_FILE}.bak"
        continue
    fi

    echo "[patch_wasm_js] Patching $JS_FILE..."
    
    # Backup original
    cp "$JS_FILE" "${JS_FILE}.bak"
    
    # Replace the table.grow(4) pattern with try/catch wrapper
    # The original pattern is: const offset = table.grow(4);
    sed -i 's/const offset = table\.grow(4);/let offset; try { offset = table.grow(4); } catch (e) { console.warn("Table.grow(4) failed, using fallback:", e.message); offset = table.length - 4; }/g' "$JS_FILE"
    
    # Verify patch was applied
    if grep -q "Table.grow.*failed, using fallback" "$JS_FILE"; then
        echo "[patch_wasm_js] Successfully patched $JS_FILE"
        rm -f "${JS_FILE}.bak"
        patched=$((patched + 1))
    else
        echo "[patch_wasm_js] Warning: patch may not have applied to $JS_FILE"
    fi
done

if [ $patched -eq 0 ]; then
    # Check if files were already patched (success case)
    already_patched=0
    for JS_FILE in "${JS_FILES[@]}"; do
        if [ -f "$JS_FILE" ] && grep -q "Table.grow.*failed, using fallback" "$JS_FILE" 2>/dev/null; then
            already_patched=$((already_patched + 1))
        fi
    done
    
    if [ $already_patched -gt 0 ]; then
        echo "[patch_wasm_js] $already_patched file(s) were already patched."
        exit 0
    else
        echo "[patch_wasm_js] No files were patched. Run 'make wasm' first to generate the WASM files."
        exit 1
    fi
fi

echo "[patch_wasm_js] Done. $patched file(s) patched."
