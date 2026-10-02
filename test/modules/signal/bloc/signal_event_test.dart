// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_event_test.dart
// Tests for the signal events.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';
import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';
import 'package:rohd_wave_viewer/testing.dart';

void main() {
  late SignalWaveformRepository signalWaveformRepository;
  late MockSignalWaveformApi signalWaveformApi;
  late ModuleStructure mockModuleStructure;
  late HierarchyOccurrence mockSelectedModule;
  late SignalOccurrence mockSelectedSignal;

  setUp(() async {
    signalWaveformApi = MockSignalWaveformApi();
    signalWaveformRepository = SignalWaveformRepository(
      signalWaveformApi: signalWaveformApi,
    );
    mockModuleStructure = await signalWaveformApi.getModuleStructure();
    signalWaveformRepository.buildSignalCacheFromHierarchy(
      mockModuleStructure.modules,
    );
    mockSelectedModule = mockModuleStructure.modules.first;
    mockSelectedSignal = signalWaveformRepository.getSignalById(
      mockSelectedModule.ports.first.path(),
    )!;
  });
  group('SignalEvent', () {
    group('SignalUpdate', () {
      test('supports value comparison', () {
        expect(
          SignalUpdateEvent(mockSelectedModule),
          SignalUpdateEvent(mockSelectedModule),
        );
      });
    });
    group('SignalSelected', () {
      test('supports value comparison', () {
        expect(
          SignalSelectedEvent(mockSelectedSignal),
          SignalSelectedEvent(mockSelectedSignal),
        );
      });
    });

    group('SignalFocus', () {
      test('supports value comparison', () {
        final wf = SignalWaveform.empty('x');
        expect(SignalFocusEvent(wf), equals(SignalFocusEvent(wf)));
      });

      test('isMultiSelect changes equality', () {
        final wf = SignalWaveform.empty('x');
        expect(
          SignalFocusEvent(wf),
          isNot(equals(SignalFocusEvent(wf, isMultiSelect: true))),
        );
      });
    });

    group('SignalRangeFocus', () {
      test('supports value comparison', () {
        expect(
          SignalRangeFocusEvent(anchorIndex: 0, extentIndex: 2),
          equals(SignalRangeFocusEvent(anchorIndex: 0, extentIndex: 2)),
        );
      });
    });

    group('SignalUnfocus', () {
      test('supports value comparison', () {
        expect(SignalUnfocusEvent(), equals(SignalUnfocusEvent()));
      });
    });

    group('SignalUnfocusOne', () {
      test('supports value comparison', () {
        expect(SignalUnfocusOneEvent('a'), equals(SignalUnfocusOneEvent('a')));
      });
    });

    group('SignalRemove', () {
      test('supports value comparison', () {
        final wf = SignalWaveform.empty('x');
        expect(SignalRemoveEvent(wf), equals(SignalRemoveEvent(wf)));
      });
    });

    group('SignalReset', () {
      test('supports value comparison', () {
        expect(SignalResetEvent(), equals(SignalResetEvent()));
      });
    });

    group('SignalRestoreMonitored', () {
      test('supports value comparison', () {
        expect(
          SignalRestoreMonitoredEvent(const ['a', 'b']),
          equals(SignalRestoreMonitoredEvent(const ['a', 'b'])),
        );
      });
    });

    group('SignalRefresh', () {
      test('default cacheOnly is false', () {
        expect(SignalRefreshEvent().cacheOnly, isFalse);
      });

      test('supports value comparison', () {
        expect(
          SignalRefreshEvent(cacheOnly: true),
          equals(SignalRefreshEvent(cacheOnly: true)),
        );
      });
    });

    group('SignalToggleInternalSignals', () {
      test('supports value comparison', () {
        expect(
          SignalToggleInternalSignalsEvent(enable: true),
          isNot(equals(SignalToggleInternalSignalsEvent(enable: false))),
        );
      });
    });

    group('SignalReorder', () {
      test('supports value comparison', () {
        expect(
          SignalReorderEvent(oldIndex: 0, newIndex: 2),
          equals(SignalReorderEvent(oldIndex: 0, newIndex: 2)),
        );
      });
    });

    group('SignalGroupReorder', () {
      test('supports value comparison', () {
        expect(
          SignalGroupReorderEvent(
            oldIndices: const [0, 1],
            anchorOldIndex: 0,
            anchorNewIndex: 2,
          ),
          equals(
            SignalGroupReorderEvent(
              oldIndices: const [0, 1],
              anchorOldIndex: 0,
              anchorNewIndex: 2,
            ),
          ),
        );
      });
    });

    group('SignalFilter', () {
      test('supports value comparison', () {
        expect(SignalFilterEvent('clock'), equals(SignalFilterEvent('clock')));
      });
    });

    group('SignalSort', () {
      test('supports value comparison', () {
        expect(
          SignalSortEvent(ascending: true),
          equals(SignalSortEvent(ascending: true)),
        );
      });
    });

    group('ModuleSignalSelect', () {
      test('supports value comparison', () {
        expect(
          ModuleSignalSelectEvent('sig1'),
          equals(ModuleSignalSelectEvent('sig1')),
        );
      });
    });

    group('ModuleSignalToggle', () {
      test('supports value comparison', () {
        expect(
          ModuleSignalToggleEvent('sig1'),
          equals(ModuleSignalToggleEvent('sig1')),
        );
      });
    });

    group('ModuleSignalRangeSelect', () {
      test('supports value comparison', () {
        expect(
          ModuleSignalRangeSelectEvent(anchorIndex: 0, extentIndex: 3),
          equals(ModuleSignalRangeSelectEvent(anchorIndex: 0, extentIndex: 3)),
        );
      });
    });

    group('Singleton events', () {
      test('ModuleSignalClearSelectionEvent', () {
        expect(
          ModuleSignalClearSelectionEvent(),
          equals(ModuleSignalClearSelectionEvent()),
        );
      });

      test('ModuleSignalAddToMonitorEvent', () {
        expect(
          ModuleSignalAddToMonitorEvent(),
          equals(ModuleSignalAddToMonitorEvent()),
        );
      });

      test('ModuleSignalRemoveFromMonitorEvent', () {
        expect(
          ModuleSignalRemoveFromMonitorEvent(),
          equals(ModuleSignalRemoveFromMonitorEvent()),
        );
      });

      test('ModuleSignalSelectAllEvent', () {
        expect(
          ModuleSignalSelectAllEvent(),
          equals(ModuleSignalSelectAllEvent()),
        );
      });

      test('SignalFocusAllEvent', () {
        expect(SignalFocusAllEvent(), equals(SignalFocusAllEvent()));
      });

      test('SignalLoadListEvent supports value comparison', () {
        final s = mockSelectedSignal;
        expect(SignalLoadListEvent([s]), equals(SignalLoadListEvent([s])));
      });
    });
  });
}
