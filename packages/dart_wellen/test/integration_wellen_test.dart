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

import 'dart:io';
import 'package:dart_wellen/dart_wellen.dart';
import 'package:test/test.dart';

// The fixture files are in the project root under test/fixtures From the test
// runner, we use the current working directory which should be the project
// root
String get fixturesPath => 'test/fixtures';

void main() {
  setUpAll(() async {
    // Initialize Wellen FFI
    await WellenSignalWaveformApi.init();
  });

  test('WellenSignalWaveformApi can load VCD (simple_counter.vcd)', () async {
    final api = WellenSignalWaveformApi();

    final filePath = '$fixturesPath/simple_counter.vcd';
    if (!File(filePath).existsSync()) {
      markTestSkipped('VCD example not found: $filePath');
      return;
    }

    await api.loadFile(filePath);
    final structure = await api.getModuleStructureOnly();
    expect(structure.modules, isNotEmpty);
    expect(structure.allSignalIds, isNotEmpty);
  });

  test('WellenSignalWaveformApi can load FST (vhdl3.fst)', () async {
    final api = WellenSignalWaveformApi();

    final filePath = '$fixturesPath/vhdl3.fst';
    if (!File(filePath).existsSync()) {
      markTestSkipped('FST example not found: $filePath');
      return;
    }

    await api.loadFile(filePath);
    final structure = await api.getModuleStructureOnly();
    expect(structure.modules, isNotEmpty);
    expect(structure.allSignalIds, isNotEmpty);
  });

  test('WellenSignalWaveformApi can load GHW (vhdlfixed.ghw)', () async {
    final api = WellenSignalWaveformApi();

    final filePath = '$fixturesPath/vhdlfixed.ghw';
    if (!File(filePath).existsSync()) {
      markTestSkipped('GHW example not found: $filePath');
      return;
    }

    await api.loadFile(filePath);
    final structure = await api.getModuleStructureOnly();
    expect(structure.modules, isNotEmpty);
    expect(structure.allSignalIds, isNotEmpty);
  });
}
