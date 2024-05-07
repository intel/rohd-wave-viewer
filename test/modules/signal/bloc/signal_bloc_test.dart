// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_bloc_test.dart
// The test file for the signal BLoC.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:module_structure_repository/module_structure_repository.dart';
import 'package:module_structure_api/module_structure_api.dart';
import 'package:rohd_wave_viewer/mock_module_structure_api.dart';
import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';

void main() {
  group('Rohd module Bloc', () {
    late SignalBloc signalBloc;
    late ModuleStructureRepository moduleStructureRepository;
    late ModuleStructureApi moduleStructureApi;
    late ModuleStructure mockModuleStructure;
    late Module mockSelectedModule;

    setUp(() async {
      moduleStructureApi = MockModuleStructureApi();
      moduleStructureRepository =
          ModuleStructureRepository(moduleStructureApi: moduleStructureApi);
      signalBloc = SignalBloc(moduleStructureRepository);
      mockModuleStructure =
          await moduleStructureRepository.getModuleStructure();
      mockSelectedModule = mockModuleStructure.modules.first;
    });

    blocTest<SignalBloc, SignalState>(
      'emit [SignalLoaded] with updated signal'
      'when SignalUpdateEvent is called.',
      build: () => signalBloc,
      act: (bloc) => bloc.add(SignalUpdateEvent(mockSelectedModule)),
      expect: () =>
          <SignalState>[SignalLoaded(mockSelectedModule.signals, const [])],
    );

    blocTest<SignalBloc, SignalState>(
      'emit [SignalLoaded] with updated monitorList'
      ' when addSignalToMonitor is called.',
      build: () => signalBloc,
      act: (bloc) => bloc
        ..add(
          SignalSelectedEvent(mockSelectedModule.signals[1]),
        ),
      expect: () => <SignalState>[
        SignalLoaded(
          const [],
          [mockSelectedModule.signals[1]],
        ),
      ],
    );
  });
}
