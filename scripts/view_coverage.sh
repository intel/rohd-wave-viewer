#!/usr/bin/env bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# view_coverage.sh
# Serves the generated coverage report locally.
#
# 2026 August
# Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HTML_DIR="$ROOT_DIR/coverage/html"
PORT="${COVERAGE_PORT:-8000}"

if [[ ! -f "$HTML_DIR/index.html" ]]; then
  "$ROOT_DIR/scripts/generate_coverage.sh"
fi

printf 'Serving coverage report at http://127.0.0.1:%s\n' "$PORT"
cd "$HTML_DIR"
python3 -m http.server "$PORT" --bind 127.0.0.1