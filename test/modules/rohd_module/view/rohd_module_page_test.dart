// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_module_page_test.dart
// Tests for the ROHD module page.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rohd_wave_viewer/src/modules/hierarchy/hierarchy.dart';
import 'package:rohd_wave_viewer/src/modules/rohd_module/bloc/rohd_module_bloc.dart'
    as rohd_module_bloc;
import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/bloc/waveform_module_bloc.dart';
import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';
import 'package:rohd_wave_viewer/testing.dart';

import '../../../helpers.dart';

void main() {
  late rohd_module_bloc.RohdModuleBloc rohdModuleBloc;
  late WaveformModuleBloc waveformModuleBloc;
  late SignalBloc signalBloc;

  late ModuleStructure mockModuleStructure;
  late MockSignalWaveformApi signalWaveformApi;
  late SignalWaveformRepository signalWaveformRepository;

  setUp(() async {
    rohdModuleBloc = MockRohdModuleBloc();
    signalBloc = MockSignalBloc();
    signalWaveformApi = MockSignalWaveformApi();
    signalWaveformRepository = SignalWaveformRepository(
      signalWaveformApi: signalWaveformApi,
    );
    mockModuleStructure = await signalWaveformApi.getModuleStructure();
    signalWaveformRepository.buildSignalCacheFromHierarchy(
      mockModuleStructure.modules,
    );
    waveformModuleBloc = WaveformModuleBloc(
      signalWaveformRepository: signalWaveformRepository,
    );
  });

  group('RohdModule Panel', () {
    testWidgets(
        'renders Module Tree Structure correctly when rohdModuleBloc '
        'Rendered.', (tester) async {
      when(
        () => rohdModuleBloc.state,
      ).thenReturn(rohd_module_bloc.Rendered(mockModuleStructure));

      when(
        () => rohdModuleBloc.repository,
      ).thenReturn(signalWaveformRepository);

      when(() => signalBloc.state).thenReturn(SignalLoading());

      await tester.pumpApp(
        rohdModuleBloc: rohdModuleBloc,
        signalBloc: signalBloc,
        waveformModuleBloc: waveformModuleBloc,
        child: HierarchyWidget(repository: signalWaveformRepository),
      );

      expect(find.byType(HierarchyWidget), findsOneWidget);
      expect(find.byType(ModuleTreePanel), findsOneWidget);
    });
  });
}
