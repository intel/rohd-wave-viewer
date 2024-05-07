// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_event_test.dart
// Tests for the signal events.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter_test/flutter_test.dart';
import 'package:module_structure_api/module_structure_api.dart';
import 'package:module_structure_repository/module_structure_repository.dart';
import 'package:rohd_wave_viewer/mock_module_structure_api.dart';

import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';

class FakeItems extends Fake implements Module {}

void main() {
  late ModuleStructureRepository moduleStructureRepository;
  late ModuleStructureApi moduleStructureApi;
  late ModuleStructure mockModuleStructure;
  late Module mockSelectedModule;
  late Signal mockSelectedSignal;

  setUp(() async {
    moduleStructureApi = MockModuleStructureApi();
    moduleStructureRepository =
        ModuleStructureRepository(moduleStructureApi: moduleStructureApi);
    mockModuleStructure = await moduleStructureRepository.getModuleStructure();
    mockSelectedModule = mockModuleStructure.modules.first;
    mockSelectedSignal = mockModuleStructure.modules.first.signals.first;
  });
  group('SignalEvent', () {
    group('SignalUpdate', () {
      test('supports value comparison', () {
        expect(SignalUpdateEvent(mockSelectedModule),
            SignalUpdateEvent(mockSelectedModule));
      });
    });
    group('SignalSelected', () {
      test('supports value comparison', () {
        expect(SignalSelectedEvent(mockSelectedSignal),
            SignalSelectedEvent(mockSelectedSignal));
      });
    });
  });
}
