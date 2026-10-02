// Copyright (C) 2025-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// integration_wellen_test.dart
// Integration tests for WellenSignalWaveformApi loading waveform files.
//
// Hierarchy (ModuleStructure) comes from the Wellen API directly — the
// SignalWaveformRepository is a waveform-data-only cache and does NOT
// provide module structure.  In production the hierarchy is supplied by
// rohd_hierarchy (populated from the schematic viewer, DevTools ModuleTree,
// or the Wellen loader in standalone mode).
//
// 2026 March
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:dart_wellen/dart_wellen.dart';
import 'package:test/test.dart';

// Tests run from the dart_wellen package root.
String get fixturesPath => 'test/fixtures';

void main() {
  setUpAll(() async {
    // Initialize Wellen FFI
    await WellenSignalWaveformApi.init();
  });

  test('WellenSignalWaveformApi can load VCD (counter.vcd)', () async {
    final api = WellenSignalWaveformApi();

    await api.loadFile('$fixturesPath/counter.vcd');
    final structure = await api.getModuleStructureOnly();
    expect(structure.modules, isNotEmpty);
    expect(structure.allSignalIds, isNotEmpty);
  });

  test('WellenSignalWaveformApi can load FST (xz_transitions.fst)', () async {
    final api = WellenSignalWaveformApi();

    await api.loadFile('$fixturesPath/xz_transitions.fst');
    final structure = await api.getModuleStructureOnly();
    expect(structure.modules, isNotEmpty);
    expect(structure.allSignalIds, isNotEmpty);
  });

  test('WellenSignalWaveformApi can load GHW (xz_transitions.ghw)', () async {
    final api = WellenSignalWaveformApi();

    await api.loadFile('$fixturesPath/xz_transitions.ghw');
    final structure = await api.getModuleStructureOnly();
    expect(structure.modules, isNotEmpty);
    expect(structure.allSignalIds, isNotEmpty);
  });

  test('preserves and reads sibling top-level VCD scopes', () async {
    final api = WellenSignalWaveformApi();

    await api.loadFile('$fixturesPath/multiple_roots.vcd');
    final structure = await api.getModuleStructureOnly();
    final root = structure.modules.single;

    expect(root.name, 'root');
    expect(root.children.map((module) => module.name), ['alpha', 'beta']);

    final alphaSignal = root.children[0].signals.single;
    final betaSignal = root.children[1].signals.single;
    expect(alphaSignal.address, isNot(equals(betaSignal.address)));

    final waveforms = await api.getWaveformData(
      signalIds: [alphaSignal.path(), betaSignal.path()],
    );
    final valuesById = {
      for (final waveform in waveforms)
        waveform.signalId: waveform.data.map((point) => point.value).toList(),
    };

    expect(valuesById[alphaSignal.path()], ['0', '1']);
    expect(valuesById[betaSignal.path()], ['1', '0']);
  });
}
