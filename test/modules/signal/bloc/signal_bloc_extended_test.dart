// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_bloc_extended_test.dart
// Extended tests for SignalBloc.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';
import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';
import 'package:rohd_wave_viewer/testing.dart';

void main() {
  group('SignalBloc', () {
    late SignalBloc signalBloc;
    late SignalWaveformRepository repo;
    late MockSignalWaveformApi api;
    late ModuleStructure structure;
    late HierarchyOccurrence rootModule;
    late List<SignalOccurrence> mockSignals;

    setUp(() async {
      SignalValueFormatRegistry.clear();
      api = MockSignalWaveformApi();
      repo = SignalWaveformRepository(signalWaveformApi: api);
      structure = await api.getModuleStructure();
      repo.buildSignalCacheFromHierarchy(structure.modules);
      signalBloc = SignalBloc(repo);
      rootModule = structure.modules.first;
      mockSignals = repo.getSignalsBySelectedModule(rootModule);
    });

    tearDown(() async {
      await signalBloc.close();
    });

    // ──── Focus / Unfocus ────

    group('focus', () {
      blocTest<SignalBloc, SignalState>(
        'focusSignal sets focused signal',
        build: () => signalBloc,
        seed: () => SignalLoaded(mockSignals, [
          SignalWaveform.empty('a'),
          SignalWaveform.empty('b'),
        ]),
        act: (bloc) {
          final state = bloc.state as SignalLoaded;
          bloc.add(SignalFocusEvent(state.monitorSignalsList.first));
        },
        verify: (bloc) {
          final state = bloc.state as SignalLoaded;
          expect(state.focusedSignalIds, {
            state.monitorSignalsList.first.monitorId,
          });
        },
      );

      blocTest<SignalBloc, SignalState>(
        'focusSignal replaces previous focus (single select)',
        build: () => signalBloc,
        // Seed with two monitored signals and one focused
        seed: () {
          final a = SignalWaveform.empty('a');
          final b = SignalWaveform.empty('b');
          return SignalLoaded(
            mockSignals,
            [a, b],
            focusedSignalIds: {a.monitorId},
          );
        },
        act: (bloc) {
          final state = bloc.state as SignalLoaded;
          bloc.add(SignalFocusEvent(state.monitorSignalsList[1]));
        },
        verify: (bloc) {
          final state = bloc.state as SignalLoaded;
          expect(state.focusedSignalIds, {
            state.monitorSignalsList[1].monitorId,
          });
        },
      );

      blocTest<SignalBloc, SignalState>(
        'focusSignal with multiSelect toggles signal into set',
        build: () => signalBloc,
        seed: () {
          final a = SignalWaveform.empty('a');
          final b = SignalWaveform.empty('b');
          return SignalLoaded(
            mockSignals,
            [a, b],
            focusedSignalIds: {a.monitorId},
          );
        },
        act: (bloc) {
          final state = bloc.state as SignalLoaded;
          bloc.add(
            SignalFocusEvent(state.monitorSignalsList[1], isMultiSelect: true),
          );
        },
        verify: (bloc) {
          final state = bloc.state as SignalLoaded;
          expect(
            state.focusedSignalIds,
            state.monitorSignalsList
                .map((waveform) => waveform.monitorId)
                .toSet(),
          );
        },
      );

      blocTest<SignalBloc, SignalState>(
        'focusSignal with multiSelect removes already-focused signal',
        build: () => signalBloc,
        seed: () {
          final a = SignalWaveform.empty('a');
          final b = SignalWaveform.empty('b');
          return SignalLoaded(
            mockSignals,
            [a, b],
            focusedSignalIds: {a.monitorId, b.monitorId},
          );
        },
        act: (bloc) {
          final state = bloc.state as SignalLoaded;
          bloc.add(
            SignalFocusEvent(
              state.monitorSignalsList.first,
              isMultiSelect: true,
            ),
          );
        },
        verify: (bloc) {
          final state = bloc.state as SignalLoaded;
          expect(state.focusedSignalIds, {
            state.monitorSignalsList[1].monitorId,
          });
        },
      );

      blocTest<SignalBloc, SignalState>(
        'rangeFocusSignal selects range',
        build: () => signalBloc,
        seed: () => SignalLoaded(mockSignals, [
          SignalWaveform.empty('x0'),
          SignalWaveform.empty('x1'),
          SignalWaveform.empty('x2'),
          SignalWaveform.empty('x3'),
        ]),
        act: (bloc) =>
            bloc.add(SignalRangeFocusEvent(anchorIndex: 1, extentIndex: 3)),
        verify: (bloc) {
          expect(
            bloc.state.focusedSignalIds,
            bloc.state.monitorSignalsList
                .skip(1)
                .map((waveform) => waveform.monitorId)
                .toSet(),
          );
        },
      );

      blocTest<SignalBloc, SignalState>(
        'rangeFocusSignal handles reversed indices',
        build: () => signalBloc,
        seed: () => SignalLoaded(mockSignals, [
          SignalWaveform.empty('a'),
          SignalWaveform.empty('b'),
          SignalWaveform.empty('c'),
        ]),
        act: (bloc) =>
            bloc.add(SignalRangeFocusEvent(anchorIndex: 2, extentIndex: 0)),
        verify: (bloc) {
          expect(
            bloc.state.focusedSignalIds,
            bloc.state.monitorSignalsList
                .map((waveform) => waveform.monitorId)
                .toSet(),
          );
        },
      );

      blocTest<SignalBloc, SignalState>(
        'unfocusSignal clears all focus',
        build: () => signalBloc,
        seed: () => SignalLoaded(
          mockSignals,
          [SignalWaveform.empty('a')],
          focusedSignalIds: const {'a'},
        ),
        act: (bloc) => bloc.add(SignalUnfocusEvent()),
        verify: (bloc) {
          expect(bloc.state.focusedSignalIds, isEmpty);
        },
      );

      blocTest<SignalBloc, SignalState>(
        'unfocusOneSignal removes specific signal from focused set',
        build: () => signalBloc,
        seed: () => SignalLoaded(
          mockSignals,
          [SignalWaveform.empty('a'), SignalWaveform.empty('b')],
          focusedSignalIds: const {'a', 'b'},
        ),
        act: (bloc) => bloc.add(SignalUnfocusOneEvent('a')),
        verify: (bloc) {
          expect(bloc.state.focusedSignalIds, {'b'});
        },
      );

      blocTest<SignalBloc, SignalState>(
        'focusAllEvent selects all monitored signals',
        build: () => signalBloc,
        seed: () => SignalLoaded(mockSignals, [
          SignalWaveform.empty('a'),
          SignalWaveform.empty('b'),
          SignalWaveform.empty('c'),
        ]),
        act: (bloc) => bloc.add(SignalFocusAllEvent()),
        verify: (bloc) {
          expect(
            bloc.state.focusedSignalIds,
            bloc.state.monitorSignalsList
                .map((waveform) => waveform.monitorId)
                .toSet(),
          );
        },
      );
    });

    // ──── Remove / Reset ────

    group('remove and reset', () {
      blocTest<SignalBloc, SignalState>(
        'removeSignal removes waveform from monitor list',
        build: () => signalBloc,
        seed: () => SignalLoaded(mockSignals, [
          SignalWaveform.empty('a'),
          SignalWaveform.empty('b'),
        ]),
        act: (bloc) {
          final state = bloc.state as SignalLoaded;
          bloc.add(SignalRemoveEvent(state.monitorSignalsList.first));
        },
        verify: (bloc) {
          expect(bloc.state.monitorSignalsList.length, 1);
          expect(bloc.state.monitorSignalsList.first.id, 'b');
        },
      );

      blocTest<SignalBloc, SignalState>(
        'removeSignal also clears focus for that signal',
        build: () => signalBloc,
        seed: () {
          final a = SignalWaveform.empty('a');
          final b = SignalWaveform.empty('b');
          return SignalLoaded(
            mockSignals,
            [a, b],
            focusedSignalIds: {a.monitorId, b.monitorId},
          );
        },
        act: (bloc) {
          final state = bloc.state as SignalLoaded;
          bloc.add(SignalRemoveEvent(state.monitorSignalsList.first));
        },
        verify: (bloc) {
          final state = bloc.state as SignalLoaded;
          expect(state.focusedSignalIds, {
            state.monitorSignalsList.single.monitorId,
          });
        },
      );

      blocTest<SignalBloc, SignalState>(
        'removeSignal preserves another monitor row for the same signal',
        build: () => signalBloc,
        seed: () {
          final first = SignalWaveform.empty('a');
          final second = SignalWaveform.copyFrom(first);
          return SignalLoaded(
            mockSignals,
            [first, second],
            focusedSignalIds: {first.monitorId},
          );
        },
        act: (bloc) {
          final state = bloc.state as SignalLoaded;
          bloc.add(SignalRemoveEvent(state.monitorSignalsList.first));
        },
        verify: (bloc) {
          final state = bloc.state as SignalLoaded;
          expect(state.monitorSignalsList, hasLength(1));
          expect(state.monitorSignalsList.single.id, 'a');
          expect(state.focusedSignalIds, isEmpty);
        },
      );

      blocTest<SignalBloc, SignalState>(
        'resetSignals returns to SignalLoading',
        build: () => signalBloc,
        seed: () => SignalLoaded(mockSignals, [SignalWaveform.empty('a')]),
        act: (bloc) => bloc.add(SignalResetEvent()),
        expect: () => [isA<SignalLoading>()],
      );
    });

    // ──── Reorder ────

    group('reorder', () {
      blocTest<SignalBloc, SignalState>(
        'reorderSignal moves item from oldIndex to newIndex',
        build: () => signalBloc,
        seed: () => SignalLoaded(mockSignals, [
          SignalWaveform.empty('a'),
          SignalWaveform.empty('b'),
          SignalWaveform.empty('c'),
        ]),
        act: (bloc) => bloc.add(SignalReorderEvent(oldIndex: 0, newIndex: 2)),
        verify: (bloc) {
          final ids = bloc.state.monitorSignalsList.map((w) => w.id).toList();
          expect(ids, ['b', 'c', 'a']);
        },
      );

      blocTest<SignalBloc, SignalState>(
        'reorderSignalGroup moves group maintaining relative order',
        build: () => signalBloc,
        seed: () => SignalLoaded(mockSignals, [
          SignalWaveform.empty('a'), // 0
          SignalWaveform.empty('b'), // 1
          SignalWaveform.empty('c'), // 2
          SignalWaveform.empty('d'), // 3
        ]),
        act: (bloc) => bloc.add(
          SignalGroupReorderEvent(
            oldIndices: const [0, 1],
            anchorOldIndex: 0,
            anchorNewIndex: 3,
          ),
        ),
        verify: (bloc) {
          final ids = bloc.state.monitorSignalsList.map((w) => w.id).toList();
          expect(ids, ['c', 'd', 'a', 'b']);
        },
      );
    });

    group('monitor edit history', () {
      blocTest<SignalBloc, SignalState>(
        'undo restores a removed monitor row and its focus',
        build: () => signalBloc,
        seed: () {
          final a = SignalWaveform.empty('a');
          final b = SignalWaveform.empty('b');
          return SignalLoaded(
            mockSignals,
            [a, b],
            focusedSignalIds: {a.monitorId},
          );
        },
        act: (bloc) {
          final state = bloc.state as SignalLoaded;
          bloc
            ..add(SignalRemoveEvent(state.monitorSignalsList.first))
            ..add(SignalUndoMonitorEvent());
        },
        verify: (bloc) {
          final state = bloc.state as SignalLoaded;
          expect(state.monitorSignalsList.map((waveform) => waveform.id), [
            'a',
            'b',
          ]);
          expect(state.focusedSignalIds, {
            state.monitorSignalsList.first.monitorId,
          });
          expect(bloc.canRedoMonitorEdit, isTrue);
        },
      );

      blocTest<SignalBloc, SignalState>(
        'redo reapplies an undone reorder',
        build: () => signalBloc,
        seed: () => SignalLoaded(mockSignals, [
          SignalWaveform.empty('a'),
          SignalWaveform.empty('b'),
          SignalWaveform.empty('c'),
        ]),
        act: (bloc) => bloc
          ..add(SignalReorderEvent(oldIndex: 0, newIndex: 2))
          ..add(SignalUndoMonitorEvent())
          ..add(SignalRedoMonitorEvent()),
        verify: (bloc) {
          expect(bloc.state.monitorSignalsList.map((waveform) => waveform.id), [
            'b',
            'c',
            'a',
          ]);
        },
      );

      blocTest<SignalBloc, SignalState>(
        'reset clears undo and redo history from the previous file',
        build: () => signalBloc,
        seed: () => SignalLoaded(mockSignals, [
          SignalWaveform.empty('old.a'),
          SignalWaveform.empty('old.b'),
        ]),
        act: (bloc) async {
          final removed = bloc.stream.firstWhere(
            (state) =>
                state is SignalLoaded && state.monitorSignalsList.length == 1,
          );
          bloc.add(
            SignalRemoveEvent(bloc.state.monitorSignalsList.first),
          );
          await removed;

          final reset =
              bloc.stream.firstWhere((state) => state is SignalLoading);
          bloc.add(SignalResetEvent());
          await reset;

          final reloaded = bloc.stream.firstWhere(
            (state) => state is SignalLoaded,
          );
          bloc.add(SignalUpdateEvent(rootModule));
          await reloaded;
          bloc.add(SignalUndoMonitorEvent());
        },
        verify: (bloc) {
          expect(bloc.state.monitorSignalsList, isEmpty);
          expect(bloc.canUndoMonitorEdit, isFalse);
          expect(bloc.canRedoMonitorEdit, isFalse);
        },
      );

      blocTest<SignalBloc, SignalState>(
        'sets and undoes a per-row display format',
        build: () => signalBloc,
        seed: () => SignalLoaded(mockSignals, [SignalWaveform.empty('a')]),
        act: (bloc) {
          final row = bloc.state.monitorSignalsList.single;
          bloc
            ..add(
              SignalSetValueFormatEvent(
                monitorIds: {row.monitorId},
                valueFormat: MonitorValueFormat.signedDecimal,
              ),
            )
            ..add(SignalUndoMonitorEvent());
        },
        verify: (bloc) {
          expect(
            bloc.state.monitorSignalsList.single.valueFormat,
            MonitorValueFormat.waveform,
          );
          expect(bloc.canRedoMonitorEdit, isTrue);
        },
      );

      blocTest<SignalBloc, SignalState>(
        'sets a display format for every monitored row of an occurrence',
        build: () => signalBloc,
        seed: () => SignalLoaded(mockSignals, [
          SignalWaveform.empty('shared.path'),
          SignalWaveform.empty('shared.path'),
          SignalWaveform.empty('other.path'),
        ]),
        act: (bloc) => bloc.add(
          SignalSetOccurrenceValueFormatEvent(
            signalPaths: const {'shared.path'},
            valueFormat: MonitorValueFormat.hexadecimal,
          ),
        ),
        verify: (bloc) {
          expect(
            bloc.valueFormatForSignalPath('shared.path'),
            MonitorValueFormat.hexadecimal,
          );
          expect(
            bloc.state.monitorSignalsList.map(
              (waveform) => waveform.valueFormat,
            ),
            [
              MonitorValueFormat.hexadecimal,
              MonitorValueFormat.hexadecimal,
              MonitorValueFormat.waveform,
            ],
          );
        },
      );

      blocTest<SignalBloc, SignalState>(
        'sets signed decimal for every monitored row of an occurrence',
        build: () => signalBloc,
        seed: () => SignalLoaded(mockSignals, [
          SignalWaveform(signalId: 'signed.path', overrideWidth: 8),
          SignalWaveform(signalId: 'signed.path', overrideWidth: 8),
        ]),
        act: (bloc) => bloc.add(
          SignalSetOccurrenceValueFormatEvent(
            signalPaths: const {'signed.path'},
            valueFormat: MonitorValueFormat.signedDecimal,
          ),
        ),
        verify: (bloc) {
          expect(
            bloc.valueFormatForSignalPath('signed.path'),
            MonitorValueFormat.signedDecimal,
          );
          expect(
            bloc.state.monitorSignalsList.map(
              (waveform) => waveform.valueFormat,
            ),
            everyElement(MonitorValueFormat.signedDecimal),
          );
        },
      );

      blocTest<SignalBloc, SignalState>(
        'sets and undoes a monitor group',
        build: () => signalBloc,
        seed: () => SignalLoaded(mockSignals, [SignalWaveform.empty('a')]),
        act: (bloc) {
          final row = bloc.state.monitorSignalsList.single;
          bloc
            ..add(
              SignalSetMonitorGroupEvent(
                monitorIds: {row.monitorId},
                groupName: 'Clocks',
              ),
            )
            ..add(SignalUndoMonitorEvent());
        },
        verify: (bloc) {
          expect(bloc.state.monitorSignalsList.single.monitorGroup, isNull);
          expect(bloc.canRedoMonitorEdit, isTrue);
        },
      );
    });

    // ──── Filter / Sort ────

    group('filter and sort', () {
      blocTest<SignalBloc, SignalState>(
        'SignalFilterEvent updates filterText',
        build: () => signalBloc,
        act: (bloc) => bloc.add(SignalFilterEvent('clock')),
        verify: (bloc) {
          expect(bloc.state.filterText, 'clock');
        },
      );

      blocTest<SignalBloc, SignalState>(
        'SignalFilterEvent clears module selection',
        build: () => signalBloc,
        seed: () => SignalLoaded(
          mockSignals,
          const [],
          moduleSelectedSignalIds: const {'some-id'},
        ),
        act: (bloc) => bloc.add(SignalFilterEvent('test')),
        verify: (bloc) {
          expect(bloc.state.moduleSelectedSignalIds, isEmpty);
        },
      );

      blocTest<SignalBloc, SignalState>(
        'SignalSortEvent updates sortAscending',
        build: () => signalBloc,
        act: (bloc) => bloc.add(SignalSortEvent(ascending: true)),
        verify: (bloc) {
          expect(bloc.state.sortAscending, true);
        },
      );

      blocTest<SignalBloc, SignalState>(
        'SignalSortEvent null resets to natural order',
        build: () => signalBloc,
        seed: () => SignalLoaded(mockSignals, const [], sortAscending: true),
        act: (bloc) => bloc.add(SignalSortEvent(ascending: null)),
        verify: (bloc) {
          expect(bloc.state.sortAscending, isNull);
        },
      );
    });

    // ──── Module SignalOccurrence Selection ────

    group('module signal selection', () {
      blocTest<SignalBloc, SignalState>(
        'ModuleSignalSelectEvent sets single selection',
        build: () => signalBloc,
        act: (bloc) => bloc.add(ModuleSignalSelectEvent('sig1')),
        verify: (bloc) {
          expect(bloc.state.moduleSelectedSignalIds, {'sig1'});
        },
      );

      blocTest<SignalBloc, SignalState>(
        'ModuleSignalToggleEvent adds to selection',
        build: () => signalBloc,
        seed: () => SignalLoaded(
          mockSignals,
          const [],
          moduleSelectedSignalIds: const {'sig1'},
        ),
        act: (bloc) => bloc.add(ModuleSignalToggleEvent('sig2')),
        verify: (bloc) {
          expect(bloc.state.moduleSelectedSignalIds, {'sig1', 'sig2'});
        },
      );

      blocTest<SignalBloc, SignalState>(
        'ModuleSignalToggleEvent removes from selection when already present',
        build: () => signalBloc,
        seed: () => SignalLoaded(
          mockSignals,
          const [],
          moduleSelectedSignalIds: const {'sig1', 'sig2'},
        ),
        act: (bloc) => bloc.add(ModuleSignalToggleEvent('sig1')),
        verify: (bloc) {
          expect(bloc.state.moduleSelectedSignalIds, {'sig2'});
        },
      );

      blocTest<SignalBloc, SignalState>(
        'ModuleSignalClearSelectionEvent clears all',
        build: () => signalBloc,
        seed: () => SignalLoaded(
          mockSignals,
          const [],
          moduleSelectedSignalIds: const {'sig1', 'sig2'},
        ),
        act: (bloc) => bloc.add(ModuleSignalClearSelectionEvent()),
        verify: (bloc) {
          expect(bloc.state.moduleSelectedSignalIds, isEmpty);
        },
      );

      blocTest<SignalBloc, SignalState>(
        'ModuleSignalSelectAllEvent selects all filtered signals',
        build: () => signalBloc,
        seed: () => SignalLoaded(
          mockSignals,
          const [],
          selectedModulePath: rootModule.path(),
        ),
        act: (bloc) => bloc.add(ModuleSignalSelectAllEvent()),
        verify: (bloc) {
          // Should have all signal paths from filteredSignals
          expect(
            bloc.state.moduleSelectedSignalIds.length,
            bloc.state.filteredSignals.length,
          );
        },
      );

      blocTest<SignalBloc, SignalState>(
        'ModuleSignalRangeSelectEvent selects range',
        build: () => signalBloc,
        seed: () => SignalLoaded(
          mockSignals,
          const [],
          selectedModulePath: rootModule.path(),
        ),
        act: (bloc) => bloc.add(
          ModuleSignalRangeSelectEvent(anchorIndex: 0, extentIndex: 1),
        ),
        verify: (bloc) {
          expect(bloc.state.moduleSelectedSignalIds.length, 2);
        },
      );
    });

    // ──── Module SignalOccurrence Add/Remove to Monitor ────

    group('module signal add/remove to monitor', () {
      blocTest<SignalBloc, SignalState>(
        'ModuleSignalAddToMonitorEvent adds selected signals '
        'and clears selection',
        build: () => signalBloc,
        seed: () {
          repo.selectedModule = rootModule;
          return SignalLoaded(
            mockSignals,
            const [],
            selectedModulePath: rootModule.path(),
            moduleSelectedSignalIds: {
              mockSignals[0].path(),
              mockSignals[1].path(),
            },
          );
        },
        act: (bloc) => bloc.add(ModuleSignalAddToMonitorEvent()),
        verify: (bloc) {
          expect(bloc.state.monitorSignalsList.length, 2);
          expect(bloc.state.moduleSelectedSignalIds, isEmpty);
        },
      );

      blocTest<SignalBloc, SignalState>(
        'ModuleSignalRemoveFromMonitorEvent removes matching signals',
        build: () => signalBloc,
        seed: () => SignalLoaded(
          mockSignals,
          [
            SignalWaveform.empty('Counter.Signal1'),
            SignalWaveform.empty('Counter.Signal2'),
            SignalWaveform.empty('Counter.Signal3'),
          ],
          moduleSelectedSignalIds: const {'Counter.Signal1', 'Counter.Signal3'},
        ),
        act: (bloc) => bloc.add(ModuleSignalRemoveFromMonitorEvent()),
        verify: (bloc) {
          expect(bloc.state.monitorSignalsList.length, 1);
          expect(bloc.state.monitorSignalsList.first.id, 'Counter.Signal2');
          expect(bloc.state.moduleSelectedSignalIds, isEmpty);
        },
      );

      blocTest<SignalBloc, SignalState>(
        'ModuleSignalRemoveFromMonitorEvent also clears focused state',
        build: () => signalBloc,
        seed: () => SignalLoaded(
          mockSignals,
          [SignalWaveform.empty('a'), SignalWaveform.empty('b')],
          focusedSignalIds: const {'a', 'b'},
          moduleSelectedSignalIds: const {'a'},
        ),
        act: (bloc) => bloc.add(ModuleSignalRemoveFromMonitorEvent()),
        verify: (bloc) {
          expect(bloc.state.focusedSignalIds, {'b'});
        },
      );
    });

    // ──── Refresh ────

    group('refresh', () {
      blocTest<SignalBloc, SignalState>(
        'SignalRefreshEvent with cacheOnly re-reads from repo cache',
        build: () => signalBloc,
        seed: () => SignalLoaded(mockSignals, [
          SignalWaveform.empty(mockSignals[0].path()),
        ]),
        act: (bloc) => bloc.add(SignalRefreshEvent(cacheOnly: true)),
        verify: (bloc) {
          expect(bloc.state.monitorSignalsList.length, 1);
        },
      );

      blocTest<SignalBloc, SignalState>(
        'SignalRefreshEvent preserves row-specific display metadata',
        build: () => signalBloc,
        seed: () {
          final waveform = SignalWaveform.empty(mockSignals.first.path())
            ..valueFormat = MonitorValueFormat.signedDecimal
            ..monitorGroup = 'Control'
            ..monitorParentId = 'parent-monitor'
            ..overrideWidth = 3
            ..overrideName = 'status';
          return SignalLoaded(mockSignals, [waveform]);
        },
        act: (bloc) => bloc.add(SignalRefreshEvent()),
        verify: (bloc) {
          final waveform = bloc.state.monitorSignalsList.single;
          expect(waveform.valueFormat, MonitorValueFormat.signedDecimal);
          expect(waveform.monitorGroup, 'Control');
          expect(waveform.monitorParentId, 'parent-monitor');
          expect(waveform.overrideWidth, 3);
          expect(waveform.overrideName, 'status');
        },
      );

      blocTest<SignalBloc, SignalState>(
        'session refresh clears history without discarding current rows',
        build: () => signalBloc,
        seed: () => SignalLoaded(mockSignals, [
          SignalWaveform.empty(mockSignals.first.path()),
        ]),
        act: (bloc) async {
          final grouped = bloc.stream.firstWhere(
            (state) => state.monitorSignalsList.single.monitorGroup == 'New',
          );
          final row = bloc.state.monitorSignalsList.single;
          bloc.add(
            SignalSetMonitorGroupEvent(
              monitorIds: {row.monitorId},
              groupName: 'New',
            ),
          );
          await grouped;

          final refreshed = bloc.stream.firstWhere(
            (state) => state is SignalLoaded,
          );
          bloc.add(
            SignalRefreshEvent(
              cacheOnly: true,
              resetMonitorHistory: true,
            ),
          );
          await refreshed;
          bloc.add(SignalUndoMonitorEvent());
        },
        verify: (bloc) {
          expect(bloc.state.monitorSignalsList, hasLength(1));
          expect(bloc.state.monitorSignalsList.single.monitorGroup, 'New');
          expect(bloc.canUndoMonitorEdit, isFalse);
          expect(bloc.canRedoMonitorEdit, isFalse);
        },
      );
    });

    // ──── State helpers ────

    group('SignalState helpers', () {
      test('hasFocusedSignals returns true when set is non-empty', () {
        final waveform = SignalWaveform.empty('a');
        final state = SignalLoaded(
          mockSignals,
          [waveform],
          focusedSignalIds: {waveform.monitorId},
        );
        expect(state.hasFocusedSignals, isTrue);
      });

      test('hasFocusedSignals returns false when set is empty', () {
        final state = SignalLoaded(mockSignals, const []);
        expect(state.hasFocusedSignals, isFalse);
      });

      test('focusedSignals returns matching waveforms', () {
        final wfA = SignalWaveform.empty('a');
        final wfB = SignalWaveform.empty('b');
        final state = SignalLoaded(
          mockSignals,
          [wfA, wfB],
          focusedSignalIds: {wfA.monitorId},
        );
        expect(state.focusedSignals.length, 1);
        expect(state.focusedSignals.first.id, 'a');
      });

      test('focusedSignal returns first focused or null', () {
        final waveform = SignalWaveform.empty('a');
        final state1 = SignalLoaded(
          mockSignals,
          [waveform],
          focusedSignalIds: {waveform.monitorId},
        );
        expect(state1.focusedSignal, isNotNull);

        final state2 = SignalLoaded(mockSignals, const []);
        expect(state2.focusedSignal, isNull);
      });

      test('isSignalFocused checks specific signal', () {
        final waveform = SignalWaveform.empty('a');
        final state = SignalLoaded(
          mockSignals,
          [waveform],
          focusedSignalIds: {waveform.monitorId},
        );
        expect(state.isSignalFocused(waveform.monitorId), isTrue);
        expect(state.isSignalFocused('other-monitor-row'), isFalse);
      });
    });

    // ──── Restore monitored signals ────

    group('restore monitored signals', () {
      test(
        'initialMonitoredSignalPaths triggers restore on first update',
        () async {
          final bloc = SignalBloc(
            repo,
            initialMonitoredSignalPaths: [
              'Counter.Signal1',
              'Counter.Signal2',
            ],
          )
            // First update triggers the pending restore
            ..add(SignalUpdateEvent(rootModule));

          // Wait for the signal update + restore events to complete
          await bloc.stream
              .firstWhere(
                (s) => s is SignalLoaded && s.monitorSignalsList.isNotEmpty,
              )
              .timeout(const Duration(seconds: 5));

          expect(bloc.state, isA<SignalLoaded>());
          expect(bloc.state.monitorSignalsList.isNotEmpty, isTrue);
          await bloc.close();
        },
      );

      test('empty initialMonitoredSignalPaths does not restore', () async {
        final bloc = SignalBloc(repo, initialMonitoredSignalPaths: [])
          ..add(SignalUpdateEvent(rootModule));

        await bloc.stream
            .firstWhere((s) => s is SignalLoaded)
            .timeout(const Duration(seconds: 5));

        expect(bloc.state, isA<SignalLoaded>());
        expect(bloc.state.monitorSignalsList, isEmpty);
        await bloc.close();
      });
    });

    // ──── LoadSignalList ────

    group('loadSignalList', () {
      blocTest<SignalBloc, SignalState>(
        'loads signals and appends to monitor list',
        build: () => signalBloc,
        seed: () => SignalLoaded(mockSignals, const []),
        act: (bloc) =>
            bloc.add(SignalLoadListEvent(mockSignals.take(2).toList())),
        verify: (bloc) {
          expect(bloc.state, isA<SignalLoaded>());
          expect(bloc.state.monitorSignalsList.length, 2);
        },
      );

      blocTest<SignalBloc, SignalState>(
        'loadSignalList appends to existing monitor list',
        build: () => signalBloc,
        seed: () =>
            SignalLoaded(mockSignals, [SignalWaveform.empty('existing')]),
        act: (bloc) =>
            bloc.add(SignalLoadListEvent(mockSignals.take(1).toList())),
        verify: (bloc) {
          expect(bloc.state, isA<SignalLoaded>());
          // 1 existing + 1 loaded
          expect(bloc.state.monitorSignalsList.length, 2);
        },
      );

      blocTest<SignalBloc, SignalState>(
        'loadSignalList with empty list is a no-op',
        build: () => signalBloc,
        seed: () => SignalLoaded(mockSignals, const []),
        act: (bloc) => bloc.add(SignalLoadListEvent(const [])),
        verify: (bloc) {
          expect(bloc.state, isA<SignalLoaded>());
          expect(bloc.state.monitorSignalsList, isEmpty);
        },
      );

      blocTest<SignalBloc, SignalState>(
        'restores ordered groups for duplicate signals',
        build: () => signalBloc,
        act: (bloc) => bloc.add(
          SignalRestoreMonitoredEvent(
            const ['Counter.Signal1', 'Counter.Signal1'],
            monitorGroups: const ['Clocks', 'Debug'],
          ),
        ),
        verify: (bloc) {
          expect(bloc.state.monitorSignalsList.map((row) => row.monitorGroup), [
            'Clocks',
            'Debug',
          ]);
        },
      );
    });

    group('restore monitored signals', () {
      blocTest<SignalBloc, SignalState>(
        'restores ordered per-row formats for duplicate signals',
        build: () => signalBloc,
        act: (bloc) => bloc.add(
          SignalRestoreMonitoredEvent(
            const ['Counter.Signal1', 'Counter.Signal1'],
            valueFormats: const [
              MonitorValueFormat.hexadecimal,
              MonitorValueFormat.signedDecimal,
            ],
          ),
        ),
        verify: (bloc) {
          final rows = bloc.state.monitorSignalsList;
          expect(rows, hasLength(2));
          expect(rows[0].id, rows[1].id);
          expect(rows[0].monitorId, isNot(rows[1].monitorId));
          expect(rows.map((row) => row.valueFormat), [
            MonitorValueFormat.hexadecimal,
            MonitorValueFormat.signedDecimal,
          ]);
        },
      );
    });

    group('bit chunk splitting', () {
      blocTest<SignalBloc, SignalState>(
        'splits from an LSB offset and retains the final partial chunk',
        build: () => signalBloc,
        seed: () {
          final parent = SignalWaveform(
            signalId: 'chunked',
            overrideWidth: 16,
            monitorGroup: 'Payload',
          );
          return SignalLoaded(mockSignals, [parent]);
        },
        act: (bloc) {
          final parent = bloc.state.monitorSignalsList.single;
          bloc.add(
            SignalBitChunkEvent(
              waveform: parent,
              index: 0,
              bitOffset: 1,
              chunkWidth: 8,
            ),
          );
        },
        verify: (bloc) {
          final rows = bloc.state.monitorSignalsList;
          expect(rows.map((row) => row.signalId), [
            'chunked',
            'chunked#b[15:9]',
            'chunked#b[8:1]',
          ]);
          expect(rows.skip(1).map((row) => row.overrideWidth), [7, 8]);
          expect(rows.skip(1).map((row) => row.monitorGroup), [
            'Payload',
            'Payload',
          ]);
        },
      );
    });

    // ──── addSignalToMonitor ────

    group('addSignalToMonitor', () {
      blocTest<SignalBloc, SignalState>(
        'adds waveform to monitor list',
        build: () => signalBloc,
        seed: () => SignalLoaded(mockSignals, const []),
        act: (bloc) {
          final port = mockSignals.first;
          bloc.add(SignalSelectedEvent(port));
        },
        verify: (bloc) {
          expect(bloc.state, isA<SignalLoaded>());
          expect(bloc.state.monitorSignalsList.length, 1);
        },
      );

      blocTest<SignalBloc, SignalState>(
        'uses a format selected before adding a waveform row',
        build: () => signalBloc,
        seed: () => SignalLoaded(mockSignals, const []),
        act: (bloc) {
          final signal = mockSignals.first;
          SignalValueFormatRegistry.setFormatFor([
            signal.address!,
          ], SignalValueFormat.signedDecimal);
          bloc.add(SignalSelectedEvent(signal));
        },
        verify: (bloc) {
          expect(
            bloc.state.monitorSignalsList.single.valueFormat,
            MonitorValueFormat.signedDecimal,
          );
        },
      );

      blocTest<SignalBloc, SignalState>(
        'allows duplicate signals in monitor list',
        build: () => signalBloc,
        seed: () => SignalLoaded(mockSignals, const []),
        act: (bloc) {
          final port = mockSignals.first;
          bloc
            ..add(SignalSelectedEvent(port))
            ..add(SignalSelectedEvent(port));
        },
        verify: (bloc) {
          expect(bloc.state, isA<SignalLoaded>());
          // Both instances should be present
          expect(bloc.state.monitorSignalsList.length, 2);
        },
      );
    });

    // ──── toggleInternalSignals ────

    group('toggleInternalSignals', () {
      blocTest<SignalBloc, SignalState>(
        'toggles showInternalSignals flag',
        build: () => signalBloc,
        seed: () => SignalLoaded(mockSignals, const []),
        act: (bloc) => bloc.add(SignalToggleInternalSignalsEvent(enable: true)),
        verify: (bloc) {
          expect(bloc.state.showInternalSignals, isTrue);
        },
      );

      blocTest<SignalBloc, SignalState>(
        'toggle back to false',
        build: () => signalBloc,
        seed: () =>
            SignalLoaded(mockSignals, const [], showInternalSignals: true),
        act: (bloc) =>
            bloc.add(SignalToggleInternalSignalsEvent(enable: false)),
        verify: (bloc) {
          expect(bloc.state.showInternalSignals, isFalse);
        },
      );
    });

    // ──── Refresh cacheOnly=false ────

    group('refresh', () {
      blocTest<SignalBloc, SignalState>(
        'refresh with cacheOnly=false reloads waveform data',
        build: () => signalBloc,
        seed: () {
          final wf = SignalWaveform(signalId: 'Counter.Signal1');
          return SignalLoaded(mockSignals, [wf]);
        },
        act: (bloc) => bloc.add(SignalRefreshEvent()),
        verify: (bloc) {
          expect(bloc.state, isA<SignalLoaded>());
          // Monitor list should still have 1 entry
          expect(bloc.state.monitorSignalsList.length, 1);
        },
      );
    });

    // ──── ModuleSignalAddToMonitor ────

    group('moduleSignalAddToMonitor', () {
      blocTest<SignalBloc, SignalState>(
        'adds selected module signals to monitor',
        build: () => signalBloc,
        seed: () => SignalLoaded(
          mockSignals,
          const [],
          moduleSelectedSignalIds: {mockSignals.first.path()},
        ),
        act: (bloc) => bloc.add(ModuleSignalAddToMonitorEvent()),
        verify: (bloc) {
          expect(bloc.state, isA<SignalLoaded>());
          expect(bloc.state.monitorSignalsList.isNotEmpty, isTrue);
          // Selection cleared after add
          expect(bloc.state.moduleSelectedSignalIds, isEmpty);
        },
      );

      blocTest<SignalBloc, SignalState>(
        'no-ops when no module signals selected',
        build: () => signalBloc,
        seed: () => SignalLoaded(mockSignals, const []),
        act: (bloc) => bloc.add(ModuleSignalAddToMonitorEvent()),
        expect: () => <SignalState>[], // no emit
      );
    });
  });
}
