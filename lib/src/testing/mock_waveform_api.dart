// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// mock_waveform_api.dart
// A mock implementation of the SignalWaveformApi class.
//
// 2024 April
// Author(s): Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
//            Yao Jing Quek <yao.jing.quek@intel.com>

import 'dart:async';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';

/// Mock waveform API used for development and tests.
class MockSignalWaveformApi extends SignalWaveformApi {
  /// Returns the module structure without waveform data.
  ///
  /// Builds the hierarchy tree directly — no JSON round-trip.
  Future<ModuleStructure> getModuleStructure() {
    final root = HierarchyOccurrence(
      name: 'Counter',
      signals: [
        SignalOccurrence(name: 'Signal1', direction: 'input', width: 1),
        SignalOccurrence(name: 'Signal2', direction: 'output', width: 1),
        SignalOccurrence(name: 'Signal3', direction: 'input', width: 8),
        SignalOccurrence(name: 'Signal4', direction: 'output', width: 1),
      ],
      children: [
        HierarchyOccurrence(
          name: 'counter_sub_module',
          signals: [
            SignalOccurrence(name: 'SubSignal1', direction: 'input', width: 16),
          ],
        ),
      ],
    );

    return Future.value(
      ModuleStructure(
        metadata: const MetaData(
          source: 'Source1',
          timescale: '1ns',
          date: '2022-01-01',
        ),
        modules: [root],
      ),
    );
  }

  /// Mock waveform data storage.
  /// Format: signalId -> [[time, value], [time, value], ...]
  /// Values can be strings (e.g., '1', '0', 'X', 'Z', 'ABCD') or integers
  /// (which get converted to strings). This supports both ROHD debugging format
  /// and the original string format.
  static final Map<String, List<List<dynamic>>> _waveformData = {
    'counter_sub_module.SubSignal1': [
      [1, '1'],
      [2, '0'],
      [3, 'ABCD102'],
      [4, 1], // Integer format - will be converted to '1'
      [5, 1],
    ],
    'Counter.Signal1': [
      [1, 'XXXXX'],
      [5, 1], // Integer format
      [12, 'ZZZZZ'],
      [18, 1],
    ],
    'Counter.Signal2': [
      [1, 1], // Integer format
      [2, 0],
      [4, 1],
      [9, 1],
      [10, 0],
      [11, 1],
      [12, 0],
      [13, 1],
    ],
    'Counter.Signal3': [
      [5, 'ZZZ'],
      [7, 1], // Integer format
      [9, 'XXX'],
      [14, 1],
      [17, 'ZZ'],
    ],
    'Counter.Signal4': [
      [1, 'X'],
      [4, 1], // Integer format
      [7, 'Z'],
      [10, 0],
      [13, 'X'],
      [16, 1],
      [19, 'Z'],
    ],
  };

  /// Converts a [time, value] list to a [Data] object.
  /// Supports both string values and integer values (wrapped as strings).
  /// This matches the format that ROHD would provide when debugging waveforms.
  static Data _toData(List<dynamic> pair) {
    final value = pair[1];
    // Convert integer values to string if needed
    final stringValue = value is int ? value.toString() : value as String;
    return Data(time: pair[0] as int, value: stringValue);
  }

  /// Retrieves waveform data for specific signals.
  @override
  Future<List<WaveformData>> getWaveformData({
    required List<String> signalIds,
    int? startTime,
    int? endTime,
  }) async {
    final result = <WaveformData>[];

    for (final signalId in signalIds) {
      final dataList = _waveformData[signalId];
      if (dataList != null) {
        var filteredData = dataList.map(_toData).toList();

        if (startTime != null || endTime != null) {
          filteredData = filteredData.where((d) {
            if (startTime != null && d.time < startTime) {
              return false;
            }
            if (endTime != null && d.time > endTime) {
              return false;
            }
            return true;
          }).toList();
        }

        result.add(WaveformData(signalId: signalId, data: filteredData));
      }
    }

    return result;
  }

  /// Streams waveform data incrementally for specific signals.
  ///
  /// This demonstrates how data can be streamed in chunks for
  /// incremental loading.
  @override
  Stream<WaveformData> streamWaveformData({
    required List<String> signalIds,
    int? startTime,
  }) async* {
    for (final signalId in signalIds) {
      final dataList = _waveformData[signalId];
      if (dataList != null) {
        var allData = dataList.map(_toData).toList();

        if (startTime != null) {
          allData = allData.where((d) => d.time >= startTime).toList();
        }

        // Simulate streaming by yielding data in chunks
        const chunkSize = 2;
        for (var i = 0; i < allData.length; i += chunkSize) {
          final end =
              (i + chunkSize < allData.length) ? i + chunkSize : allData.length;
          final chunk = allData.sublist(i, end);

          yield WaveformData(signalId: signalId, data: chunk);

          // Simulate network delay
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }
    }
  }
}
