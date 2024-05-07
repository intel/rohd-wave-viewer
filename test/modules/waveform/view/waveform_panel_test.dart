// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// waveform_panel_test.dart
// Tests for the waveform panel.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:module_structure_api/module_structure_api.dart';
import 'package:module_structure_repository/module_structure_repository.dart';
import 'package:rohd_wave_viewer/mock_module_structure_api.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rohd_wave_viewer/src/modules/rohd_module/bloc/rohd_module_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/bloc/waveform_module_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/view/waveform_panel.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/view/widgets/waveform_background.dart';

import '../../../helpers.dart';

void main() {
  late RohdModuleBloc rohdModuleBloc;
  late WaveformModuleBloc waveformModuleBloc;
  late SignalBloc signalBloc;

  late ModuleStructure mockModuleStructure;
  late Module selectedModule;
  late ModuleStructureApi moduleStructureApi;
  late ModuleStructureRepository moduleStructureRepository;
  late List<Signal> signals;

  setUp(() async {
    rohdModuleBloc = MockRohdModuleBloc();
    signalBloc = MockSignalBloc();
    moduleStructureApi = MockModuleStructureApi();
    moduleStructureRepository =
        ModuleStructureRepository(moduleStructureApi: moduleStructureApi);
    mockModuleStructure = await moduleStructureRepository.getModuleStructure();
    selectedModule = mockModuleStructure.modules.first;
    signals = selectedModule.signals;
    waveformModuleBloc = WaveformModuleBloc(
        moduleStructureRepository: moduleStructureRepository);
  });

  group('Waveform Panel', () {
    testWidgets('Waveform Panel contains a container with waveform background.',
        (tester) async {
      when(() => rohdModuleBloc.state).thenReturn(
        Rendered(mockModuleStructure),
      );

      when(() => signalBloc.state).thenReturn(
        SignalLoaded(signals, const []),
      );

      await tester.pumpApp(
        rohdModuleBloc: rohdModuleBloc,
        signalBloc: signalBloc,
        waveformModuleBloc: waveformModuleBloc,
        child: const WaveformPanel(),
      );

      expect(find.byType(Container), findsAtLeastNWidgets(1));
      expect(find.byType(WaveformBackground), findsAtLeastNWidgets(1));
    });
  });
}
