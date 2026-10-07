// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// js_interop_bridge.dart
// Modernized JS interop using package:web instead of deprecated package:js.
// Centralizes all JS interop imports and provides clean helpers.
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async' show unawaited;
import 'dart:convert' as convert;
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

// Runtime checks are required while normalizing values from JavaScript APIs.
// ignore_for_file: invalid_runtime_check_with_js_interop_types

// ============================================================================
// Global access helpers
// ============================================================================

/// Get the JavaScript global object.
dynamic getGlobalThis() => web.window;

/// Set a property on the global window object.
void setGlobalProperty(String name, JSAny? value) {
  (web.window as JSObject).setProperty(name.toJS, value);
}

/// Get a property from the global object.
dynamic getGlobalProperty(String name) {
  final prop = _getJSProperty(web.window, name);
  return _convertFromJS(prop);
}

/// Call a method on the global object.
dynamic callGlobalMethod(String methodName, List<dynamic> args) =>
    callMethod(web.window, methodName, args);

/// Add an event listener to the window/global.
void addGlobalEventListener(
  String eventName,
  void Function(web.Event event) handler,
) {
  web.window.addEventListener(
    eventName,
    (web.Event event) {
      handler(event);
    }.toJS as web.EventListener,
  );
}

// ============================================================================
// Property and method access helpers
// ============================================================================

/// Get a property from a JavaScript object.
dynamic getProperty(dynamic obj, dynamic prop) {
  final jsValue = _getJSProperty(obj, prop);
  return _convertFromJS(jsValue);
}

/// Internal: Get raw JS property without converting.
JSAny? _getJSProperty(dynamic obj, dynamic prop) {
  final propKey = prop is String ? prop : prop.toString();
  try {
    // Use js_interop_unsafe for dynamic property access
    return (obj as JSObject).getProperty(propKey.toJS);
  } on Object catch (_) {
    return null;
  }
}

/// Call a method on a JavaScript object.
dynamic callMethod(dynamic obj, String methodName, List<dynamic> args) {
  try {
    final jsArgs = args.map(jsify).toList();
    // Use js_interop_unsafe for dynamic method calls
    return (obj as JSObject).callMethod(methodName.toJS, jsArgs.toJS);
  } on Object catch (_) {
    return null;
  }
}

/// Convert a JavaScript Promise to a Dart Future.
Future<T> promiseToFuture<T extends JSAny?>(JSPromise<T> promise) =>
    promise.toDart;

// ============================================================================
// Conversion utilities (bridging package:web and dart:js_interop)
// ============================================================================

/// Convert Dart values to JavaScript values.
JSAny? jsify(dynamic value) {
  if (value is JSAny) {
    return value;
  }
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value.toJS;
  }
  if (value is int) {
    return value.toJS;
  }
  if (value is double) {
    return value.toJS;
  }
  if (value is bool) {
    return value.toJS;
  }
  if (value is List) {
    final arr = <JSAny?>[];
    for (final item in value) {
      arr.add(jsify(item));
    }
    return arr.toJS;
  }
  if (value is Map) {
    final obj = <String, JSAny?>{};
    for (final entry in value.entries) {
      obj[entry.key.toString()] = jsify(entry.value);
    }
    return obj.jsify();
  }
  return value as JSAny?;
}

/// Convert JavaScript values to Dart values.
dynamic dartify(JSAny? value) => _convertFromJS(value);

/// Internal: Convert JS values to Dart.
dynamic _convertFromJS(JSAny? value) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value;
  }
  if (value is int) {
    return value;
  }
  if (value is double) {
    return value;
  }
  if (value is bool) {
    return value;
  }
  // For objects and arrays, try to convert them
  if (value is JSObject) {
    try {
      // Try to parse as JSON string if possible
      return convert.jsonDecode(convert.jsonEncode(value));
    } on Object catch (_) {
      // Return the JS object as-is if conversion fails
      return value;
    }
  }
  return value;
}

/// Wrap a Dart function to be callable from JavaScript.
/// With dart:js_interop, we need to convert to JSFunction using .toJS on a
/// specific function signature. For dynamic callbacks, we use a wrapper.
///
/// Note: This creates a wrapper that accepts a single argument.
JSFunction allowInterop(Function f) {
  // Create a wrapper with a known signature that dart:js_interop can convert
  JSAny? wrapper(JSAny? arg) {
    try {
      final dartArg = dartify(arg);
      final result = Function.apply(f, [dartArg]);
      if (result is Future) {
        // Handle async functions - we can't return the future, just call it
        unawaited(result.catchError((e) => null));
        return null;
      }
      return jsify(result);
    } on Object catch (_) {
      return null;
    }
  }

  return wrapper.toJS;
}

/// Create an interop function that takes no arguments.
JSFunction allowInteropVoid(void Function() f) {
  void wrapper() {
    f();
  }

  return wrapper.toJS;
}

// ============================================================================
// Custom JS bindings (via package:web and dart:js_interop)
// ============================================================================

/// Get the ROHD embed object from the global context.
dynamic get rohdEmbed => getGlobalProperty('rohdEmbed');

/// Force repaint in ROHD.
void rohdForceRepaint() {
  final fn = getGlobalProperty('rohdForceRepaint');
  if (fn != null) {
    (fn as JSFunction).callAsFunction();
  }
}

/// Get the postRohd function from the global context.
dynamic get postRohd => getGlobalProperty('postRohd');

/// Request an animation frame callback.
/// Accepts either a Dart Function or a JSFunction (from allowInterop).
void requestAnimationFrame(dynamic callback) {
  final fn = getGlobalProperty('requestAnimationFrame');
  if (fn != null) {
    JSFunction jsCallback;
    if (callback is JSFunction) {
      jsCallback = callback;
    } else if (callback is Function) {
      // Create a wrapper with the expected signature for requestAnimationFrame
      void wrapper(JSNumber timestamp) {
        try {
          (callback as dynamic)(timestamp.toDartDouble);
        } on Object catch (_) {}
      }

      jsCallback = wrapper.toJS;
    } else {
      return;
    }
    (fn as JSFunction).callAsFunction(web.window, jsCallback);
  }
}

// ============================================================================
// File System Access API bindings
// ============================================================================

/// Check if File System Access API is supported in the current browser.
bool get isFileSystemAccessSupported {
  try {
    final showOpenFilePicker = _getJSProperty(web.window, 'showOpenFilePicker');
    return showOpenFilePicker != null;
  } on Object catch (_) {
    return false;
  }
}

/// Wrapper class for FileSystemFileHandle from the File System Access API.
/// This allows us to store a reference to a file and re-read it later.
class FileSystemHandle {
  final JSObject _handle;

  /// Display name of the underlying file-system entry.
  final String name;

  /// Creates a file-system handle wrapper.
  FileSystemHandle._(this._handle, this.name);

  /// Read fresh bytes from the file system using the stored handle.
  Future<Uint8List> readBytes() async {
    try {
      // Call handle.getFile() which returns a Promise<File>
      final filePromise = _handle.callMethod('getFile'.toJS)! as JSPromise;
      final file = (await filePromise.toDart)! as JSObject;

      // Call file.arrayBuffer() which returns a Promise<ArrayBuffer>
      final arrayBufferPromise =
          file.callMethod('arrayBuffer'.toJS)! as JSPromise;
      final arrayBuffer = await arrayBufferPromise.toDart;

      // Efficiently convert ArrayBuffer directly to Dart Uint8List
      // (avoids the old byte-by-byte copy that caused "Invalid array length"
      //  on large files like 213 MB VCD waveforms)
      final byteBuffer = (arrayBuffer! as JSArrayBuffer).toDart;
      return byteBuffer.asUint8List();
    } on Object catch (_) {
      throw Exception('Failed to read file from handle');
    }
  }
}

/// Open a file picker dialog using the File System Access API.
/// Returns a FileSystemHandle that can be used to re-read the file later.
/// Returns null if the user cancels or the API is not supported.
Future<FileSystemHandle?> showOpenFilePickerNative({
  List<String>? extensions,
}) async {
  if (!isFileSystemAccessSupported) {
    return null;
  }

  try {
    // Build the options object
    final types = <JSAny?>[];
    if (extensions != null && extensions.isNotEmpty) {
      final acceptMap = <String, JSAny?>{};
      // Create accept types like: { 'application/octet-stream': ['.vcd', '.fst'] }
      final extList = extensions.map((e) => '.$e'.toJS).toList();
      acceptMap['application/octet-stream'] = extList.toJS;

      types.add(
        <String, JSAny?>{
          'description': 'Waveform files'.toJS,
          'accept': acceptMap.jsify(),
        }.jsify(),
      );
    }

    final options = <String, JSAny?>{'multiple': false.toJS};
    if (types.isNotEmpty) {
      options['types'] = types.toJS;
    }

    // Call window.showOpenFilePicker(options)
    final showOpenFilePicker =
        _getJSProperty(web.window, 'showOpenFilePicker')! as JSFunction;
    final promise = showOpenFilePicker.callAsFunction(
        web.window, options.jsify())! as JSPromise;

    final handles = (await promise.toDart)! as JSArray;
    if (handles.toDart.isEmpty) {
      return null;
    }

    final handle = handles.toDart.first! as JSObject;
    final name = (handle.getProperty('name'.toJS)! as JSString).toDart;

    return FileSystemHandle._(handle, name);
  } on Object catch (_) {
    // User cancelled or error occurred
    // DOMException with name 'AbortError' means user cancelled
    return null;
  }
}

/// Save bytes to a file using the File System Access API.
/// Opens a native save dialog and writes the bytes to the chosen file.
/// Returns true if the file was saved, false if the user cancelled.
Future<bool> showSaveFilePickerNative({
  required Uint8List bytes,
  String suggestedName = 'signals.json',
  List<String>? extensions,
}) async {
  if (!isFileSystemAccessSupported) {
    return false;
  }

  try {
    // Build the options object
    final options = <String, JSAny?>{'suggestedName': suggestedName.toJS};

    if (extensions != null && extensions.isNotEmpty) {
      final acceptMap = <String, JSAny?>{};
      final extList = extensions.map((e) => '.$e'.toJS).toList();
      acceptMap['application/json'] = extList.toJS;

      final types = [
        <String, JSAny?>{
          'description': 'JSON files'.toJS,
          'accept': acceptMap.jsify(),
        }.jsify(),
      ];
      options['types'] = types.toJS;
    }

    // Call window.showSaveFilePicker(options)
    final showSaveFilePicker =
        _getJSProperty(web.window, 'showSaveFilePicker')! as JSFunction;
    final promise = showSaveFilePicker.callAsFunction(
        web.window, options.jsify())! as JSPromise;

    final handle = (await promise.toDart)! as JSObject;

    // Create a writable stream and write the bytes
    final writablePromise =
        handle.callMethod('createWritable'.toJS)! as JSPromise;
    final writable = (await writablePromise.toDart)! as JSObject;

    final jsBytes = bytes.toJS;
    final writePromise =
        writable.callMethod('write'.toJS, jsBytes)! as JSPromise;
    await writePromise.toDart;

    final closePromise = writable.callMethod('close'.toJS)! as JSPromise;
    await closePromise.toDart;

    return true;
  } on Object catch (_) {
    // User cancelled or error occurred
    return false;
  }
}
