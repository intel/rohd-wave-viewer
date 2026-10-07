// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_state_extended_test.dart
// Extended tests for SignalState.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';
import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';
import 'package:rohd_wave_viewer/testing.dart';

void main() {
  late List<SignalOccurrence> mockSignals;
  late List<SignalWaveform> emptyMonitor;

  setUp(() async {
    final api = MockSignalWaveformApi();
    final repo = SignalWaveformRepository(signalWaveformApi: api);
    final structure = await api.getModuleStructure();
    repo.buildSignalCacheFromHierarchy(structure.modules);
    final root = structure.modules.first;
    mockSignals = repo.getSignalsBySelectedModule(root);
    emptyMonitor = [];
  });

  group('SignalState extended', () {
    // ──── Helper getters ────

    test('hasFocusedSignals returns false when empty', () {
      final state = SignalLoaded(mockSignals, emptyMonitor);
      expect(state.hasFocusedSignals, isFalse);
    });

    test('hasFocusedSignals returns true when non-empty', () {
      final state = SignalLoaded(
        mockSignals,
        emptyMonitor,
        focusedSignalIds: const {'Counter.Signal1'},
      );
      expect(state.hasFocusedSignals, isTrue);
    });

    test('focusedSignal returns null when no signals focused', () {
      final state = SignalLoaded(mockSignals, emptyMonitor);
      expect(state.focusedSignal, isNull);
    });

    test('focusedSignal returns first focused signal', () {
      final wf = SignalWaveform(signalId: 'Counter.Signal1');
      final state = SignalLoaded(
        mockSignals,
        [wf],
        focusedSignalIds: const {'Counter.Signal1'},
      );
      expect(state.focusedSignal, isNotNull);
      expect(state.focusedSignal!.id, 'Counter.Signal1');
    });

    test('focusedSignals returns matching waveforms', () {
      final wf1 = SignalWaveform(signalId: 'Counter.Signal1');
      final wf2 = SignalWaveform(signalId: 'Counter.Signal2');
      final state = SignalLoaded(
        mockSignals,
        [wf1, wf2],
        focusedSignalIds: const {'Counter.Signal1', 'Counter.Signal2'},
      );
      expect(state.focusedSignals, hasLength(2));
    });

    test('isSignalFocused checks membership', () {
      final state = SignalLoaded(
        mockSignals,
        emptyMonitor,
        focusedSignalIds: const {'Counter.Signal1'},
      );
      expect(state.isSignalFocused('Counter.Signal1'), isTrue);
      expect(state.isSignalFocused('Counter.Signal2'), isFalse);
    });

    test('isModuleSignalSelected checks membership', () {
      final state = SignalLoaded(
        mockSignals,
        emptyMonitor,
        moduleSelectedSignalIds: const {'Counter.Signal1'},
      );
      expect(state.isModuleSignalSelected('Counter.Signal1'), isTrue);
      expect(state.isModuleSignalSelected('Counter.Signal2'), isFalse);
    });

    // ──── filteredSignals with wildcards ────

    test('filteredSignals applies wildcard filter', () {
      final state = SignalLoaded(
        mockSignals,
        emptyMonitor,
        showInternalSignals: true,
        filterText: 'Signal*',
      );
      final filtered = state.filteredSignals;
      expect(filtered, isNotEmpty);
      for (final s in filtered) {
        expect(s.name, startsWith('Signal'));
      }
    });

    test('filteredSignals treats non-wildcard symbols as text', () {
      final state = SignalLoaded(
        mockSignals,
        emptyMonitor,
        showInternalSignals: true,
        filterText: '[invalid',
      );
      final filtered = state.filteredSignals;
      expect(filtered, isA<List<SignalOccurrence>>());
    });

    test('filteredSignals plain text does prefix match', () {
      final state = SignalLoaded(
        mockSignals,
        emptyMonitor,
        showInternalSignals: true,
        filterText: 'Signal',
      );
      final filtered = state.filteredSignals;
      // All mock signals start with "Signal" so they should all match
      expect(filtered.isNotEmpty, isTrue);
      for (final s in filtered) {
        expect(s.name.toLowerCase().startsWith('signal'), isTrue);
      }
    });

    test('filteredSignals with no matches returns empty', () {
      final state = SignalLoaded(
        mockSignals,
        emptyMonitor,
        showInternalSignals: true,
        filterText: 'NoSuchSignal',
      );
      expect(state.filteredSignals, isEmpty);
    });

    // ──── filteredSignals with sort ────

    test('filteredSignals sorts ascending', () {
      final state = SignalLoaded(
        mockSignals,
        emptyMonitor,
        showInternalSignals: true,
        sortAscending: true,
      );
      final filtered = state.filteredSignals;
      for (var i = 1; i < filtered.length; i++) {
        expect(
          filtered[i - 1].name.toLowerCase().compareTo(
                filtered[i].name.toLowerCase(),
              ),
          lessThanOrEqualTo(0),
        );
      }
    });

    test('filteredSignals sorts descending', () {
      final state = SignalLoaded(
        mockSignals,
        emptyMonitor,
        showInternalSignals: true,
        sortAscending: false,
      );
      final filtered = state.filteredSignals;
      for (var i = 1; i < filtered.length; i++) {
        expect(
          filtered[i - 1].name.toLowerCase().compareTo(
                filtered[i].name.toLowerCase(),
              ),
          greaterThanOrEqualTo(0),
        );
      }
    });

    // ──── getDisplayNameForSignal ────

    test('getDisplayNameForSignal falls back to leaf name with dot', () {
      final wf = SignalWaveform(signalId: 'Counter.Signal1');
      // No monitored signals with matching id — triggers fallback
      final state = SignalLoaded(mockSignals, const []);
      final name = state.getDisplayNameForSignal(wf);
      // wf.name is 'Counter.Signal1' (signalId), fallback extracts after last
      // dot
      expect(name, 'Signal1');
    });

    test('getDisplayNameForSignal falls back to leaf name with slash', () {
      final wf = SignalWaveform(signalId: 'root/sub/Signal1');
      final state = SignalLoaded(mockSignals, const []);
      final name = state.getDisplayNameForSignal(wf);
      expect(name, 'Signal1');
    });

    test('getDisplayNameForSignal returns bare name without separator', () {
      final wf = SignalWaveform(signalId: 'Signal1');
      final state = SignalLoaded(mockSignals, const []);
      final name = state.getDisplayNameForSignal(wf);
      expect(name, 'Signal1');
    });

    test('getDisplayNameForSignal prefers a monitor-local alias', () {
      final monitored = MonitoredSignal.fromWaveform(
        SignalWaveform(signalId: 'Counter.Signal1'),
        displayName: 'exponent',
      );
      final state = SignalLoaded(mockSignals, [monitored]);

      expect(state.getDisplayNameForSignal(monitored), 'exponent');
      expect(monitored.name, 'exponent');
    });

    // ──── getMonitoredSignalDisplayNames ────

    test('getMonitoredSignalDisplayNames returns empty map for empty list', () {
      final state = SignalLoaded(mockSignals, const []);
      expect(state.getMonitoredSignalDisplayNames(), isEmpty);
    });

    // ──── SignalLoading ────

    test('SignalLoading has empty signals and monitor', () {
      final state = SignalLoading();
      expect(state.signals, isEmpty);
      expect(state.monitorSignalsList, isEmpty);
      expect(state.showInternalSignals, isFalse);
    });

    test('SignalLoading preserves showInternalSignals', () {
      final state = SignalLoading(showInternalSignals: true);
      expect(state.showInternalSignals, isTrue);
    });

    // ──── Equatable ────

    test('SignalLoaded states with different filter are not equal', () {
      final a = SignalLoaded(mockSignals, emptyMonitor, filterText: 'abc');
      final b = SignalLoaded(mockSignals, emptyMonitor, filterText: 'xyz');
      expect(a, isNot(equals(b)));
    });

    test('SignalLoaded states with different sort are not equal', () {
      final a = SignalLoaded(mockSignals, emptyMonitor, sortAscending: true);
      final b = SignalLoaded(mockSignals, emptyMonitor, sortAscending: false);
      expect(a, isNot(equals(b)));
    });

    test('SignalLoaded states with same props are equal', () {
      final a = SignalLoaded(
        mockSignals,
        emptyMonitor,
        filterText: 'test',
        sortAscending: true,
      );
      final b = SignalLoaded(
        mockSignals,
        emptyMonitor,
        filterText: 'test',
        sortAscending: true,
      );
      expect(a, equals(b));
    });
  });
}
