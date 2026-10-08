// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// external_library_web.dart
// Web platform implementation - WASM initialization and utilities
//
// 2026 January 03
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

// 2026 January 03
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

// ignore_for_file: invalid_runtime_check_with_js_interop_types

import 'dart:async';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated_web.dart';

/// On web, returns an ExternalLibrary to indicate WASM is already loaded via wasm_bindgen().
/// This prevents flutter_rust_bridge from trying to load the WASM again.
ExternalLibrary? createPreloadedExternalLibrary() {
  return const ExternalLibrary(debugInfo: 'wasm-preloaded-via-wasm_bindgen');
}

/// Wait for WASM to be initialized (wasm_bindgen available via JS interop).
Future<void> waitForWasmInit({
  Duration timeout = const Duration(seconds: 10),
}) async {
  final completer = Completer<void>();
  final end = DateTime.now().add(timeout);

  void check() {
    try {
      if (_hasWasmBindgen()) {
        completer.complete();
        return;
      }
    } catch (_) {}
    if (DateTime.now().isAfter(end)) {
      completer.completeError(StateError('wasm_bindgen not available'));
    } else {
      Future.delayed(const Duration(milliseconds: 100), check);
    }
  }

  check();
  return completer.future;
}

/// Load the WASM JS library (wellen_bridge.js) into the document.
Future<void> loadWasmScript(String scriptUrl) async {
  _injectWasmScript(scriptUrl);
  // Wait for wasm_bindgen to become available
  await waitForWasmInit();
}

/// Fetch binary data from a URL using the Fetch API.
Future<Uint8List> fetchBytes(String url) async {
  final completer = Completer<Uint8List>();

  void handleFetchResult(JSUint8Array data) {
    completer.complete(data.toDart);
  }

  _fetchBytesImpl(url, handleFetchResult.toJS);
  return completer.future;
}

// JS interop - simple types only for WASM compatibility
@JS()
external bool _hasWasmBindgen();

@JS()
external void _injectWasmScript(String scriptUrl);

@JS()
external void _fetchBytesImpl(String url, JSFunction callback);
