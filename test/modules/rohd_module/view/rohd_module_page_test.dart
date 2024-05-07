// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_module_page_test.dart
// Tests for the ROHD module page.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter_test/flutter_test.dart';
import 'package:module_structure_api/module_structure_api.dart';
import 'package:module_structure_repository/module_structure_repository.dart';
import 'package:rohd_wave_viewer/mock_module_structure_api.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rohd_wave_viewer/src/modules/home/view/home.dart';
import 'package:rohd_wave_viewer/src/modules/rohd_module/bloc/rohd_module_bloc.dart'
    as rohd_module_bloc;
import 'package:rohd_wave_viewer/src/modules/rohd_module/rohd_module.dart';
import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/bloc/waveform_module_bloc.dart';

import '../../../helpers.dart';

void main() {
  late rohd_module_bloc.RohdModuleBloc rohdModuleBloc;
  late WaveformModuleBloc waveformModuleBloc;
  late SignalBloc signalBloc;

  late ModuleStructure mockModuleStructure;
  late ModuleStructureApi moduleStructureApi;
  late ModuleStructureRepository moduleStructureRepository;

  setUp(() async {
    rohdModuleBloc = MockRohdModuleBloc();
    signalBloc = MockSignalBloc();
    moduleStructureApi = MockModuleStructureApi();
    moduleStructureRepository =
        ModuleStructureRepository(moduleStructureApi: moduleStructureApi);
    mockModuleStructure = await moduleStructureRepository.getModuleStructure();
    waveformModuleBloc = WaveformModuleBloc(
        moduleStructureRepository: moduleStructureRepository);
  });

  group('RohdModule Panel', () {
    testWidgets(
        skip: true, //TODO: enable this test!
        'renders Module Tree Structure correctly when rohdModuleBloc '
        'Rendered.', (tester) async {
      when(() => rohdModuleBloc.state).thenReturn(
        rohd_module_bloc.Rendered(mockModuleStructure),
      );

      when(() => signalBloc.state).thenReturn(
        SignalLoading(),
      );

      await tester.pumpApp(
        rohdModuleBloc: rohdModuleBloc,
        signalBloc: signalBloc,
        waveformModuleBloc: waveformModuleBloc,
        child: const WaveFormViewerPage(),
      );

      expect(find.byType(ModuleSignalPanel), findsOneWidget);
      expect(find.byType(RohdModulePanel), findsOneWidget);
      expect(find.byType(ModuleTree), findsOneWidget);
    });
  });
}
