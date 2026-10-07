#!/usr/bin/env bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# run_wasm_test_nvm.sh
# Runs Wellen WASM tests with the configured Node Version Manager.
#
# 2026 January
# Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [ -s "$NVM_DIR/nvm.sh" ]; then
  # shellcheck source=/dev/null
  . "$NVM_DIR/nvm.sh"
else
  echo "Warning: nvm not found at $NVM_DIR. Proceeding with system node if available."
fi

echo "Using Node via nvm (requesting v24)..."
if command -v nvm >/dev/null 2>&1; then
  nvm install 24 >/dev/null 2>&1 || true
  nvm use 24 >/dev/null 2>&1 || true
fi

echo "node: $(command -v node || echo 'not found') $(node --version 2>/dev/null || true)"

# Ensure patched pkg is copied into web/pkg so the harness uses the patched wasm/js
if [ -d "$REPO_ROOT/build/web/pkg" ]; then
  echo "Copying patched build/web/pkg into web/pkg"
  mkdir -p "$REPO_ROOT/web/pkg"
  cp -r "$REPO_ROOT/build/web/pkg/"* "$REPO_ROOT/web/pkg/" || true
else
  echo "Warning: build/web/pkg not found — ensure you ran 'make web' or 'make extension'"
fi

LOGDIR="$REPO_ROOT/build_logs/wasm_test_runs"
mkdir -p "$LOGDIR"
timestamp() { date -u +%Y%m%dT%H%M%SZ; }

# Accept test files as args; if none given, use the default example
if [ "$#" -gt 0 ]; then
  TEST_FILES=("$@")
else
  TEST_FILES=("surfer/examples/vhdl3.vcd")
fi

for tf in "${TEST_FILES[@]}"; do
  abs_test_file="$REPO_ROOT/$tf"
  if [ ! -f "$abs_test_file" ]; then
    echo "Test file not found: $abs_test_file" >&2
    continue
  fi

  export TEST_FILE="$abs_test_file"
  out="${LOGDIR}/wasm_test_$(timestamp)_$(basename "$tf").log"
  echo "Running wasm node test for $abs_test_file -> $out"

  # run harness using the nvm node (or system node)
  bash -lc "export NVM_DIR=\"$NVM_DIR\"; [ -s \"$NVM_DIR/nvm.sh\" ] && . \"$NVM_DIR/nvm.sh\"; nvm use 24 >/dev/null 2>&1 || true; node '$SCRIPT_DIR/run_wasm_node_test.cjs'" > "$out" 2>&1 || echo "Test failed for $tf (see $out)"

  echo "Log written: $out"
done

echo "All done. Logs are in $LOGDIR"
