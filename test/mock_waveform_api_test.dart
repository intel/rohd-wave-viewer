// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// mock_waveform_api_test.dart
// Tests for the mock waveform API.
//
// 2026 September 28
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_wave_viewer/testing.dart';

void main() {
  group('MockSignalWaveformApi', () {
    late MockSignalWaveformApi api;

    setUp(() {
      api = MockSignalWaveformApi();
    });

    test('returns the expected hierarchy and metadata', () async {
      final structure = await api.getModuleStructure();

      expect(structure.metadata.source, 'Source1');
      expect(structure.metadata.timescale, '1ns');
      expect(structure.metadata.date, '2022-01-01');
      expect(structure.modules, hasLength(1));

      final root = structure.modules.single;
      expect(root.name, 'Counter');
      expect(root.signals.map((signal) => signal.name), [
        'Signal1',
        'Signal2',
        'Signal3',
        'Signal4',
      ]);
      expect(root.children.single.name, 'counter_sub_module');
      expect(root.children.single.signals.single.width, 16);
    });

    test('returns only known signals and applies inclusive time bounds',
        () async {
      final waveforms = await api.getWaveformData(
        signalIds: ['Counter.Signal2', 'missing'],
        startTime: 4,
        endTime: 11,
      );

      expect(waveforms, hasLength(1));
      expect(waveforms.single.signalId, 'Counter.Signal2');
      expect(
        waveforms.single.data.map((data) => (data.time, data.value)),
        [(4, '1'), (9, '1'), (10, '0'), (11, '1')],
      );
    });

    test('converts integer samples to strings without time filtering',
        () async {
      final waveforms = await api.getWaveformData(
        signalIds: ['counter_sub_module.SubSignal1'],
      );

      expect(
        waveforms.single.data.map((data) => (data.time, data.value)),
        [(1, '1'), (2, '0'), (3, 'ABCD102'), (4, '1'), (5, '1')],
      );
    });

    test('streams filtered waveform samples in chunks and skips unknown ids',
        () async {
      final chunks = await api.streamWaveformData(
        signalIds: ['Counter.Signal1', 'missing'],
        startTime: 5,
      ).toList();

      expect(chunks, hasLength(2));
      expect(chunks.map((chunk) => chunk.signalId),
          everyElement('Counter.Signal1'));
      expect(
        chunks
            .map((chunk) => chunk.data.map((data) => (data.time, data.value))),
        [
          [(5, '1'), (12, 'ZZZZZ')],
          [(18, '1')],
        ],
      );
    });
  });
}
