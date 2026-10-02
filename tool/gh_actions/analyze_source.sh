#!/bin/bash

# Copyright (C) 2022-2024 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# analyze_source.sh
# GitHub Actions step: Analyze the complete Pub workspace.
#
# 2022 October 9
# Author: Chykon

set -euo pipefail

make dart
flutter analyze --fatal-infos
