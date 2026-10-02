// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// waveform_file_open_icon_test.dart
// Tests the composite waveform file-open icon.
//
// 2026 October
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_wave_viewer/src/modules/shared/widgets/waveform_file_open_icon.dart';

void main() {
  testWidgets('combines file-open and waveform symbols', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: IconTheme(
            data: IconThemeData(size: 32, color: Colors.teal),
            child: WaveformFileOpenIcon(),
          ),
        ),
      ),
    );

    expect(find.byType(WaveformFileOpenIcon), findsOneWidget);
    expect(find.byIcon(Icons.file_open), findsOneWidget);
    expect(find.byIcon(Icons.ssid_chart), findsOneWidget);
    expect(
      tester.getSize(find.byType(WaveformFileOpenIcon)),
      const Size.square(32),
    );

    final fileIcon = tester.widget<Icon>(find.byIcon(Icons.file_open));
    final waveformIcon = tester.widget<Icon>(find.byIcon(Icons.ssid_chart));
    expect(fileIcon.size, closeTo(28.16, 0.001));
    expect(waveformIcon.size, 16);
    expect(fileIcon.color, Colors.teal);
    expect(waveformIcon.color, Colors.teal);
  });
}
