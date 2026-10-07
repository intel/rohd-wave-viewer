// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_module_event_test.dart
// Tests for the ROHD module BLoC events.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_wave_viewer/src/modules/rohd_module/bloc/rohd_module_bloc.dart';
import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';
import 'package:rohd_wave_viewer/testing.dart';

void main() {
  late SignalWaveformRepository signalWaveformRepository;
  late MockSignalWaveformApi signalWaveformApi;
  late ModuleStructure mockModuleStructure;
  late HierarchyOccurrence selectedModule;

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
  });
  group('RohdModuleEvent', () {
    group('RohdModuleInit', () {
      test('supports value comparison', () {
        expect(const RohdModuleInit(), const RohdModuleInit());
      });
    });
    group('RohdModuleSelected', () {
      test('supports value comparison', () {
        expect(
          RohdModuleSelect(mockModuleStructure, selectedModule),
          RohdModuleSelect(mockModuleStructure, selectedModule),
        );
      });
    });
  });
}
