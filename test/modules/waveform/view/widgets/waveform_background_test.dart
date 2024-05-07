// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// waveform_background_test.dart
// Tests for the waveform background widget.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter_test/flutter_test.dart';
import 'package:module_structure_api/module_structure_api.dart';
import 'package:module_structure_repository/module_structure_repository.dart';
import 'package:rohd_wave_viewer/mock_module_structure_api.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rohd_wave_viewer/src/modules/rohd_module/bloc/rohd_module_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/shared/widgets/signal_tab_container.dart';
import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/bloc/waveform_module_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/view/widgets/waveform_background.dart';

import '../../../../helpers.dart';

void main() {
  late RohdModuleBloc rohdModuleBloc;
  late WaveformModuleBloc waveformModuleBloc;
  late SignalBloc signalBloc;

  late ModuleStructure mockModuleStructure;
  late Module selectedModule;
  late ModuleStructureApi moduleStructureApi;
  late ModuleStructureRepository moduleStructureRepository;
  late List<Signal> signals;
  late List<Signal> monitoredSignals;

  setUp(() async {
    rohdModuleBloc = MockRohdModuleBloc();
    signalBloc = MockSignalBloc();
    moduleStructureApi = MockModuleStructureApi();
    moduleStructureRepository =
        ModuleStructureRepository(moduleStructureApi: moduleStructureApi);
    mockModuleStructure = await moduleStructureRepository.getModuleStructure();
    selectedModule = mockModuleStructure.modules.first;
    signals = selectedModule.signals;
    monitoredSignals = [signals[0], signals[1], signals[2]];
    waveformModuleBloc = WaveformModuleBloc(
        moduleStructureRepository: moduleStructureRepository);
  });

  group('Waveform Background', () {
    testWidgets(
        'Waveform Background expect to see SignalTabContainer when there are monitored signals.',
        (tester) async {
      when(() => rohdModuleBloc.state).thenReturn(
        Rendered(mockModuleStructure),
      );

      when(() => signalBloc.state).thenReturn(
        SignalLoaded(signals, monitoredSignals),
      );

      await tester.pumpApp(
        rohdModuleBloc: rohdModuleBloc,
        signalBloc: signalBloc,
        waveformModuleBloc: waveformModuleBloc,
        child: const WaveformBackground(timescale: 20),
      );

      expect(find.byType(SignalTabContainer),
          findsAtLeastNWidgets(monitoredSignals.length + 1));
    });
  });
}
