#!/bin/bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# patch_wasm_binary.sh
# Patches the Wellen bridge WASM externref table export.
#
# 2026 January
# Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

# Patch wellen_bridge WASM binary to fix externref table export bug
# See doc/WASM_WEBVIEW_PATCH.md for details

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if ! command -v wasm2wat &>/dev/null || \
   ! command -v wat2wasm &>/dev/null || \
   ! command -v wasm-objdump &>/dev/null; then
    echo "[patch_wasm_binary] WARNING: wabt tools not found; skipping optional binary patch"
    echo "[patch_wasm_binary] Install them with: $ROOT_DIR/tool/gh_actions/install_wasm_tools.sh"
    exit 0
fi

# Find WASM files to patch
WASM_FILES=(
    "$ROOT_DIR/web/pkg/wellen_bridge_bg.wasm"
    "$ROOT_DIR/build/web/pkg/wellen_bridge_bg.wasm"
)

patched=0
for WASM_FILE in "${WASM_FILES[@]}"; do
    if [ ! -f "$WASM_FILE" ]; then
        echo "[patch_wasm_binary] Skipping $WASM_FILE (not found)"
        continue
    fi

    # Check if already patched by examining the table export
    export_info=$(wasm-objdump -x "$WASM_FILE" 2>/dev/null | grep "__wbindgen_externrefs" || true)
    if echo "$export_info" | grep -q "table\[1\]"; then
        echo "[patch_wasm_binary] $WASM_FILE already patched (exports table[1])"
        rm -f "${WASM_FILE}.bak"
        continue
    fi

    echo "[patch_wasm_binary] Patching $WASM_FILE..."
    
    # Backup original
    cp "$WASM_FILE" "${WASM_FILE}.bak"
    
    # Convert to WAT
    WAT_FILE="${WASM_FILE%.wasm}.wat"
    wasm2wat "$WASM_FILE" -o "$WAT_FILE"
    
    # Fix 1: Change externref table from 128 to 132 initial entries
    # Pattern: (table (;1;) 128 externref)
    sed -i 's/(table (;1;) 128 externref)/(table (;1;) 132 externref)/g' "$WAT_FILE"
    
    # Fix 2: Change export to point to table 1 instead of table 0
    # Pattern: (export "__wbindgen_externrefs" (table 0))
    sed -i 's/(export "__wbindgen_externrefs" (table 0))/(export "__wbindgen_externrefs" (table 1))/g' "$WAT_FILE"
    
    # Convert back to WASM
    wat2wasm "$WAT_FILE" -o "$WASM_FILE"
    
    # Cleanup WAT file
    rm -f "$WAT_FILE"
    
    # Verify patch
    new_export=$(wasm-objdump -x "$WASM_FILE" 2>/dev/null | grep "__wbindgen_externrefs" || true)
    if echo "$new_export" | grep -q "table\[1\]"; then
        echo "[patch_wasm_binary] Successfully patched $WASM_FILE"
        echo "[patch_wasm_binary]   $new_export"
        rm -f "${WASM_FILE}.bak"
        patched=$((patched + 1))
    else
        echo "[patch_wasm_binary] Warning: patch may not have applied correctly"
        echo "[patch_wasm_binary]   $new_export"
    fi
done

if [ $patched -eq 0 ]; then
    # Check if files were already patched
    already_patched=0
    for WASM_FILE in "${WASM_FILES[@]}"; do
        if [ -f "$WASM_FILE" ]; then
            export_info=$(wasm-objdump -x "$WASM_FILE" 2>/dev/null | grep "__wbindgen_externrefs" || true)
            if echo "$export_info" | grep -q "table\[1\]"; then
                already_patched=$((already_patched + 1))
            fi
        fi
    done
    
    if [ $already_patched -gt 0 ]; then
        echo "[patch_wasm_binary] $already_patched file(s) were already patched."
        exit 0
    else
        echo "[patch_wasm_binary] No files were patched."
        exit 1
    fi
fi

echo "[patch_wasm_binary] Done. $patched file(s) patched."
