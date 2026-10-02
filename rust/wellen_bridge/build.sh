#!/usr/bin/env bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# build.sh
# Compatibility wrapper for the supported root WebAssembly build.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "[wellen-bridge] Delegating to 'make wasm' at the repository root."
exec make -C "$ROOT_DIR" wasm
