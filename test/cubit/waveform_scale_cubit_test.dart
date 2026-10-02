// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// waveform_scale_cubit_test.dart
// Tests for WaveformScaleCubit.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_wave_viewer/src/const/layout.dart';
import 'package:rohd_wave_viewer/src/cubit/waveform_scale_cubit.dart';

void main() {
  group('WaveformScaleCubit', () {
    late WaveformScaleCubit cubit;

    setUp(() {
      cubit = WaveformScaleCubit();
    });

    tearDown(() async {
      await cubit.close();
    });

    test('initial state is 1.0', () {
      expect(cubit.state, 1.0);
    });

    test('custom initial scale', () async {
      final c = WaveformScaleCubit(2);
      expect(c.state, 2.0);
      await c.close();
    });

    test('scaledRowHeight reflects current scale', () {
      expect(cubit.scaledRowHeight, baseSignalRowHeight * 1.0);
    });

    blocTest<WaveformScaleCubit, double>(
      'scaleUp increases state by 0.1',
      build: WaveformScaleCubit.new,
      act: (c) => c.scaleUp(),
      expect: () => [1.1],
    );

    blocTest<WaveformScaleCubit, double>(
      'scaleDown decreases state by 0.1',
      build: WaveformScaleCubit.new,
      act: (c) => c.scaleDown(),
      expect: () => [0.9],
    );

    blocTest<WaveformScaleCubit, double>(
      'scaleUp clamps at maxScale (3.0)',
      build: () => WaveformScaleCubit(3),
      act: (c) => c.scaleUp(),
      expect: () => <double>[], // no emission — already at max
    );

    blocTest<WaveformScaleCubit, double>(
      'scaleDown clamps at minScale (0.5)',
      build: () => WaveformScaleCubit(0.5),
      act: (c) => c.scaleDown(),
      expect: () => <double>[], // no emission — already at min
    );

    blocTest<WaveformScaleCubit, double>(
      'resetScale emits 1.0 when scale is not 1.0',
      build: () => WaveformScaleCubit(2),
      act: (c) => c.resetScale(),
      expect: () => [1.0],
    );

    blocTest<WaveformScaleCubit, double>(
      'resetScale does nothing when already 1.0',
      build: WaveformScaleCubit.new,
      act: (c) => c.resetScale(),
      expect: () => <double>[],
    );

    blocTest<WaveformScaleCubit, double>(
      'multiple scaleUp calls reach max',
      build: () => WaveformScaleCubit(2.8),
      act: (c) {
        c
          ..scaleUp() // 2.9
          ..scaleUp() // 3.0
          ..scaleUp(); // no-op
      },
      expect: () => [2.9, 3.0],
    );

    blocTest<WaveformScaleCubit, double>(
      'multiple scaleDown calls reach min',
      build: () => WaveformScaleCubit(0.7),
      act: (c) {
        c
          ..scaleDown() // 0.6
          ..scaleDown() // 0.5
          ..scaleDown(); // no-op
      },
      expect: () => [0.6, 0.5],
    );
  });
}
