// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_module_state_test.dart
// Tests for the ROHD module BLoC state.
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

  group('RohdModuleState', () {
    group('ModuleSelected', () {
      test('support value comparison', () {
        expect(
          ModuleSelected(mockModuleStructure, selectedModule),
          ModuleSelected(mockModuleStructure, selectedModule),
        );
      });
    });
  });
}
