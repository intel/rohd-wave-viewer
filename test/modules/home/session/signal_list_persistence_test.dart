// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_list_persistence_test.dart
// Tests for monitored-signal session persistence.
//
// 2026 August
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';

import 'package:dart_wellen/dart_wellen.dart' hide SignalWaveform;
import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_wave_viewer/src/cubit/wave_viewer_theme_cubit.dart';
import 'package:rohd_wave_viewer/src/modules/home/session/signal_list_persistence.dart';
import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';

void main() {
  Future<ModuleStructure> loadFixtureStructure() async {
    await WellenSignalWaveformApi.init();
    final api = WellenSignalWaveformApi();
    await api.loadFile('test/fixtures/xz_transitions.vcd');
    final structure = await api.getModuleStructureOnly();
    return structure;
  }

  group('SignalListPersistence', () {
    test('round-trips current rows, duplicates, and viewer session state',
        () async {
      final structure = await loadFixtureStructure();
      final scalarId = structure.allSignalIds.firstWhere(
        (id) => id.endsWith('bin_xz'),
      );
      final busId = structure.allSignalIds.firstWhere(
        (id) => id.endsWith('bin5_xz'),
      );
      final encoded = SignalListPersistence.encode(
        entries: [
          SignalListEntry(id: scalarId),
          SignalListEntry(
            id: busId,
            width: 5,
            displayName: 'fixture_bus',
            valueFormat: MonitorValueFormat.hexadecimal,
            monitorGroup: 'inputs',
          ),
          SignalListEntry(
            id: busId,
            valueFormat: MonitorValueFormat.binary,
            monitorGroup: 'comparison',
          ),
        ],
        session: const SignalListSessionState(
          showInternalSignals: true,
          filterText: 'bin',
          cursorTimePs: 80,
          measurementMarkerTimePs: 60,
          rowScale: 1.4,
          themeMode: WaveViewerThemeMode.light,
          hierarchyPinned: false,
          appBarPinned: false,
          pinnedPanelWidth: 320,
          viewport: SignalListViewportState(
            zoomLevel: 3,
            scrollFraction: .25,
          ),
        ),
      );

      final plan = SignalListPersistence.decodeAndResolve(
        content: encoded,
        structure: structure,
      );

      expect(plan.signalPaths, [scalarId, busId, busId]);
      expect(
        plan.valueFormats,
        [
          MonitorValueFormat.waveform,
          MonitorValueFormat.hexadecimal,
          MonitorValueFormat.binary,
        ],
      );
      expect(plan.monitorGroups, [null, 'inputs', 'comparison']);
      expect(plan.metadata?[busId], (width: 5, displayName: 'fixture_bus'));
      expect(plan.skippedPaths, isEmpty);
      expect(plan.session?.showInternalSignals, isTrue);
      expect(plan.session?.filterText, 'bin');
      expect(plan.session?.cursorTimePs, 80);
      expect(plan.session?.measurementMarkerTimePs, 60);
      expect(plan.session?.rowScale, 1.4);
      expect(plan.session?.themeMode, WaveViewerThemeMode.light);
      expect(plan.session?.hierarchyPinned, isFalse);
      expect(plan.session?.appBarPinned, isFalse);
      expect(plan.session?.pinnedPanelWidth, 320);
      expect(plan.session?.viewport?.zoomLevel, 3);
      expect(plan.session?.viewport?.scrollFraction, .25);
    });

    test('supports legacy paths and skips unresolved signal parents', () async {
      final structure = await loadFixtureStructure();
      final scalarId = structure.allSignalIds.firstWhere(
        (id) => id.endsWith('bin_xz'),
      );
      final busId = structure.allSignalIds.firstWhere(
        (id) => id.endsWith('bin5_xz'),
      );
      final content = jsonEncode({
        'signals': [
          scalarId,
          '$busId#b[2]',
          'missing/signal',
          'missing/signal#b[0]',
        ],
      });

      final plan = SignalListPersistence.decodeAndResolve(
        content: content,
        structure: structure,
      );

      expect(plan.signalPaths, [scalarId, '$busId#b[2]']);
      expect(
        plan.valueFormats,
        everyElement(MonitorValueFormat.waveform),
      );
      expect(plan.monitorGroups, everyElement(isNull));
      expect(plan.skippedPaths, ['missing/signal', 'missing/signal#b[0]']);
      expect(plan.session, isNull);
    });

    test('rejects documents without a signal list', () async {
      final structure = await loadFixtureStructure();

      expect(
        () => SignalListPersistence.decodeAndResolve(
          content: jsonEncode({'version': 6}),
          structure: structure,
        ),
        throwsFormatException,
      );
    });
  });
}
