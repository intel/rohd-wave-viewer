// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// wave_viewer_theme_cubit_test.dart
// Tests for WaveViewerThemeCubit.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_wave_viewer/src/cubit/wave_viewer_theme_cubit.dart';

void main() {
  group('WaveViewerThemeCubit', () {
    test('initial state is dark', () async {
      final cubit = WaveViewerThemeCubit();
      expect(cubit.state, WaveViewerThemeMode.dark);
      await cubit.close();
    });

    test('initial state can be overridden', () async {
      final cubit = WaveViewerThemeCubit(WaveViewerThemeMode.light);
      expect(cubit.state, WaveViewerThemeMode.light);
      await cubit.close();
    });

    blocTest<WaveViewerThemeCubit, WaveViewerThemeMode>(
      'toggleTheme switches dark to light',
      build: WaveViewerThemeCubit.new,
      act: (cubit) => cubit.toggleTheme(),
      expect: () => [WaveViewerThemeMode.light],
    );

    blocTest<WaveViewerThemeCubit, WaveViewerThemeMode>(
      'toggleTheme switches light back to dark',
      build: WaveViewerThemeCubit.new,
      act: (cubit) {
        cubit
          ..toggleTheme() // dark -> light
          ..toggleTheme(); // light -> dark
      },
      expect: () => [WaveViewerThemeMode.light, WaveViewerThemeMode.dark],
    );

    blocTest<WaveViewerThemeCubit, WaveViewerThemeMode>(
      'setTheme to different mode emits it',
      build: WaveViewerThemeCubit.new,
      act: (cubit) => cubit.setTheme(WaveViewerThemeMode.light),
      expect: () => [WaveViewerThemeMode.light],
    );
  });
}
