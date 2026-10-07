// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// platform_io.dart
// Consolidated IO/native platform implementation.
// All no-JS shims and native helpers are inlined here.
//
// 2024 April
// Author(s): Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
//            Max Korbel <max.korbel@intel.com>

import 'dart:async' show unawaited;
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart'
    show consolidateHttpClientResponseBytes;

// ============================================================================
// File utilities
// ============================================================================

/// Read file bytes on native platforms.
Future<List<int>> readFileBytes(String path) {
  final file = File(path);
  return file.readAsBytes();
}

/// Fetch bytes for native platforms. Supports file:// and http(s) URLs.
Future<Uint8List> fetchBytes(String uri) async {
  try {
    final u = Uri.parse(uri);
    if (u.scheme == 'file' || u.scheme.isEmpty) {
      final path = u.scheme == 'file' ? u.toFilePath() : uri;
      final bytes = await readFileBytes(path);
      return Uint8List.fromList(bytes);
    } else if (u.scheme == 'http' || u.scheme == 'https') {
      final client = HttpClient();
      final req = await client.getUrl(u);
      final resp = await req.close();
      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}');
      }
      final bytes = await consolidateHttpClientResponseBytes(resp);
      return Uint8List.fromList(bytes);
    } else {
      throw UnsupportedError('Unsupported URI scheme: ${u.scheme}');
    }
  } on Object catch (_) {
    rethrow;
  }
}

// ============================================================================
// Embed helpers (no-op on native)
// ============================================================================

/// Native no-op stub for signalling that the embed host is ready.
void signalEmbedReadyImpl([Map<String, dynamic>? info]) {}

/// Native no-op stub for posting a message to a JS host.
void postMessageToHostImpl(Object message) {}

/// Returns whether shift is held down (always false on native).
bool isShiftDownFromJsImpl() => false;

/// Returns whether control is held down (always false on native).
bool isControlDownFromJsImpl() => false;

// ============================================================================
// JS bindings helpers (no-op on native)
// ============================================================================

/// Native no-op for `window.requestAnimationFrame`.
void jsRequestAnimationFrame(void Function() cb) {}

/// Native no-op stub for forcing a repaint via JS.
void jsRohdForceRepaint() {}

// ============================================================================
// Window message helpers (no-op on native)
// ============================================================================

/// Callback type for window message listeners.
typedef WindowMessageCallback = void Function(dynamic data);

/// Native no-op for adding a window message listener.
void addWindowMessageListener(WindowMessageCallback cb) {}

/// Native no-op for removing a window message listener.
void removeWindowMessageListener(WindowMessageCallback cb) {}

// ============================================================================
// URL strategy (no-op on native)
// ============================================================================

/// Native no-op for setting a Flutter URL strategy.
void setUrlStrategySafe(dynamic strategy) {}

// ============================================================================
// js_util-like shim (for code that uses getProperty/callMethod/etc.)
// ============================================================================

final _global = <String, dynamic>{};

/// Returns a stand-in for `globalThis` (a Map on native).
dynamic getGlobalThis() => _global;

/// Stand-in for `globalThis` (a Map on native).
dynamic get globalThis => _global;

/// Set a property on the global object (no-op on native).
void setGlobalProperty(String name, dynamic value) {
  _global[name] = value;
}

/// Read a property from a Map-like target (native shim).
dynamic getProperty(dynamic target, dynamic prop) {
  try {
    if (target is Map) {
      return target[prop.toString()];
    }
    return null;
  } on Object catch (_) {
    return null;
  }
}

/// Set a property on a Map-like target (native shim).
void setProperty(dynamic target, dynamic prop, dynamic value) {
  try {
    if (target is Map) {
      target[prop.toString()] = value;
    }
  } on Object catch (_) {}
}

/// Call a method on a Map-like target (native shim).
dynamic callMethod(dynamic target, String method, List<dynamic> args) {
  try {
    final fn = getProperty(target, method);
    if (fn is Function) {
      return Function.apply(fn, args);
    }
  } on Object catch (_) {}
  return null;
}

/// Native no-op for `js_util.allowInterop`; returns the function unchanged.
dynamic allowInterop(Function f) => f;

/// Native no-op for `dartify`; returns the value unchanged.
dynamic dartify(dynamic o) => o;

/// Native no-op for `jsify`; returns the value unchanged.
dynamic jsify(dynamic o) => o;

// ============================================================================
// @JS externals stubs (no-op on native)
// ============================================================================

/// Stub for the JS `rohdEmbed` global (always null on native).
dynamic get rohdEmbed => null;

/// Native stub mirroring the `RohdEmbed` JS object.
class RohdEmbed {
  /// Stub for `onMessage`; always null on native.
  dynamic get onMessage => null;

  /// Stub for `postMessage`; no-op on native.
  void postMessage(dynamic msg) {}
}

/// Native no-op for forcing the host to repaint.
void rohdForceRepaint() {}

/// Stub for the JS `postRohd` global (always null on native).
dynamic get postRohd => null;

/// Native shim that schedules `callback` on the next microtask.
void requestAnimationFrame(void Function(num timestamp) callback) {
  unawaited(Future.microtask(() => callback(0)));
}

// Public embed API wrappers (moved from lib/embed.dart)

/// Signal to the embed host that the app is ready.
void signalEmbedReady([Map<String, dynamic>? info]) =>
    signalEmbedReadyImpl(info);

/// Post a message to the embed host.
void postMessageToHost(Object message) => postMessageToHostImpl(message);

/// Whether shift is held down (false on native).
bool isShiftDownFromJs() => isShiftDownFromJsImpl();

/// Whether control is held down (false on native).
bool isControlDownFromJs() => isControlDownFromJsImpl();

// Stub for getGlobalPropertyExported to match platform_web.dart
/// Read a global property by name from the native global Map shim.
dynamic getGlobalPropertyExported(String name) => _global[name];

// ============================================================================
// File System Access API stubs (native uses file paths directly)
// ============================================================================

/// On native platforms, File System Access API is not used.
bool get isFileSystemAccessSupported => false;

/// Stub FileSystemHandle for native platforms.
/// On native, we use file paths directly instead.
class FileSystemHandle {
  /// File path for the underlying file.
  final String path;

  /// Display name for the underlying file.
  final String name;

  /// Create a handle from an absolute path and display name.
  FileSystemHandle.fromPath(this.path, this.name);

  /// Read bytes from the file system using the stored path.
  Future<List<int>> readBytes() => readFileBytes(path);
}

/// Check whether a color emoji font (Noto Color Emoji) is installed.
/// Returns true if `fc-list` reports `Noto Color Emoji`.
Future<bool> isEmojiFontInstalled() async {
  try {
    final result = await Process.run('fc-list', []);
    if (result.exitCode == 0) {
      final out = result.stdout.toString().toLowerCase();
      return out.contains('noto color emoji');
    }
  } on Object catch (_) {}
  return false;
}

/// Create a FileSystemHandle from a file path (native only).
FileSystemHandle createFileHandleFromPath(String path, String name) =>
    FileSystemHandle.fromPath(path, name);

/// Stub for showOpenFilePickerNative - not used on native.
Future<FileSystemHandle?> showOpenFilePickerNative({
  List<String>? extensions,
}) async =>
    // On native, we don't use this - FilePicker provides paths directly
    null;

/// Stub for showSaveFilePickerNative - not used on native.
Future<bool> showSaveFilePickerNative({
  required List<int> bytes,
  String suggestedName = 'signals.json',
  List<String>? extensions,
}) async =>
    false;

/// Stub for triggerBrowserDownload - not applicable on native.
void triggerBrowserDownload(List<int> bytes, String fileName) {
  // No-op on native platforms; use FilePicker.platform.saveFile instead.
}
