// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_state_test.dart
// The SignalState tests.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter_test/flutter_test.dart';
import 'package:module_structure_api/module_structure_api.dart';
import 'package:module_structure_repository/module_structure_repository.dart';
import 'package:rohd_wave_viewer/mock_module_structure_api.dart';

import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';

void main() {
  late ModuleStructureRepository moduleStructureRepository;
  late ModuleStructureApi moduleStructureApi;
  late ModuleStructure mockModuleStructure;
  late Module selectedModule;

  late List<Signal> mockSignals;
  late List<Signal> mockMonitorSignals;

  setUp(() async {
    moduleStructureApi = MockModuleStructureApi();
    moduleStructureRepository =
        ModuleStructureRepository(moduleStructureApi: moduleStructureApi);
    mockModuleStructure = await moduleStructureRepository.getModuleStructure();
    selectedModule = mockModuleStructure.modules.first;
    mockSignals = selectedModule.signals;
    mockMonitorSignals = [];
  });

  group('SignalState', () {
    group('Signal Loaded', () {
      test('support value comparison', () {
        expect(
          SignalLoaded(mockSignals, mockMonitorSignals),
          SignalLoaded(mockSignals, mockMonitorSignals),
        );
      });
    });
  });
}
