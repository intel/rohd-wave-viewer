// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// selected_signal_panel_test.dart
// Tests for the selected signal panel.
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
import 'package:rohd_wave_viewer/src/modules/signal/view/selected_signal_panel.dart';

import '../../../helpers.dart';

void main() {
  late RohdModuleBloc rohdModuleBloc;
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
  });

  group('Selected Signal Panel', () {
    testWidgets(
        'Selected Signals show signals when there are send to be monitored.',
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
        child: const SelectedSignalsPanel(),
      );

      expect(find.byType(SignalTabContainer), findsAtLeastNWidgets(1));
    });
  });
}
