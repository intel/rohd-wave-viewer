// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_module_bloc_test.dart
// The test file for the ROHD module BLoC.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_wave_viewer/src/modules/rohd_module/bloc/rohd_module_bloc.dart';
import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';
import 'package:rohd_wave_viewer/testing.dart';

void main() {
  group('Rohd module Bloc', () {
    late SignalWaveformRepository signalWaveformRepository;
    late MockSignalWaveformApi signalWaveformApi;
    late ModuleStructure mockModuleStructure;
    late HierarchyOccurrence selectedModule;
    late HierarchyService hierarchyService;

    setUp(() async {
      signalWaveformApi = MockSignalWaveformApi();
      signalWaveformRepository = SignalWaveformRepository(
        signalWaveformApi: signalWaveformApi,
      );
      // Hierarchy comes from rohd_hierarchy, not the repository.
      mockModuleStructure = await signalWaveformApi.getModuleStructure();
      signalWaveformRepository.buildSignalCacheFromHierarchy(
        mockModuleStructure.modules,
      );
      selectedModule = mockModuleStructure.modules.first;
      hierarchyService = BaseHierarchyAdapter.fromTree(
        mockModuleStructure.modules.first,
      );
    });

    blocTest<RohdModuleBloc, RohdModuleState>(
      'emit [Loading] when onRohdModuleInit is called.',
      build: () =>
          RohdModuleBloc(signalWaveformRepository: signalWaveformRepository),
      act: (bloc) {
        bloc
          ..add(const RohdModuleInit())
          ..add(RohdModuleSetExternalHierarchy(hierarchyService));
      },
      expect: () => <Matcher>[
        isA<Loading>(),
        isA<Rendered>(),
        isA<ModuleSelected>(), // Auto-selected top module
      ],
    );

    blocTest<RohdModuleBloc, RohdModuleState>(
      'emit [ModuleSelected] when click on a module.',
      build: () =>
          RohdModuleBloc(signalWaveformRepository: signalWaveformRepository),
      act: (bloc) async {
        // Trigger init and provide hierarchy
        bloc
          ..add(const RohdModuleInit())
          ..add(RohdModuleSetExternalHierarchy(hierarchyService));
        // Wait for auto-selection to complete
        await bloc.stream.firstWhere((s) => s is ModuleSelected);
        // Select a different module (sub-module) to trigger a distinct state
        final subModule = selectedModule.children.first;
        bloc.add(RohdModuleSelect(mockModuleStructure, subModule));
      },
      expect: () => <Matcher>[
        isA<Loading>(),
        isA<Rendered>(),
        isA<ModuleSelected>(), // Auto-selected top module from init
        isA<ModuleSelected>(), // Explicitly selected sub-module
      ],
    );
  });
}
