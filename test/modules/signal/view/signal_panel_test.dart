// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_panel_test.dart
// Tests for the SignalOccurrence Panel.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_wave_viewer/src/modules/rohd_module/bloc/rohd_module_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/signal/view/signal_panel.dart';
import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';
import 'package:rohd_wave_viewer/testing.dart';

import '../../../helpers.dart';

void main() {
  late RohdModuleBloc rohdModuleBloc;
  late SignalBloc signalBloc;

  late ModuleStructure mockModuleStructure;
  late HierarchyOccurrence selectedModule;
  late MockSignalWaveformApi signalWaveformApi;
  late SignalWaveformRepository signalWaveformRepository;
  late List<SignalOccurrence> signals;

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
    selectedModule = mockModuleStructure.modules.first;
    signals = signalWaveformRepository.getSignalsBySelectedModule(
      selectedModule,
    );
  });

  group('SignalOccurrence Panel', () {
    testWidgets('Module Signals show signals when there are selected Module.', (
      tester,
    ) async {
      when(
        () => rohdModuleBloc.state,
      ).thenReturn(Rendered(mockModuleStructure));

      when(() => signalBloc.state).thenReturn(SignalLoaded(signals, const []));

      await tester.pumpApp(
        rohdModuleBloc: rohdModuleBloc,
        signalBloc: signalBloc,
        child: const SignalPanel(),
      );

      expect(find.byType(SignalList), findsOneWidget);
      expect(find.text(signals.first.name), findsOneWidget);
    });

    testWidgets('Shows all signals when internal signals enabled', (
      tester,
    ) async {
      when(
        () => rohdModuleBloc.state,
      ).thenReturn(Rendered(mockModuleStructure));

      when(
        () => signalBloc.state,
      ).thenReturn(SignalLoaded(signals, const [], showInternalSignals: true));

      await tester.pumpApp(
        rohdModuleBloc: rohdModuleBloc,
        signalBloc: signalBloc,
        child: const SignalPanel(),
      );

      expect(find.byType(SignalList), findsOneWidget);
    });

    testWidgets('selects an available signal when its row is tapped', (
      tester,
    ) async {
      final signal = signals.first;
      await tester.pumpApp(
        signalBloc: signalBloc,
        child: SignalList(signals: [signal]),
      );

      await tester.tap(find.text(signal.name));

      verify(() => signalBloc.add(SignalSelectedEvent(signal))).called(1);
    });

    testWidgets('expands struct fields and selects a derived field', (
      tester,
    ) async {
      final structSignal = SignalOccurrence(
        name: 'sample',
        width: 8,
        logicType: {
          'typeName': 'Sample',
          'fields': [
            {
              'name': 'upper',
              'width': 4,
              'bits': [7, 6, 5, 4],
            },
            {
              'name': 'lower',
              'width': 4,
              'bits': [3, 2, 1, 0],
            },
          ],
        },
      );
      await tester.pumpApp(
        signalBloc: signalBloc,
        child: SignalList(signals: [structSignal]),
      );

      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pump();
      expect(find.textContaining('upper'), findsOneWidget);
      expect(find.textContaining('lower'), findsOneWidget);

      await tester.tap(find.textContaining('upper'));

      verify(
        () => signalBloc.add(
          SignalSubFieldSelectedEvent(
            parentSignal: structSignal,
            fieldLabel: 'upper',
            startBit: 4,
            width: 4,
          ),
        ),
      ).called(1);
    });

    testWidgets('expands a selected range of a large array', (tester) async {
      final arraySignal = SignalOccurrence(
        name: 'samples',
        width: 160,
        logicType: {
          'width': 160,
          'arrayDims': [10],
          'elementWidth': 16,
        },
      );
      await tester.pumpApp(
        signalBloc: signalBloc,
        child: SignalList(signals: [arraySignal]),
      );

      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      expect(find.text('samples  [10 elements]'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '3:1');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.textContaining('[1]'), findsOneWidget);
      expect(find.textContaining('[2]'), findsOneWidget);
      expect(find.textContaining('[3]'), findsOneWidget);
      expect(find.textContaining('[0]'), findsNothing);
      expect(find.textContaining('[4]'), findsNothing);
    });
  });
}
