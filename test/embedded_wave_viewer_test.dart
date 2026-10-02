// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// embedded_wave_viewer_test.dart
// Stable embedded viewer lifecycle tests.
//
// 2026 September 29
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_wave_viewer/rohd_wave_viewer.dart';
import 'package:rohd_wave_viewer/src/ui/wave_viewer_app.dart';
import 'package:rohd_wave_viewer/testing.dart';

void main() {
  void useDesktopViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  testWidgets('shows an explicit empty state without a waveform API', (
    tester,
  ) async {
    useDesktopViewport(tester);
    await tester.pumpWidget(
      const EmbeddedWaveViewer(waveformApi: null),
    );

    expect(find.text('No waveform data available'), findsOneWidget);
  });

  testWidgets('creates the viewer when an API becomes available', (
    tester,
  ) async {
    useDesktopViewport(tester);
    await tester.pumpWidget(
      const MaterialApp(
        home: EmbeddedWaveViewer(waveformApi: null),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: EmbeddedWaveViewer(
          waveformApi: MockSignalWaveformApi(),
          isExtensionMode: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('No waveform data available'), findsNothing);
    expect(find.byType(EmbeddedWaveViewer), findsOneWidget);
  });

  testWidgets('recreates internal state when the waveform API changes', (
    tester,
  ) async {
    useDesktopViewport(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: EmbeddedWaveViewer(
          waveformApi: MockSignalWaveformApi(),
          isExtensionMode: true,
        ),
      ),
    );
    await tester.pump();
    final firstKey = tester.widget<App>(find.byType(App)).key;

    await tester.pumpWidget(
      MaterialApp(
        home: EmbeddedWaveViewer(
          waveformApi: MockSignalWaveformApi(),
          isExtensionMode: true,
        ),
      ),
    );
    await tester.pump();
    final secondKey = tester.widget<App>(find.byType(App)).key;

    expect(secondKey, isNot(firstKey));
  });
}
