#!/usr/bin/env bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# Installs Pana for pub package quality analysis.

set -euo pipefail

dart pub global activate pana
