#!/usr/bin/env bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# wave_run.sh
# Runs the Wave Viewer with the currently selected dependency configuration.
#
# 2026 August
# Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

set -euo pipefail

cd "$(dirname "$0")/.."

bash scripts/verify_flutter_version.sh

run_mode="${1:-}"

usage() {
  cat <<'USAGE'
Usage: scripts/wave_run.sh <run-mode>

Dependency sources are selected separately with scripts/wave_dev_mode.sh.
This command runs using the currently generated dependency configuration.
Run modes: web-debug, web-release, linux-debug, linux-release
USAGE
}

if [[ -z "$run_mode" ]]; then
  usage >&2
  exit 2
fi

case "$run_mode" in
  -h|--help|help) usage; exit 0 ;;
esac

flutter pub get

case "$run_mode" in
  web-debug)
    make wasm
    flutter run -d web-server --web-port=9299 --web-hostname=127.0.0.1 lib/main_web.dart
    ;;
  web-release)
    make wasm
    flutter run --release --wasm -d web-server --web-port=9299 --web-hostname=127.0.0.1 lib/main_web.dart
    ;;
  linux-debug)
    make rust-native
    LD_LIBRARY_PATH="$PWD/build/native_assets/linux:$PWD/rust/wellen_bridge/target/release:${LD_LIBRARY_PATH:-}" flutter run -d linux --debug --enable-software-rendering
    ;;
  linux-release)
    make rust-native
    LD_LIBRARY_PATH="$PWD/build/native_assets/linux:$PWD/rust/wellen_bridge/target/release:${LD_LIBRARY_PATH:-}" flutter run -d linux --release
    ;;
  *) usage >&2; exit 2 ;;
esac
