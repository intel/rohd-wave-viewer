// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_display_utils_test.dart
// Tests for signal display name generation with duplicate handling.
//
// 2024 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_wave_viewer/src/modules/signal/utils/signal_display_utils.dart';
import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';

/// Creates a [SignalOccurrence] with parent back-references so that
/// [SignalOccurrence.path()] returns the given [fullPath].
///
/// E.g. `_signalWithPath('top/counter/clk', width: 1)` builds:
///   HierarchyOccurrence(name: 'top') └─ HierarchyOccurrence(name: 'counter')
///   └─ SignalOccurrence(name: 'clk', width: 1) and calls `buildAddresses()` so
///   the signal's `path()` returns `'top/counter/clk'`.
SignalOccurrence _signalWithPath(String fullPath, {int width = 1}) {
  final parts =
      fullPath.contains('/') ? fullPath.split('/') : fullPath.split('.');
  final moduleParts = parts.sublist(0, parts.length - 1);
  final signalName = parts.last;

  final signal = SignalOccurrence(name: signalName, width: width);

  if (moduleParts.isEmpty) {
    // Root-level signal – no parent hierarchy
    return signal;
  }

  // Build hierarchy tree top-down so buildAddresses wires parent references.
  final root = HierarchyOccurrence(name: moduleParts.first);
  var current = root;
  for (final moduleName in moduleParts.skip(1)) {
    final child = HierarchyOccurrence(name: moduleName);
    current.children.add(child);
    current = child;
  }
  current.signals.add(signal);
  root.buildAddresses();
  return signal;
}

void main() {
  group('SignalOccurrence Display Utils', () {
    group('generateSignalDisplayNames', () {
      setUp(SignalWaveform.clearSignalLookup);

      test('Returns base names when no duplicates exist', () {
        final signals = {
          'sig1': _signalWithPath('top/counter/clk'),
          'sig2': _signalWithPath('top/counter/reset'),
        };

        // Set up signal lookup
        SignalWaveform.signalLookup = (id) => signals[id];

        final waveforms = [
          SignalWaveform(signalId: 'sig1'),
          SignalWaveform(signalId: 'sig2'),
        ];

        final displayNames = generateSignalDisplayNames(waveforms);

        expect(displayNames['sig1'], equals('clk'));
        expect(displayNames['sig2'], equals('reset'));
      });

      test(
          'Prepends parent module names when duplicates with '
          'different parents exist', () {
        final signals = {
          'sig1': _signalWithPath('top/moduleA/clk'),
          'sig2': _signalWithPath('top/moduleB/clk'),
        };

        // Set up signal lookup
        SignalWaveform.signalLookup = (id) => signals[id];

        final waveforms = [
          SignalWaveform(signalId: 'sig1'),
          SignalWaveform(signalId: 'sig2'),
        ];

        final displayNames = generateSignalDisplayNames(waveforms);

        // Both signals should have qualified names to distinguish them
        expect(displayNames['sig1'], equals('moduleA/clk'));
        expect(displayNames['sig2'], equals('moduleB/clk'));
      });

      test('Uses deeper hierarchy when immediate parent is same', () {
        final signals = {
          'sig1': _signalWithPath('top/processor/alu/enable'),
          'sig2': _signalWithPath('top/processor/cache/enable'),
        };

        // Set up signal lookup
        SignalWaveform.signalLookup = (id) => signals[id];

        final waveforms = [
          SignalWaveform(signalId: 'sig1'),
          SignalWaveform(signalId: 'sig2'),
        ];

        final displayNames = generateSignalDisplayNames(waveforms);

        // Signals should be distinguished by their parent modules
        expect(displayNames['sig1'], equals('alu/enable'));
        expect(displayNames['sig2'], equals('cache/enable'));
      });

      test('Handles single signal without modification', () {
        final signals = {'sig1': _signalWithPath('top/counter/clk')};

        SignalWaveform.signalLookup = (id) => signals[id];

        final waveforms = [SignalWaveform(signalId: 'sig1')];

        final displayNames = generateSignalDisplayNames(waveforms);

        expect(displayNames['sig1'], equals('clk'));
      });

      test('Handles empty signal list', () {
        final displayNames = generateSignalDisplayNames([]);
        expect(displayNames.isEmpty, equals(true));
      });

      test('Uses signal ID as fallback when fullPath is missing', () {
        final signals = {'sig1': SignalOccurrence(name: 'clk', width: 1)};

        SignalWaveform.signalLookup = (id) => signals[id];

        final waveforms = [SignalWaveform(signalId: 'sig1')];

        final displayNames = generateSignalDisplayNames(waveforms);

        // Should use the signal name when no path is available
        expect(displayNames['sig1'], equals('clk'));
      });

      test(
        'Handles three signals with same name from different hierarchies',
        () {
          final signals = {
            'sig1': _signalWithPath('top/system/core0/counter', width: 32),
            'sig2': _signalWithPath('top/system/core1/counter', width: 32),
            'sig3': _signalWithPath('top/memory/counter', width: 32),
          };

          SignalWaveform.signalLookup = (id) => signals[id];

          final waveforms = [
            SignalWaveform(signalId: 'sig1'),
            SignalWaveform(signalId: 'sig2'),
            SignalWaveform(signalId: 'sig3'),
          ];

          final displayNames = generateSignalDisplayNames(waveforms);

          // All should be distinguished
          expect(displayNames['sig1'], equals('core0/counter'));
          expect(displayNames['sig2'], equals('core1/counter'));
          expect(displayNames['sig3'], equals('memory/counter'));
        },
      );
    });

    group('generateSignalDisplayNames with selectedModulePath', () {
      setUp(SignalWaveform.clearSignalLookup);

      test('Signals in selected module show bare names', () {
        final signals = {
          'sig1': _signalWithPath('top/counter/clk'),
          'sig2': _signalWithPath('top/counter/reset'),
        };

        SignalWaveform.signalLookup = (id) => signals[id];

        final waveforms = [
          SignalWaveform(signalId: 'sig1'),
          SignalWaveform(signalId: 'sig2'),
        ];

        final displayNames = generateSignalDisplayNames(
          waveforms,
          selectedModulePath: 'top/counter',
        );

        expect(displayNames['sig1'], equals('clk'));
        expect(displayNames['sig2'], equals('reset'));
      });

      test('Signals in immediate child use bare names when unique', () {
        final signals = {
          'sig1': _signalWithPath('top/counter/adder/a'),
          'sig2': _signalWithPath('top/counter/adder/b'),
        };

        SignalWaveform.signalLookup = (id) => signals[id];

        final waveforms = [
          SignalWaveform(signalId: 'sig1'),
          SignalWaveform(signalId: 'sig2'),
        ];

        final displayNames = generateSignalDisplayNames(
          waveforms,
          selectedModulePath: 'top/counter',
        );

        // Unique names don't need scope prefix
        expect(displayNames['sig1'], equals('a'));
        expect(displayNames['sig2'], equals('b'));
      });

      test('Signals in deep descendant use bare name when unique', () {
        final signals = {
          'sig1': _signalWithPath('top/counter/adder/multiplier/x'),
        };

        SignalWaveform.signalLookup = (id) => signals[id];

        final waveforms = [SignalWaveform(signalId: 'sig1')];

        final displayNames = generateSignalDisplayNames(
          waveforms,
          selectedModulePath: 'top/counter',
        );

        // Unique name doesn't need scope prefix
        expect(displayNames['sig1'], equals('x'));
      });

      test('Signals in sibling module get sibling prefix', () {
        final signals = {
          'sig1': _signalWithPath('top/counter/clk'),
          'sig2': _signalWithPath('top/timer/clk'),
        };

        SignalWaveform.signalLookup = (id) => signals[id];

        final waveforms = [
          SignalWaveform(signalId: 'sig1'),
          SignalWaveform(signalId: 'sig2'),
        ];

        final displayNames = generateSignalDisplayNames(
          waveforms,
          selectedModulePath: 'top/counter',
        );

        expect(displayNames['sig1'], equals('clk'));
        expect(displayNames['sig2'], equals('timer/clk'));
      });

      test('Mixed signals: own, child, sibling, deep descendant', () {
        final signals = {
          'sig1': _signalWithPath('top/counter/clk'),
          'sig2': _signalWithPath('top/counter/adder/a', width: 8),
          'sig3': _signalWithPath('top/timer/clk'),
          'sig4': _signalWithPath('top/counter/adder/mul/x'),
        };

        SignalWaveform.signalLookup = (id) => signals[id];

        final waveforms = [
          SignalWaveform(signalId: 'sig1'),
          SignalWaveform(signalId: 'sig2'),
          SignalWaveform(signalId: 'sig3'),
          SignalWaveform(signalId: 'sig4'),
        ];

        final displayNames = generateSignalDisplayNames(
          waveforms,
          selectedModulePath: 'top/counter',
        );

        // 'clk' is duplicated → scope-aware disambiguation
        // own module → bare name
        expect(displayNames['sig1'], equals('clk'));
        // sibling → sibling/name (disambiguated from sig1's "clk")
        expect(displayNames['sig3'], equals('timer/clk'));
        // 'a' and 'x' are unique → bare names
        expect(displayNames['sig2'], equals('a'));
        expect(displayNames['sig4'], equals('x'));
      });

      test('Dot-separated paths work correctly', () {
        final signals = {
          'sig1': _signalWithPath('top.counter.clk'),
          'sig2': _signalWithPath('top.counter.adder.a', width: 8),
        };

        SignalWaveform.signalLookup = (id) => signals[id];

        final waveforms = [
          SignalWaveform(signalId: 'sig1'),
          SignalWaveform(signalId: 'sig2'),
        ];

        final displayNames = generateSignalDisplayNames(
          waveforms,
          selectedModulePath: 'top.counter',
        );

        // Both names are unique → bare names
        expect(displayNames['sig1'], equals('clk'));
        expect(displayNames['sig2'], equals('a'));
      });

      test('Internal signals (__internal__) are handled correctly', () {
        final signals = {
          'sig1': _signalWithPath('top/counter/__internal__/wire_a'),
        };

        SignalWaveform.signalLookup = (id) => signals[id];

        final waveforms = [SignalWaveform(signalId: 'sig1')];

        final displayNames = generateSignalDisplayNames(
          waveforms,
          selectedModulePath: 'top/counter',
        );

        // __internal__ should be stripped, signal is in selected module
        expect(displayNames['sig1'], equals('wire_a'));
      });

      test('Switching selected module: unique names always bare', () {
        final signals = {
          'sig1': _signalWithPath('top/counter/clk'),
          'sig2': _signalWithPath('top/counter/adder/a', width: 8),
        };

        SignalWaveform.signalLookup = (id) => signals[id];

        final waveforms = [
          SignalWaveform(signalId: 'sig1'),
          SignalWaveform(signalId: 'sig2'),
        ];

        // Both names are unique → always bare, regardless of selected module
        var displayNames = generateSignalDisplayNames(
          waveforms,
          selectedModulePath: 'top/counter',
        );
        expect(displayNames['sig1'], equals('clk'));
        expect(displayNames['sig2'], equals('a'));

        displayNames = generateSignalDisplayNames(
          waveforms,
          selectedModulePath: 'top',
        );
        expect(displayNames['sig1'], equals('clk'));
        expect(displayNames['sig2'], equals('a'));

        displayNames = generateSignalDisplayNames(
          waveforms,
          selectedModulePath: 'top/counter/adder',
        );
        expect(displayNames['sig1'], equals('clk'));
        expect(displayNames['sig2'], equals('a'));
      });

      test(
          'Real-app format: dotted fullPath IDs with selectedModulePath '
          'produces bare names', () {
        // This test mimics the EXACT format used by the real app:
        // - SignalOccurrence IDs are fullPaths like "testbench.clk"
        // - SignalOccurrence names are leaf names like "clk"
        // - selectedModulePath is the module's fullPath like "testbench"
        final signals = {
          'testbench.clk': _signalWithPath('testbench.clk'),
          'testbench.reset': _signalWithPath('testbench.reset'),
          'testbench.data': _signalWithPath('testbench.data', width: 8),
        };

        SignalWaveform.signalLookup = (id) => signals[id];

        final waveforms = [
          SignalWaveform(signalId: 'testbench.clk'),
          SignalWaveform(signalId: 'testbench.reset'),
          SignalWaveform(signalId: 'testbench.data'),
        ];

        final displayNames = generateSignalDisplayNames(
          waveforms,
          selectedModulePath: 'testbench',
        );

        // All unique names → bare names expected
        expect(displayNames['testbench.clk'], equals('clk'));
        expect(displayNames['testbench.reset'], equals('reset'));
        expect(displayNames['testbench.data'], equals('data'));
      });

      test(
          'Real-app format: dotted fullPath IDs WITHOUT selectedModulePath '
          'produces bare names', () {
        // Test the fallback path when selectedModulePath is null
        final signals = {
          'testbench.clk': _signalWithPath('testbench.clk'),
          'testbench.reset': _signalWithPath('testbench.reset'),
        };

        SignalWaveform.signalLookup = (id) => signals[id];

        final waveforms = [
          SignalWaveform(signalId: 'testbench.clk'),
          SignalWaveform(signalId: 'testbench.reset'),
        ];

        final displayNames = generateSignalDisplayNames(waveforms);

        // All unique names → bare names expected
        expect(displayNames['testbench.clk'], equals('clk'));
        expect(displayNames['testbench.reset'], equals('reset'));
      });

      test(
          'Real-app format: signal lookup failure falls back to signalId '
          '(regression check)', () {
        // When the signal lookup fails, SignalWaveform.name returns signalId
        // which is the fullPath like "testbench.clk". The disambiguation
        // should NOT produce "testbench.clk" as the display name.
        SignalWaveform.clearSignalLookup();

        final waveforms = [
          SignalWaveform(signalId: 'testbench.clk'),
          SignalWaveform(signalId: 'testbench.reset'),
        ];

        // Without signal lookup, signal.name = signalId = "testbench.clk"
        // This mimics a scenario where the signal cache wasn't populated
        final displayNames = generateSignalDisplayNames(
          waveforms,
          selectedModulePath: 'testbench',
        );

        // Even without lookup, should produce bare names
        // The scope-aware code should use fullPath (which == signalId)
        expect(displayNames['testbench.clk'], equals('clk'));
        expect(displayNames['testbench.reset'], equals('reset'));
      });

      test(
          'Real-app format: signal lookup failure without selectedModulePath '
          'produces bare names', () {
        // Fallback path: no selectedModulePath AND no signal lookup
        SignalWaveform.clearSignalLookup();

        final waveforms = [
          SignalWaveform(signalId: 'testbench.clk'),
          SignalWaveform(signalId: 'testbench.reset'),
        ];

        final displayNames = generateSignalDisplayNames(waveforms);

        // Even without lookup, should extract leaf names
        expect(displayNames['testbench.clk'], equals('clk'));
        expect(displayNames['testbench.reset'], equals('reset'));
      });

      test(
          'duplicate instances of the same signal should not trigger '
          'disambiguation', () {
        // When the same signal is added to the monitor list multiple times
        // (e.g., for performance comparison), they share the same id and
        // fullPath. This should NOT cause disambiguation prefixing.
        final signals = <String, SignalOccurrence>{
          'top.counter.clk': _signalWithPath('top.counter.clk'),
        };

        SignalWaveform.signalLookup = (id) => signals[id];

        final waveforms = [
          SignalWaveform(signalId: 'top.counter.clk'),
          SignalWaveform(signalId: 'top.counter.clk'), // same signal again
          SignalWaveform(signalId: 'top.counter.clk'), // and again
        ];

        // Without selectedModulePath (fallback path)
        var displayNames = generateSignalDisplayNames(waveforms);
        expect(displayNames['top.counter.clk'], equals('clk'));

        // With selectedModulePath (scope-aware path)
        displayNames = generateSignalDisplayNames(
          waveforms,
          selectedModulePath: 'top.counter',
        );
        expect(displayNames['top.counter.clk'], equals('clk'));
      });

      test(
          'duplicate instances should not prevent disambiguation of '
          'truly different signals', () {
        // Two different signals named "clk" from different modules, plus
        // duplicates of one of them. The disambiguation should still work
        // for the distinct signals, but the duplicates shouldn't inflate
        // the conflict count.
        final signals = <String, SignalOccurrence>{
          'top.counter.clk': _signalWithPath('top.counter.clk'),
          'top.timer.clk': _signalWithPath('top.timer.clk'),
        };

        SignalWaveform.signalLookup = (id) => signals[id];

        final waveforms = [
          SignalWaveform(signalId: 'top.counter.clk'),
          SignalWaveform(signalId: 'top.counter.clk'), // duplicate
          SignalWaveform(signalId: 'top.timer.clk'),
        ];

        final displayNames = generateSignalDisplayNames(waveforms);

        // Both "clk" signals need disambiguation because they come from
        // different modules, but the duplicate shouldn't affect anything
        expect(displayNames['top.counter.clk'], equals('counter/clk'));
        expect(displayNames['top.timer.clk'], equals('timer/clk'));
      });
    });
  });
}
