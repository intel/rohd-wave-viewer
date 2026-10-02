// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// wellen_reader_simple_test.dart
// Simplified tests for WellenReader using test fixtures
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

// This test suite validates the Wellen reader's ability to parse multiple
// waveform dump formats:
//
// VCD Format (Value Change Dump):
//   - Source: ROHD simulation outputs (SystemVerilog-based testbenches)
//   - File: xz_transitions.vcd
//   - Coverage: X/Z value transitions
//
// FST Format (Fast Signal Trace):
//   - Source: Converted from VCD using vcd2fst tool
//   - Command: vcd2fst xz_transitions.vcd xz_transitions.fst
//   - File: xz_transitions.fst
//   - Coverage: X/Z transitions in binary format
//
// GHW Format (GHDL Waveform):
//   - Source: Generated from test/vhdl/xz_transitions_tb.vhd using GHDL
//   - File: xz_transitions.ghw
//   - Generation: cd test/vhdl && ghdl -a xz_transitions_tb.vhd && ghdl -e test && ghdl -r test --stop-time=250ns --wave=../fixtures/xz_transitions.ghw
//   - Coverage: X/Z transitions in GHDL format
//
// To regenerate or add new fixtures:
//   1. VCD: Use ROHD simulation or write Verilog testbenches
//   2. FST: Run bash scripts/convert_test_fixtures.sh (requires vcd2fst)
//   3. GHW: Copy from Surfer examples or run the GHDL command above
//
// 2026 January 09
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:io';
import 'package:dart_wellen/dart_wellen.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

/// Path to test fixture files
String get fixturesPath {
  // Find project root by looking for pubspec.yaml in parent directories
  var current = Directory.current;
  while (!File(path.join(current.path, 'pubspec.yaml')).existsSync() ||
      !Directory(path.join(current.path, 'test', 'fixtures')).existsSync()) {
    final parent = current.parent;
    if (parent.path == current.path) {
      // Reached filesystem root
      return 'test/fixtures'; // fallback
    }
    current = parent;
  }
  return path.join(current.path, 'test', 'fixtures');
}

void main() {
  setUpAll(() async {
    // Initialize the Rust FFI library before running any tests
    await WellenReader.init();
  });

  group('WellenReader VCD parsing with fixtures', () {
    test('loads xz_transitions.vcd with X and Z values', () async {
      final reader = WellenReader();
      final vcdPath = '$fixturesPath/xz_transitions.vcd';

      if (!File(vcdPath).existsSync()) {
        markTestSkipped('Test VCD file not found: $vcdPath');
        return;
      }

      final metadata = await reader.loadFile(vcdPath);
      expect(metadata.format, equals(WaveFormat.vcd));

      final structure = await reader.getStructure();
      expect(structure.modules, isNotEmpty);

      // This file specifically has X and Z transitions
      final testModule = structure.modules.firstWhere(
        (m) => m.name == 'test',
        orElse: () => throw StateError('Module test not found'),
      );
      expect(testModule.name, equals('test'));

      // Load waveform data to verify X/Z handling
      final waveformData = await reader.getWaveformData(structure.allSignalIds);
      expect(waveformData, isNotEmpty);
    });
  });

  group('WellenReader lifecycle', () {
    test('can load and close file', () async {
      final reader = WellenReader();
      final vcdPath = '$fixturesPath/xz_transitions.vcd';

      if (!File(vcdPath).existsSync()) {
        markTestSkipped('Test VCD file not found: $vcdPath');
        return;
      }

      await reader.loadFile(vcdPath);
      final structure = await reader.getStructure();
      expect(structure.modules, isNotEmpty);

      // Should be able to close without error
      await reader.close();
    });
  });

  group('WellenReader FST format support', () {
    test('loads xz_transitions.fst with X and Z values', () async {
      final reader = WellenReader();
      final fstPath = '$fixturesPath/xz_transitions.fst';

      if (!File(fstPath).existsSync()) {
        markTestSkipped('Test FST file not found: $fstPath');
        return;
      }

      final metadata = await reader.loadFile(fstPath);
      expect(metadata.format, equals(WaveFormat.fst));

      final structure = await reader.getStructure();
      expect(structure.modules, isNotEmpty);

      // This file specifically has X and Z transitions
      final testModule = structure.modules.firstWhere(
        (m) => m.name == 'test',
        orElse: () => throw StateError('Module test not found'),
      );
      expect(testModule.name, equals('test'));

      // Load waveform data to verify X/Z handling in FST format
      final waveformData = await reader.getWaveformData(structure.allSignalIds);
      expect(waveformData, isNotEmpty);
    });
  });

  group('WellenReader GHW format support', () {
    test('loads xz_transitions.ghw with X and Z values', () async {
      final reader = WellenReader();
      final ghwPath = '$fixturesPath/xz_transitions.ghw';

      if (!File(ghwPath).existsSync()) {
        markTestSkipped(
          'Test GHW file not found: $ghwPath. Generate via test/vhdl/xz_transitions_tb.vhd using GHDL.',
        );
        return;
      }

      final metadata = await reader.loadFile(ghwPath);
      expect(metadata.format, equals(WaveFormat.ghw));

      final structure = await reader.getStructure();
      expect(structure.modules, isNotEmpty);

      final testModule = structure.modules.firstWhere(
        (m) => m.name == 'test',
        orElse: () => throw StateError('Module test not found in GHW fixture'),
      );
      expect(testModule.name, equals('test'));

      final clkSignalId = structure.allSignalIds.firstWhere(
        (s) => s.contains('clk'),
        orElse: () => throw StateError('clk signal not found in GHW fixture'),
      );

      final dataSignalId = structure.allSignalIds.firstWhere(
        (s) => s.contains('data8'),
        orElse: () => throw StateError('data8 signal not found in GHW fixture'),
      );

      final waveformData = await reader.getWaveformData([
        clkSignalId,
        dataSignalId,
      ]);
      expect(waveformData.length, equals(2));
      expect(waveformData.any((w) => w.signalId == dataSignalId), isTrue);
    });
  });
}
