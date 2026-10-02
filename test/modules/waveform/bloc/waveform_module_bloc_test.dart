// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// waveform_module_bloc_test.dart
// Tests for WaveformModuleBloc.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/bloc/waveform_module_bloc.dart';
import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';
import 'package:rohd_wave_viewer/testing.dart';

void main() {
  group('WaveformModuleBloc', () {
    late SignalWaveformRepository repo;
    late MockSignalWaveformApi api;

    setUp(() {
      api = MockSignalWaveformApi();
      repo = SignalWaveformRepository(signalWaveformApi: api);
    });

    test('initial state is InitialCursor with timePs=-1', () async {
      final bloc = WaveformModuleBloc(signalWaveformRepository: repo);
      expect(bloc.state, isA<InitialCursor>());
      expect(bloc.state.timePs, -1);
      await bloc.close();
    });

    blocTest<WaveformModuleBloc, WaveformModuleState>(
      'WaveformModuleOnTap emits UpdatedCursor with correct time',
      build: () => WaveformModuleBloc(signalWaveformRepository: repo),
      act: (bloc) => bloc.add(const WaveformModuleOnTap(42)),
      expect: () => [const UpdatedCursor(42)],
    );

    blocTest<WaveformModuleBloc, WaveformModuleState>(
      'WaveformModuleOnTap updates cursor to new time',
      build: () => WaveformModuleBloc(signalWaveformRepository: repo),
      act: (bloc) {
        bloc
          ..add(const WaveformModuleOnTap(100))
          ..add(const WaveformModuleOnTap(200));
      },
      expect: () => [const UpdatedCursor(100), const UpdatedCursor(200)],
    );

    blocTest<WaveformModuleBloc, WaveformModuleState>(
      'WaveformModuleReset returns to InitialCursor',
      build: () => WaveformModuleBloc(signalWaveformRepository: repo),
      act: (bloc) {
        bloc
          ..add(const WaveformModuleOnTap(100))
          ..add(const WaveformModuleReset());
      },
      expect: () => [const UpdatedCursor(100), const InitialCursor()],
    );

    // ──── Event equatable ────

    group('event equatable', () {
      test('WaveformModuleOnTap with same time are equal', () {
        expect(
          const WaveformModuleOnTap(10),
          equals(const WaveformModuleOnTap(10)),
        );
      });

      test('WaveformModuleOnTap with different time are not equal', () {
        expect(
          const WaveformModuleOnTap(10),
          isNot(equals(const WaveformModuleOnTap(20))),
        );
      });

      test('WaveformModuleReset instances are equal', () {
        expect(
          const WaveformModuleReset(),
          equals(const WaveformModuleReset()),
        );
      });
    });

    // ──── State equatable ────

    group('state equatable', () {
      test('InitialCursor instances are equal', () {
        expect(const InitialCursor(), equals(const InitialCursor()));
      });

      test('UpdatedCursor with same time are equal', () {
        expect(const UpdatedCursor(42), equals(const UpdatedCursor(42)));
      });

      test('UpdatedCursor with different time are not equal', () {
        expect(const UpdatedCursor(42), isNot(equals(const UpdatedCursor(99))));
      });

      test('WaveformModuleError state has timePs=0', () {
        expect(const WaveformModuleError().timePs, 0);
      });
    });
  });
}
