// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// vscode_webview_interop_io.dart
// IO stub for VS Code webview integration (non-web platforms).
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:typed_data';

/// Stub for native platforms - no VS Code webview integration.
Uint8List? getInjectedVcdBytes() => null;

/// Stub for native platforms - no injected filename.
String? getInjectedVcdFilename() => null;

/// Returns false on native platforms - not running in VS Code webview.
bool isVscodeWebview() => false;

/// Stub for requesting reload from extension.
void requestExtensionReload() {
  // No-op on native platforms
}

/// Stub for requesting signal list load via extension.
Future<String?> requestExtensionLoadSignalList() async => null;

/// Stub for requesting signal list save via extension.
void requestExtensionSaveSignalList(
  String jsonContent, {
  String fileName = 'signals.json',
}) {
  // No-op on native platforms
}

/// Stub for posting goToSource message to extension host.
bool postGoToSourceByName({
  required List<Map<String, String>> signals,
  String? format,
}) =>
    false;

/// Stub for posting savePng message to extension host.
bool postSavePng({required String pngBase64, required String suggestedName}) =>
    false;
