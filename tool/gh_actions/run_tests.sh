#!/bin/bash

# Copyright (C) 2023-2024 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# run_tests.sh
# Runs tests for every package in the ROHD Wave Viewer Pub workspace.
#
# 2023 September 21
# Author: Max Korbel <max.korbel@intel.com>

set -euo pipefail

cd "$(dirname "$0")/../.."

# The devcontainer installer uses $HOME for non-root users.
export PATH="$HOME/flutter/bin:/usr/local/flutter/bin:$PATH"

bash scripts/verify_flutter_version.sh

flutter_bin="$(readlink -f "$(command -v flutter)")"
dart_bin="$(dirname "$flutter_bin")/dart"

make rust-native

export LD_LIBRARY_PATH="$PWD/build/native_assets/linux:$PWD/rust/wellen_bridge/target/release:${LD_LIBRARY_PATH:-}"

flutter test "$@"

# Arguments select root-package tests. A complete run also validates the
# pure-Dart dart_wellen workspace member from its own package root.
if [[ "$#" -eq 0 ]]; then
  (
    cd packages/dart_wellen
    "$dart_bin" run test:test
  )
fi