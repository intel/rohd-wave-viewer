// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// vscode_extension_client_stub.dart
// Native stub for the VS Code webview extension client.
//
// 2026 May
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart';

/// Creates the platform-appropriate [RohdExtensionClient] for VS Code webview
/// mode.  On native platforms this always returns a [NullExtensionClient].
RohdExtensionClient createVscodeExtensionClient() => NullExtensionClient();
