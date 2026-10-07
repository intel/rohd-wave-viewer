// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// platform_web.dart
// Consolidated web platform implementation.
// All web-specific helpers delegated to js_interop_bridge.
//
// 2024 April
// Author(s): Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
//            Max Korbel <max.korbel@intel.com>

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter_web_plugins/flutter_web_plugins.dart' as web_plugins;
import 'package:rohd_wave_viewer/src/platform/js_interop_bridge.dart';
import 'package:web/web.dart' as web;

export 'js_interop_bridge.dart'
    show
        FileSystemHandle,
        allowInterop,
        callMethod,
        dartify,
        getGlobalThis,
        getProperty,
        isFileSystemAccessSupported,
        jsify,
        rohdEmbed,
        setGlobalProperty,
        showOpenFilePickerNative,
        showSaveFilePickerNative;

/// Getter for the global JavaScript object.
dynamic get globalThis => getGlobalThis();

/// Add an event listener to a JavaScript object (like window).
void addEventListener(dynamic target, String eventType, dynamic callback) {
  try {
    callMethod(target, 'addEventListener', [eventType, callback as JSAny?]);
  } on Object catch (e) {
    // Browser console output is the only available diagnostics channel here.
    // ignore: avoid_print
    print('[platform_web] addEventListener failed: $e');
  }
}

/// Set a property on a JavaScript object.
void setProperty(dynamic target, String prop, dynamic value) {
  if (target is Map) {
    target[prop] = value;
    return;
  }
  // For JS objects, we need to use the JS interop
  try {
    (target as JSObject).setProperty(prop.toJS, jsify(value));
  } on Object catch (_) {}
}

// ============================================================================
// File utilities (stub on web)
// ============================================================================

/// Stub implementation for web where direct file access isn't available.
/// Throws [UnsupportedError] since direct file access is not available on web.
Future<List<int>> readFileBytes(String path) => Future<List<int>>.error(
      UnsupportedError('readFileBytes is not supported on web'),
    );

// ============================================================================
// Embed helpers
// ============================================================================

/// Signals to the host that the embedded viewer is ready.
void signalEmbedReadyImpl([Map<String, dynamic>? info]) {
  try {
    final payload = Map<String, dynamic>.from(info ?? {'initialized': true});
    payload['reloaded_in_gui'] = true;
    try {
      final console = getGlobalProperty('console');
      if (console != null) {
        callMethod(console, 'log', [
          '[embed] signalEmbedReady called',
          jsify(payload),
        ]);
      }
    } on Object catch (_) {}
    try {
      final cb = getGlobalProperty('__rohdEmbedReady');
      if (cb != null) {
        // The bridge exposes globals as JSObject values, including functions.
        // Invoke through Function.call so this works without an unsafe cast.
        callMethod(cb, 'call', [getGlobalProperty('window'), jsify(payload)]);
      }
    } on Object catch (_) {}
  } on Object catch (_) {}
}

/// Posts a message from the web viewer to the embedding host.
void postMessageToHostImpl(Object message) {
  final jsMessage = message.jsify();
  try {
    final post =
        (web.window as JSObject).getProperty('postRohd'.toJS) as JSFunction?;
    if (post != null && post.isA<JSFunction>()) {
      post.callAsFunction(web.window, jsMessage);
      return;
    }
  } on Object catch (e) {
    // The VS Code embed shim forwards browser console output to its output
    // channel, which is the only diagnostics path available at this layer.
    // ignore: avoid_print
    print('[platform_web] postRohd failed: $e');
  }

  try {
    final embed =
        (web.window as JSObject).getProperty('rohdEmbed'.toJS) as JSObject?;
    final post = embed?.getProperty('postMessage'.toJS) as JSFunction?;
    if (post != null && post.isA<JSFunction>()) {
      post.callAsFunction(embed, jsMessage);
      return;
    }
  } on Object catch (e) {
    // The VS Code embed shim forwards browser console output to its output
    // channel, which is the only diagnostics path available at this layer.
    // ignore: avoid_print
    print('[platform_web] rohdEmbed.postMessage failed: $e');
  }

  // The VS Code embed shim forwards browser console output to its output
  // channel, which is the only diagnostics path available at this layer.
  // ignore: avoid_print
  print('[platform_web] no host message bridge is available');
}

/// Returns whether the Shift key is currently pressed.
bool isShiftDownFromJsImpl() {
  try {
    final jsVal = getGlobalProperty('__shiftDown');
    if (jsVal == null) {
      return false;
    }
    final dartVal = dartify(jsVal as JSAny?);
    if (dartVal is bool) {
      return dartVal;
    }
    return jsVal.toString().toLowerCase() == 'true';
  } on Object catch (_) {
    return false;
  }
}

/// Returns whether the Control key is currently pressed.
bool isControlDownFromJsImpl() {
  try {
    final jsVal = getGlobalProperty('__controlDown');
    if (jsVal == null) {
      return false;
    }
    final dartVal = dartify(jsVal as JSAny?);
    if (dartVal is bool) {
      return dartVal;
    }
    return jsVal.toString().toLowerCase() == 'true';
  } on Object catch (_) {
    return false;
  }
}

// ============================================================================
// JS bindings helpers
// ============================================================================

/// Requests a repaint callback on the next animation frame.
void jsRequestAnimationFrame(void Function() cb) {
  try {
    requestAnimationFrame(
      allowInterop((_) {
        try {
          cb();
        } on Object catch (_) {}
      }),
    );
  } on Object catch (_) {}
}

/// Forces a repaint in the ROHD web host when available.
void jsRohdForceRepaint() {
  try {
    rohdForceRepaint();
  } on Object catch (_) {}
}

// ============================================================================
// Window message helpers
// ============================================================================

/// Callback signature for window message events.
typedef WindowMessageCallback = void Function(dynamic data);

/// Adds a listener for window message events.
void addWindowMessageListener(WindowMessageCallback cb) {
  try {
    callGlobalMethod('addEventListener', [
      'message',
      allowInterop((dynamic e) {
        try {
          final data = getProperty(e, 'data') as JSAny?;
          if (data == null) {
            return;
          }
          final dartified = dartify(data);
          if (dartified is String) {
            try {
              cb(json.decode(dartified));
              return;
            } on Object catch (_) {}
          }
          if (dartified != null) {
            cb(dartified);
            return;
          }
          cb(dartified);
        } on Object catch (_) {}
      }),
    ]);
  } on Object catch (_) {}
}

/// Removes a window message listener (currently a no-op).
void removeWindowMessageListener(WindowMessageCallback cb) {
  // No-op: listener removal not yet implemented
}

// ============================================================================
// Fetch helpers
// ============================================================================

/// Fetch bytes from a URI in the web environment. Returns a Uint8List.
/// Uses ArrayBuffer → ByteBuffer → Uint8List for efficient bulk transfer
/// (no byte-by-byte copy).
Future<Uint8List> fetchBytes(String uri) async {
  try {
    final response = await web.window.fetch(uri.toJS).toDart;
    if (!response.ok) {
      throw Exception('HTTP ${response.status} ${response.statusText}');
    }
    final arrayBuffer = await response.arrayBuffer().toDart;
    return arrayBuffer.toDart.asUint8List();
  } on Object catch (e) {
    throw Exception('fetchBytes failed for $uri: $e');
  }
}

// ============================================================================
// URL strategy
// ============================================================================

/// Sets the URL strategy for the web app.
void setUrlStrategySafe(dynamic strategy) {
  web_plugins.setUrlStrategy(strategy as web_plugins.UrlStrategy?);
}

/// Signals to the host that the embedded viewer is ready.
void signalEmbedReady([Map<String, dynamic>? info]) =>
    signalEmbedReadyImpl(info);

/// Posts a message from the viewer to the embedding host.
void postMessageToHost(Object message) => postMessageToHostImpl(message);

/// Returns whether the Shift key is currently pressed.
bool isShiftDownFromJs() => isShiftDownFromJsImpl();

/// Returns whether the Control key is currently pressed.
bool isControlDownFromJs() => isControlDownFromJsImpl();

/// Returns a global JavaScript property by [name].
dynamic getGlobalPropertyExported(String name) => getGlobalProperty(name);

/// Web: emoji fonts are natively supported by browsers.
/// Return true to enable color emoji in the UI by default.
Future<bool> isEmojiFontInstalled() async => true;

/// Trigger a browser download of [bytes] with the given [fileName].
///
/// Works in VS Code webviews and regular browsers by creating a temporary
/// anchor element with a Blob URL.
void triggerBrowserDownload(List<int> bytes, String fileName) {
  final blob = web.Blob(
    [Uint8List.fromList(bytes).toJS].toJS,
    web.BlobPropertyBag(type: 'application/octet-stream'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  web.document.body?.append(anchor);
  anchor
    ..click()
    ..remove();
  web.URL.revokeObjectURL(url);
}
