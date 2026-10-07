// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_module_state_extended_test.dart
// Extended tests for RohdModuleState.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_wave_viewer/src/modules/rohd_module/bloc/rohd_module_bloc.dart';
import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';
import 'package:rohd_wave_viewer/testing.dart';

void main() {
  late ModuleStructure structure;
  late HierarchyOccurrence rootModule;

  setUp(() async {
    final api = MockSignalWaveformApi();
    structure = await api.getModuleStructure();
    rootModule = structure.modules.first;
  });

  group('RohdModuleState extended', () {
    // ──── Loading ────

    test('Loading props include moduleStructure', () {
      final state = Loading(structure);
      expect(state.props, contains(structure));
    });

    // ──── Rendered ────

    test('Rendered exposes rohdModules', () {
      final state = Rendered(structure);
      expect(state.rohdModules, same(structure));
      expect(state.module, same(structure));
    });

    test('Rendered equality', () {
      final a = Rendered(structure);
      final b = Rendered(structure);
      expect(a, equals(b));
    });

    // ──── RohdModuleError ────
    test('RohdModuleError state holds moduleStructure', () {
      final state = RohdModuleError(structure);
      expect(state.moduleStructure, same(structure));
    });

    test('RohdModuleError equality', () {
      final a = RohdModuleError(structure);
      final b = RohdModuleError(structure);
      expect(a, equals(b));
    });

    test('RohdModuleError is not equal to Loading with same structure', () {
      final error = RohdModuleError(structure);
      final loading = Loading(structure);
      expect(error, isNot(equals(loading)));
    });

    // ──── WaveformUpdated ────

    test('WaveformUpdated exposes upToTime and selectedModule', () {
      final state = WaveformUpdated(structure, 500, selectedModule: rootModule);
      expect(state.upToTime, 500);
      expect(state.selectedModule, rootModule);
      expect(state.rohdModules, same(structure));
    });

    test('WaveformUpdated with dataEndTime', () {
      final state = WaveformUpdated(structure, 500, dataEndTime: 300);
      expect(state.dataEndTime, 300);
    });

    test('WaveformUpdated with null selectedModule', () {
      final state = WaveformUpdated(structure, 100);
      expect(state.selectedModule, isNull);
    });

    test('WaveformUpdated sequences are unique', () {
      final a = WaveformUpdated(structure, 100);
      final b = WaveformUpdated(structure, 100);
      expect(a.sequence, isNot(equals(b.sequence)));
      // Therefore states are not equal even with same data
      expect(a, isNot(equals(b)));
    });

    // ──── ModuleSelected ────

    test('ModuleSelected rohdModules alias', () {
      final state = ModuleSelected(structure, rootModule);
      expect(state.rohdModules, same(structure));
      expect(state.singleModule, same(rootModule));
    });
  });
}
