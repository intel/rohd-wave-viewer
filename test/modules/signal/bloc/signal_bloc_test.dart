// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_bloc_test.dart
// The test file for the signal BLoC.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';
import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';
import 'package:rohd_wave_viewer/testing.dart';

void main() {
  group('Rohd module Bloc', () {
    late SignalBloc signalBloc;
    late SignalWaveformRepository signalWaveformRepository;
    late MockSignalWaveformApi signalWaveformApi;
    late ModuleStructure mockModuleStructure;
    late HierarchyOccurrence mockSelectedModule;
    late List<SignalOccurrence> mockSignals;

    setUp(() async {
      signalWaveformApi = MockSignalWaveformApi();
      signalWaveformRepository = SignalWaveformRepository(
        signalWaveformApi: signalWaveformApi,
      );
      mockModuleStructure = await signalWaveformApi.getModuleStructure();
      signalWaveformRepository.buildSignalCacheFromHierarchy(
        mockModuleStructure.modules,
      );
      signalBloc = SignalBloc(signalWaveformRepository);
      mockSelectedModule = mockModuleStructure.modules.first;
      mockSignals = signalWaveformRepository.getSignalsBySelectedModule(
        mockSelectedModule,
      );
    });

    blocTest<SignalBloc, SignalState>(
      'emit [SignalLoaded] with updated signal '
      'when SignalUpdateEvent is called.',
      build: () => signalBloc,
      act: (bloc) => bloc.add(SignalUpdateEvent(mockSelectedModule)),
      expect: () => <SignalState>[
        SignalLoaded(
          mockSignals,
          const [],
          selectedModulePath: mockSelectedModule.path(),
        ),
      ],
    );

    blocTest<SignalBloc, SignalState>(
      'emit [SignalLoaded] with updated monitorList'
      ' when addSignalToMonitor is called.',
      build: () => signalBloc,
      act: (bloc) => bloc..add(SignalSelectedEvent(mockSignals[1])),
      verify: (bloc) {
        // Verify that the monitor list has one waveform with correct signal ID
        expect(bloc.state.monitorSignalsList.length, 1);
        expect(
          bloc.state.monitorSignalsList.first.signalId,
          mockSignals[1].path(),
        );
      },
    );

    blocTest<SignalBloc, SignalState>(
      'emit [SignalLoaded] with showInternalSignals=true'
      ' when SignalToggleInternalSignalsEvent is called with enable=true.',
      build: () => signalBloc,
      act: (bloc) => bloc.add(SignalToggleInternalSignalsEvent(enable: true)),
      verify: (bloc) {
        expect(bloc.state.showInternalSignals, isTrue);
      },
    );

    blocTest<SignalBloc, SignalState>(
      'emit [SignalLoaded] with showInternalSignals=false'
      ' when SignalToggleInternalSignalsEvent is called with enable=false.',
      build: () => signalBloc,
      act: (bloc) => bloc
        ..add(SignalToggleInternalSignalsEvent(enable: true))
        ..add(SignalToggleInternalSignalsEvent(enable: false)),
      verify: (bloc) {
        expect(bloc.state.showInternalSignals, isFalse);
      },
    );

    test('initialShowInternalSignals seeds the initial state', () async {
      final bloc = SignalBloc(
        signalWaveformRepository,
        initialShowInternalSignals: true,
      );

      expect(bloc.state.showInternalSignals, isTrue);
      await bloc.close();
    });
  });
}
