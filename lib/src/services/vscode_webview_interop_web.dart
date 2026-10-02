// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// vscode_webview_interop_web.dart
// Web implementation for VS Code webview integration.
// Reads VCD data injected as global variable by the extension.
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

// Runtime checks are required while normalizing VS Code JavaScript messages.
// ignore_for_file: invalid_runtime_check_with_js_interop_types

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

/// JavaScript interop for accessing window properties
@JS('window.VCD_BASE64')
external JSString? get _vcdBase64;

@JS('window.VCD_FILENAME')
external JSString? get _vcdFilename;

@JS('window.VSCODE_WEBVIEW')
external JSBoolean? get _vscodeWebview;

/// Gets the injected VCD data from VS Code webview as bytes.
/// Returns null if not running in VS Code webview or no VCD was injected.
Uint8List? getInjectedVcdBytes() {
  try {
    final base64Data = _vcdBase64;
    if (base64Data == null) {
      return null;
    }
    final base64String = base64Data.toDart;
    if (base64String.isEmpty) {
      return null;
    }
    // Decode base64 to get the original bytes
    return base64Decode(base64String);
  } on Object catch (_) {
    throw Exception('[VCD Interop] Error getting injected VCD');
  }
}

/// Gets the injected VCD filename.
String? getInjectedVcdFilename() {
  try {
    final filename = _vcdFilename;
    return filename?.toDart;
  } on Object catch (_) {
    return null;
  }
}

/// Returns true if running in VS Code webview context.
bool isVscodeWebview() {
  try {
    final flag = _vscodeWebview;
    return flag?.toDart ?? false;
  } on Object catch (_) {
    return false;
  }
}

/// Request the VS Code extension to reload the original file.
/// This sends a message to the extension which re-reads and re-sends the file.
void requestExtensionReload() {
  try {
    // Use the vscode.postMessage API via rohdEmbed
    final rohdEmbed = (web.window as JSObject).getProperty('rohdEmbed'.toJS);
    if (rohdEmbed != null) {
      final postFn = (rohdEmbed as JSObject).getProperty('postMessage'.toJS);
      if (postFn != null && postFn is JSFunction) {
        final msg = <String, dynamic>{'type': 'requestReload'}.jsify();
        postFn.callAsFunction(rohdEmbed, msg);
      }
    }
  } on Object catch (_) {
    // Ignore errors - extension might not be listening
  }
}

/// Ask the VS Code extension to load a signal list via a native Open dialog.
///
/// The extension handles the `loadSignalList` message by showing
/// `vscode.window.showOpenDialog`, reading the file, and posting
/// `loadSignalListResult` back.
///
/// Returns the file content as a String, or null if cancelled/failed.
Future<String?> requestExtensionLoadSignalList() async {
  try {
    final completer = Completer<String?>();

    // Listen for the response from the extension host.
    late final web.EventListener listener;
    listener = (web.Event event) {
      try {
        final me = event as web.MessageEvent;
        final data = me.data;
        if (data == null) {
          return;
        }
        // data comes as a JS object; pull out 'type' property
        final jsObj = data as JSObject;
        final typeVal = jsObj.getProperty('type'.toJS);
        if (typeVal == null) {
          return;
        }
        final type = (typeVal as JSString).toDart;
        if (type != 'loadSignalListResult') {
          return;
        }

        // Remove listener once we get our response
        web.window.removeEventListener('message', listener);

        final successVal = jsObj.getProperty('success'.toJS);
        final success = successVal != null && (successVal as JSBoolean).toDart;
        if (success) {
          final contentVal = jsObj.getProperty('content'.toJS);
          final content =
              contentVal != null ? (contentVal as JSString).toDart : null;
          completer.complete(content);
        } else {
          completer.complete(null);
        }
      } on Object catch (_) {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      }
    }.toJS;

    web.window.addEventListener('message', listener);

    // Post the request to the extension host
    final rohdEmbed = (web.window as JSObject).getProperty('rohdEmbed'.toJS);
    if (rohdEmbed != null) {
      final postFn = (rohdEmbed as JSObject).getProperty('postMessage'.toJS);
      if (postFn != null && postFn is JSFunction) {
        final msg = <String, dynamic>{'type': 'loadSignalList'}.jsify();
        postFn.callAsFunction(rohdEmbed, msg);
      } else {
        web.window.removeEventListener('message', listener);
        return null;
      }
    } else {
      web.window.removeEventListener('message', listener);
      return null;
    }

    return await completer.future;
  } on Object catch (_) {
    return null;
  }
}

/// Ask the VS Code extension to save a signal list via a native Save dialog.
///
/// The extension handles the `saveSignalList` message by showing
/// `vscode.window.showSaveDialog` and writing the file.
void requestExtensionSaveSignalList(
  String jsonContent, {
  String fileName = 'signals.json',
}) {
  try {
    final rohdEmbed = (web.window as JSObject).getProperty('rohdEmbed'.toJS);
    if (rohdEmbed != null) {
      final postFn = (rohdEmbed as JSObject).getProperty('postMessage'.toJS);
      if (postFn != null && postFn is JSFunction) {
        final msg = <String, dynamic>{
          'type': 'saveSignalList',
          'content': jsonContent,
          'fileName': fileName,
        }.jsify();
        postFn.callAsFunction(rohdEmbed, msg);
      }
    }
  } on Object catch (_) {
    throw Exception('[saveSignalList] Failed to post message');
  }
}

/// Post a goToSource message to the VS Code extension host.
///
/// [signals] is a list of maps with 'module' and 'name' keys.
/// [format] is optional — 'rohd' or 'sv' to filter frame types.
/// Returns true if the message was posted, false otherwise.
bool postGoToSourceByName({
  required List<Map<String, String>> signals,
  String? format,
}) {
  try {
    final rohdEmbed = (web.window as JSObject).getProperty('rohdEmbed'.toJS);
    if (rohdEmbed != null) {
      final postFn = (rohdEmbed as JSObject).getProperty('postMessage'.toJS);
      if (postFn != null && postFn is JSFunction) {
        final msg = <String, dynamic>{
          'type': 'goToSource',
          'signals': signals,
          if (format != null) 'format': format,
        }.jsify();
        postFn.callAsFunction(rohdEmbed, msg);
        return true;
      }
    }
    return false;
  } on Object catch (_) {
    return false;
  }
}

/// Post a "save PNG" request to the VS Code extension host.
///
/// The extension shows a native Save dialog, letting the user choose the
/// output path, and writes the base64-encoded PNG bytes there.
///
/// Returns true if the message was posted, false otherwise.
bool postSavePng({required String pngBase64, required String suggestedName}) {
  try {
    final rohdEmbed = (web.window as JSObject).getProperty('rohdEmbed'.toJS);
    if (rohdEmbed != null) {
      final postFn = (rohdEmbed as JSObject).getProperty('postMessage'.toJS);
      if (postFn != null && postFn is JSFunction) {
        final msg = <String, dynamic>{
          'type': 'savePng',
          'data': pngBase64,
          'suggestedName': suggestedName,
        }.jsify();
        postFn.callAsFunction(rohdEmbed, msg);
        return true;
      }
    }
    return false;
  } on Object catch (_) {
    return false;
  }
}
