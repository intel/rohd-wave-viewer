#!/usr/bin/env python3

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# fix_bootstrap.py
# Patches generated Flutter bootstrap code for web deployment.
#
# 2026 January
# Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import re
import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BUILD_BOOTSTRAP = os.path.join(SCRIPT_DIR, '..', 'build', 'web', 'flutter_bootstrap.js')

if not os.path.exists(BUILD_BOOTSTRAP):
    print(f"Warning: {BUILD_BOOTSTRAP} not found. Has the Flutter web build completed?", file=sys.stderr)
    sys.exit(0)

with open(BUILD_BOOTSTRAP, 'r') as f:
    content = f.read()

# Add useLocalCanvasKit
content = content.replace('"engineRevision":', '"useLocalCanvasKit":true,"engineRevision":')

# Replace the load call (remove service worker settings)
content = re.sub(
    r'_flutter\.loader\.load\(\{[^}]+serviceWorkerSettings:[^}]+\}[^}]*\}\);',
    '_flutter.loader.load({});',
    content,
    flags=re.DOTALL
)

with open(BUILD_BOOTSTRAP, 'w') as f:
    f.write(content)

print('Done')
