// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// main_io_test.dart
// Native startup behavior tests.
//
// 2026 October 2
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

@TestOn('vm')
library;

import 'package:dart_wellen/dart_wellen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_wave_viewer/embedded_wave_viewer.dart';
import 'package:rohd_wave_viewer/main_io.dart';

void main() {
  testWidgets('native startup without a file exposes the file picker', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final api = await initializeSignalWaveformApi(
      const [],
      environment: const {},
    );
    expect(api, isA<WellenSignalWaveformApi>());
    expect(api.isLoaded, isFalse);

    await tester.pumpWidget(EmbeddedWaveViewer(waveformApi: api));
    await tester.pumpAndSettle();

    expect(find.text('No waveform data available'), findsNothing);
    expect(find.byTooltip('Load waveform file'), findsOneWidget);
  });
}
