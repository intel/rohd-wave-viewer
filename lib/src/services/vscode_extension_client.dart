// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// vscode_extension_client.dart
// Conditional VS Code extension client exports.
//
// 2026 August
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

export 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart'
    show RohdExtensionClient, RohdModuleInfo;

export 'vscode_extension_client_stub.dart'
    if (dart.library.js_interop) 'vscode_extension_client_web.dart'
    show createVscodeExtensionClient;
