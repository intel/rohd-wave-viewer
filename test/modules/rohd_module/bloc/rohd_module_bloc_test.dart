// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_module_bloc_test.dart
// The test file for the ROHD module BLoC.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:module_structure_repository/module_structure_repository.dart';
import 'package:module_structure_api/module_structure_api.dart';
import 'package:rohd_wave_viewer/mock_module_structure_api.dart';
import 'package:rohd_wave_viewer/src/modules/rohd_module/bloc/rohd_module_bloc.dart';

void main() {
  group('Rohd module Bloc', () {
    late RohdModuleBloc rohdModuleBloc;
    late ModuleStructureRepository moduleStructureRepository;
    late ModuleStructureApi moduleStructureApi;
    late ModuleStructure mockModuleStructure;
    late Module selectedModule;

    setUp(() async {
      moduleStructureApi = MockModuleStructureApi();
      moduleStructureRepository =
          ModuleStructureRepository(moduleStructureApi: moduleStructureApi);
      rohdModuleBloc =
          RohdModuleBloc(moduleStructureRepository: moduleStructureRepository);
      mockModuleStructure =
          await moduleStructureRepository.getModuleStructure();
      selectedModule = mockModuleStructure.modules.first;
    });

    blocTest(
      'emit [Loading] when onRohdModuleInit is called.',
      build: () => rohdModuleBloc,
      act: (bloc) => bloc.add(RohdModuleInit()),
      expect: () => <RohdModuleState>[
        Loading(mockModuleStructure),
        Rendered(mockModuleStructure)
      ],
    );

    blocTest<RohdModuleBloc, RohdModuleState>(
      'emit [ModuleSelected] when click on a module.',
      build: () => rohdModuleBloc,
      act: (bloc) => bloc.add(
        RohdModuleSelect(mockModuleStructure, selectedModule),
      ),
      expect: () => <RohdModuleState>[
        ModuleSelected(mockModuleStructure, selectedModule)
      ],
    );
  });
}
