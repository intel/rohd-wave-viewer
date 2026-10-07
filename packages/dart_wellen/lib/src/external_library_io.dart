// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// external_library_io.dart
// Native platform implementation - stubs for web-only functions
//
// 2026 January 03
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

// 2026 January 03
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

/// On native platforms, locate libwellen_bridge.so relative to the project root.
///
/// The codegen config (`flutter_rust_bridge.yaml`) uses paths relative to the
/// `packages/dart_wellen/` directory, but the runtime loader resolves
/// `ioDirectory` from `Directory.current`.  When tests or `flutter run`
/// execute from the `rohd-wave-viewer/` project root the default
/// `../../rust/…` path resolves two levels too high. The embedded DevTools
/// app instead runs from its parent directory, with the viewer below
/// `rohd-wave-viewer/`.
///
/// Returns an [ExternalLibrary] when the native lib is found at a known
/// relative location, or `null` to fall back to the default loader.
ExternalLibrary? createPreloadedExternalLibrary() {
  const lib = 'libwellen_bridge.so';
  final candidates = [
    // Standalone rohd-wave-viewer project root.
    File('rust/wellen_bridge/target/release/$lib'),
    // rohd_devtools_extension project root with an embedded wave viewer.
    File('rohd-wave-viewer/rust/wellen_bridge/target/release/$lib'),
  ];
  for (final candidate in candidates) {
    if (candidate.existsSync()) {
      return ExternalLibrary.open(candidate.absolute.path);
    }
  }
  return null;
}

/// Stub - only available on web platform.
Future<void> waitForWasmInit({
  Duration timeout = const Duration(seconds: 10),
}) async {
  throw UnsupportedError('waitForWasmInit is only available on web');
}

/// Stub - only available on web platform.
Future<void> loadWasmScript(String scriptUrl) async {
  throw UnsupportedError('loadWasmScript is only available on web');
}

/// Stub - only available on web platform.
Future<Uint8List> fetchBytes(String url) async {
  throw UnsupportedError('fetchBytes is only available on web');
}
