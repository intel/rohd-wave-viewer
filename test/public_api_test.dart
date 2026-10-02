// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// public_api_test.dart
// Compile-time coverage for supported package entry points.
//
// 2026 September 29
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_wave_viewer/rohd_wave_viewer.dart' as viewer;
import 'package:rohd_wave_viewer/testing.dart' as testing;

void main() {
  test('core entry point exposes the embedded widget contract', () {
    const embeddedViewer = viewer.EmbeddedWaveViewer(
      waveformApi: null,
    );
    const helpButton = viewer.WaveViewerHelpButton(isDark: true);

    expect(embeddedViewer.waveformApi, isNull);
    expect(embeddedViewer.themeMode, viewer.WaveViewerThemeMode.dark);
    expect(helpButton, isA<viewer.WaveViewerHelpButton>());
  });

  test('testing entry point exposes mock data support', () {
    expect(testing.MockSignalWaveformApi(), isNotNull);
  });
}
