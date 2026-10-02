// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// devtools_shared_ui.dart
// Conditional export facade for shared DevTools UI platform helpers.
//
// 2026 June
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

export 'devtools_shared_ui_io.dart'
    if (dart.library.js_interop) 'package:devtools_app_shared/ui.dart';
