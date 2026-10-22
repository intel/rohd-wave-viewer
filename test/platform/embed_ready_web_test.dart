// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// embed_ready_web_test.dart
// Browser regression tests for web host readiness metadata.
//
// 2026 October
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_wave_viewer/src/platform/platform_web.dart' as platform;
import 'package:web/web.dart' as web;

void main() {
  test('delivers WASM readiness metadata to the host callback', () {
    final window = web.window as JSObject;
    final original = window.getProperty('__rohdEmbedReady'.toJS);
    addTearDown(() => window.setProperty('__rohdEmbedReady'.toJS, original));
    Object? received;
    window.setProperty(
      '__rohdEmbedReady'.toJS,
      ((JSAny? info) {
        received = info.dartify();
      }).toJS,
    );

    platform.signalEmbedReady({'platform': 'web', 'wasm': true});

    expect(received, {
      'platform': 'web',
      'wasm': true,
      'reloaded_in_gui': true,
    });
  });
}
