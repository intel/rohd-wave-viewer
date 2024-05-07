// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_module_event_test.dart
// Tests for the ROHD module BLoC events.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter_test/flutter_test.dart';
import 'package:module_structure_api/module_structure_api.dart';
import 'package:module_structure_repository/module_structure_repository.dart';
import 'package:rohd_wave_viewer/mock_module_structure_api.dart';

import 'package:rohd_wave_viewer/src/modules/rohd_module/bloc/rohd_module_bloc.dart';

class FakeItems extends Fake implements Module {}

void main() {
  late ModuleStructureRepository moduleStructureRepository;
  late ModuleStructureApi moduleStructureApi;
  late ModuleStructure mockModuleStructure;
  late Module selectedModule;

  setUp(() async {
    moduleStructureApi = MockModuleStructureApi();
    moduleStructureRepository =
        ModuleStructureRepository(moduleStructureApi: moduleStructureApi);
    mockModuleStructure = await moduleStructureRepository.getModuleStructure();
    selectedModule = mockModuleStructure.modules.first;
  });
  group('RohdModuleEvent', () {
    group('RohdModuleInit', () {
      test('supports value comparison', () {
        expect(RohdModuleInit(), RohdModuleInit());
      });
    });
    group('RohdModuleSelected', () {
      test('supports value comparison', () {
        expect(RohdModuleSelect(mockModuleStructure, selectedModule),
            RohdModuleSelect(mockModuleStructure, selectedModule));
      });
    });
  });
}
