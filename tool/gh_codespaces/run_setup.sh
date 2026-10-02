#!/bin/bash

# Copyright (C) 2023-2024 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# run_setup.sh
# GitHub Codespaces setup: Setting up the development environment.
#
# 2023 February 5
# Author: Chykon

set -euo pipefail

# Install Flutter
tool/gh_codespaces/install_flutter.sh

# Put either supported installation location on the active process path.
export PATH="$HOME/flutter/bin:/usr/local/flutter/bin:$PATH"

# Install build tools (C++ toolchain, GTK, etc.)
tool/gh_actions/install_build_tools.sh

# Install the pinned Rust toolchain and Flutter Rust Bridge generator.
tool/gh_actions/install_rust_1_92.sh

# Install Pub workspace dependencies.
tool/gh_actions/install_dependencies.sh
