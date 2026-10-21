// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// js_interop_bridge_web_test.dart
// Browser regression tests for Schematic Viewer cross-probe messages.
//
// 2026 October
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:rohd_wave_viewer/src/platform/js_interop_bridge.dart' as bridge;
import 'package:test/test.dart';

void main() {
  test('decodes incoming cross-probe signals from the schematic host', () {
    final message = <String, Object?>{
      'type': 'incomingSignals',
      'sourceViewerId': 'rohd-schematic-viewer:4',
      'signalPaths': ['Top/sum', 'Top/clk'],
    };

    expect(bridge.dartify(message.jsify()), message);
  });

  test('decodes viewer registration and primitive values', () {
    final message = <String, Object?>{
      'type': 'signalViewerAvailability',
      'viewerId': 'rohd-wave-viewer:1',
      'canSendSignals': true,
    };

    expect(bridge.dartify(message.jsify()), message);
    expect(bridge.dartify(['Top/sum'].jsify()), ['Top/sum']);
    expect(bridge.dartify(true.toJS), isTrue);
    expect(bridge.dartify(null), isNull);
  });
}
