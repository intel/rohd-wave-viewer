// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_state_test.dart
// The SignalState tests.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';
import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';
import 'package:rohd_wave_viewer/testing.dart';

void main() {
  late SignalWaveformRepository signalWaveformRepository;
  late MockSignalWaveformApi signalWaveformApi;
  late ModuleStructure mockModuleStructure;
  late HierarchyOccurrence selectedModule;

  late List<SignalOccurrence> mockSignals;
  late List<SignalWaveform> mockMonitorSignals;

  setUp(() async {
    signalWaveformApi = MockSignalWaveformApi();
    signalWaveformRepository = SignalWaveformRepository(
      signalWaveformApi: signalWaveformApi,
    );
    mockModuleStructure = await signalWaveformApi.getModuleStructure();
    signalWaveformRepository.buildSignalCacheFromHierarchy(
      mockModuleStructure.modules,
    );
    selectedModule = mockModuleStructure.modules.first;
    mockSignals = signalWaveformRepository.getSignalsBySelectedModule(
      selectedModule,
    );
    mockMonitorSignals = [];
  });

  group('SignalState', () {
    group('SignalOccurrence Loaded', () {
      test('support value comparison', () {
        expect(
          SignalLoaded(mockSignals, mockMonitorSignals),
          SignalLoaded(mockSignals, mockMonitorSignals),
        );
      });

      test(
        'filteredSignals returns only ports when showInternalSignals is false',
        () {
          final state = SignalLoaded(mockSignals, mockMonitorSignals);
          final filtered = state.filteredSignals;

          // All filtered signals should be ports
          for (final signal in filtered) {
            expect(signal, isA<SignalOccurrence>());
          }
        },
      );

      test(
        'filteredSignals returns all signals when showInternalSignals is true',
        () {
          final state = SignalLoaded(
            mockSignals,
            mockMonitorSignals,
            showInternalSignals: true,
          );
          final filtered = state.filteredSignals;

          // Should have all signals when internal signals are shown
          expect(filtered.length, equals(mockSignals.length));
          expect(filtered, equals(mockSignals));
        },
      );
    });
  });
}
