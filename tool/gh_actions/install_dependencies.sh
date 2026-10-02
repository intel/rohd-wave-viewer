#!/bin/bash

# Copyright (C) 2023-2024 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# install_dependencies.sh
# GitHub Actions step: Install dependencies for the complete Pub workspace.
#
# 2023 August 01
# Author: Yao Jing Quek <yao.jing.quek@intel.com>
#

set -euo pipefail

cd "$(dirname "$0")/../.."

bash scripts/verify_flutter_version.sh

flutter_bin="${FLUTTER:-flutter}"

dependency_mode="${ROHD_WAVE_DEPENDENCY_MODE:-}"
if [[ -n "$dependency_mode" ]]; then
	bash scripts/wave_dev_mode.sh "$dependency_mode"
elif [[ -n "${ROHD_LOCAL_PATH:-}" ]]; then
	bash scripts/wave_dev_mode.sh local-all
fi

"$flutter_bin" pub get
