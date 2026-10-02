// Copyright (C) 2025-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// waveform_painter_test.dart
// Tests binary waveform painting with representative clock data.
//
// 2026 March
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/view/widgets/painters/waveform_binary.dart';
import 'package:rohd_waveform/rohd_waveform.dart';

List<Data> _generateClock({
  int startTime = 0,
  int endTime = 10000,
  int period = 200,
}) {
  final data = <Data>[];
  for (var t = startTime; t <= endTime; t += period ~/ 2) {
    data.add(Data(time: t, value: ((t ~/ (period ~/ 2)) % 2).toString()));
  }
  return data;
}

void main() {
  test('draws alternating clock data across the visible range', () {
    final clockData = _generateClock();
    final painter = WaveformBinary(
      clockData,
      10000,
      0,
      timescale: 10000,
      textColor: Colors.white,
      labelBackgroundColor: Colors.black,
    );

    final recorder = PictureRecorder();
    painter.paint(Canvas(recorder), const Size(1000, 30));
    recorder.endRecording();

    expect(painter.waveform.length, 101);
    expect(painter.timescale, 10000);
  });

  test('clips transitions beyond a short visible range', () {
    final clockData = _generateClock();
    final painter = WaveformBinary(
      clockData,
      20,
      0,
      timescale: 20,
      textColor: Colors.white,
      labelBackgroundColor: Colors.black,
    );

    final recorder = PictureRecorder();
    painter.paint(Canvas(recorder), const Size(1000, 30));
    recorder.endRecording();

    expect(painter.waveform.length, 101);
    expect(painter.timescale, 20);
  });
}
