// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// wave_viewer_help_button_test.dart
// Tests for the Wave Viewer help button and dialog.
//
// 2026 August
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_wave_viewer/src/modules/shared/widgets/wave_viewer_help_button.dart';

void main() {
  testWidgets('opens the help dialog after showing the hover tooltip',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WaveViewerHelpButton(
            isDark: true,
            isEmbedded: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final helpButton = find.byType(WaveViewerHelpButton);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(helpButton));
    await mouse.moveTo(tester.getCenter(helpButton));
    await tester.pump(const Duration(seconds: 1));

    expect(find.textContaining('Keybindings'), findsOneWidget);

    await tester.tap(helpButton);
    await tester.pumpAndSettle();

    expect(find.textContaining('ROHD Wave Viewer'), findsOneWidget);
    expect(find.text('Waveform Navigation'), findsWidgets);
  });
}
