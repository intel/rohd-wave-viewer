// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// filter_bank_workspace_flow_test.dart
// End-to-end widget tests for the FilterBank workspace workflow.
//
// 2026 August
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:io';

import 'package:dart_wellen/dart_wellen.dart' hide SignalWaveform;
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart';
import 'package:rohd_wave_viewer/src/modules/home/session/signal_list_persistence.dart';
import 'package:rohd_wave_viewer/src/modules/shared/widgets/widgets.dart';
import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/signal/view/selected_signal_panel.dart';
import 'package:rohd_wave_viewer/src/modules/signal/view/signal_value_panel.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/bloc/waveform_module_bloc.dart';
import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';

import '../helpers.dart';

void main() {
  tearDown(SignalValueFormatRegistry.clear);

  testWidgets(
    'restores, edits, and saves a filter-bank waveform workspace',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await WellenSignalWaveformApi.init();
      final api = WellenSignalWaveformApi();
      await api.loadFile('test/fixtures/filter_bank.vcd');
      final structure = await api.getModuleStructureOnly();
      final repository = SignalWaveformRepository(signalWaveformApi: api)
        ..buildSignalCacheFromHierarchy(structure.modules);
      final signalBloc = SignalBloc(repository);
      final waveformBloc = WaveformModuleBloc(
        signalWaveformRepository: repository,
      );
      addTearDown(signalBloc.close);
      addTearDown(waveformBloc.close);

      Future<void> waitForMonitorCount(int count) async {
        if (signalBloc.state.monitorSignalsList.length == count) {
          return;
        }
        await signalBloc.stream
            .firstWhere((state) => state.monitorSignalsList.length == count)
            .timeout(const Duration(seconds: 5));
      }

      final restorePlan = SignalListPersistence.decodeAndResolve(
        content:
            File('test/fixtures/filter_bank_workspace.json').readAsStringSync(),
        structure: structure,
      );
      final module = structure.modules.single;
      signalBloc
        ..add(SignalUpdateEvent(module))
        ..add(
          SignalRestoreMonitoredEvent(
            restorePlan.signalPaths,
            metadata: restorePlan.metadata,
            valueFormats: restorePlan.valueFormats,
            monitorGroups: restorePlan.monitorGroups,
          ),
        );
      await waitForMonitorCount(4);
      waveformBloc.add(
        WaveformModuleOnTap(restorePlan.session!.cursorTimePs!),
      );
      await waveformBloc.stream.firstWhere(
        (state) => state.timePs == restorePlan.session!.cursorTimePs,
      );

      await tester.pumpApp(
        signalBloc: signalBloc,
        waveformModuleBloc: waveformBloc,
        child: const SelectedSignalsPanel(),
      );
      await tester.pump();

      expect(find.byType(SignalTabContainer), findsNWidgets(4));
      expect(
        signalBloc.state.monitorSignalsList.last.overrideName,
        'coefficients0.tap0',
      );
      expect(
        signalBloc.state.monitorSignalsList
            .map((signal) => signal.monitorGroup),
        ['inputs', 'control', 'coefficients', 'coefficients'],
      );

      Future<void> openParentMenu() async {
        await tester.tapAt(
          tester.getCenter(find.byType(SignalTabContainer).first),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
      }

      await openParentMenu();
      await tester.tap(find.text('Format As'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hexadecimal'));
      await tester.pumpAndSettle();
      expect(
        signalBloc.state.monitorSignalsList.first.valueFormat,
        MonitorValueFormat.hexadecimal,
      );

      await openParentMenu();
      await tester.tap(find.text('Expand Bits [16]'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '3:0');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await waitForMonitorCount(8);

      await openParentMenu();
      await tester.tap(find.text('Define Bit Fields [16]...'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'sign 15\npayload 14:0',
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await waitForMonitorCount(10);

      final editedSignals = signalBloc.state.monitorSignalsList;
      expect(
        editedSignals.map((signal) => signal.overrideName).whereType<String>(),
        containsAll(['sampleIn0[3]', 'sampleIn0.sign', 'sampleIn0.payload']),
      );

      await tester.pumpApp(
        signalBloc: signalBloc,
        waveformModuleBloc: waveformBloc,
        child: const SignalValuePanel(),
      );
      await tester.pump();
      expect(find.byType(SignalValuePanel), findsOneWidget);

      final saved = SignalListPersistence.encode(
        entries: [
          for (final signal in editedSignals)
            SignalListEntry(
              id: signal.signalId,
              width: signal.overrideWidth,
              displayName: signal.overrideName,
              valueFormat: signal.valueFormat,
              monitorGroup: signal.monitorGroup,
            ),
        ],
        session: restorePlan.session,
      );
      final roundTrip = SignalListPersistence.decodeAndResolve(
        content: saved,
        structure: structure,
      );

      expect(roundTrip.entries, hasLength(10));
      expect(roundTrip.skippedPaths, isEmpty);
      expect(
        roundTrip.entries.map((entry) => entry.displayName).whereType<String>(),
        containsAll(['sampleIn0.sign', 'sampleIn0.payload']),
      );
      expect(
        roundTrip.entries.first.valueFormat,
        MonitorValueFormat.hexadecimal,
      );
    },
  );
}
