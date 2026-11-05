// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// monitor_row_test.dart
// Tests viewer-owned monitor rows backed by shared waveform models.
//
// 2026 November
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';
import 'package:test/test.dart';

void main() {
  test('duplicate rows have independent identities, data, and presentation',
      () {
    final cached = SignalWaveform(
      signalId: 'top/data',
      data: [Data(time: 0, value: '0')],
      overrideWidth: 8,
    );
    final first = MonitorRow.fromWaveform(cached)
      ..monitorGroup = 'inputs'
      ..valueFormat = MonitorValueFormat.binary;
    final second = MonitorRow.fromWaveform(cached)
      ..monitorGroup = 'outputs'
      ..valueFormat = MonitorValueFormat.hexadecimal;

    expect(first.monitorId, isNot(second.monitorId));
    expect(first.waveform, isA<SignalWaveform>());
    expect(first.waveform, isNot(same(cached)));
    cached.appendData([Data(time: 5, value: '1')]);
    first.waveform.appendData([Data(time: 10, value: '2')]);
    expect(second.data.map((point) => point.time), [0]);
    expect(first.data.map((point) => point.time), [0, 10]);
    expect(first.monitorGroup, 'inputs');
    expect(second.monitorGroup, 'outputs');
    expect(first.valueFormat, MonitorValueFormat.binary);
    expect(second.valueFormat, MonitorValueFormat.hexadecimal);
  });

  test('row copies preserve presentation and snapshot their waveform', () {
    final original = MonitorRow(
      signalId: 'top/data#b[7:4]',
      monitorId: 'row-1',
      monitorParentId: 'parent',
      monitorGroup: 'bus',
      valueFormat: MonitorValueFormat.binary,
      overrideName: 'data[7:4]',
      overrideWidth: 4,
      data: [Data(time: 0, value: '0')],
      isComputed: true,
    );
    final copy = MonitorRow.copyFrom(original, monitorId: original.monitorId);
    copy.waveform.appendData([Data(time: 1, value: '1')]);

    expect(copy.monitorId, 'row-1');
    expect(copy.monitorParentId, 'parent');
    expect(copy.monitorGroup, 'bus');
    expect(copy.valueFormat, MonitorValueFormat.binary);
    expect(copy.overrideName, 'data[7:4]');
    expect(copy.overrideWidth, 4);
    expect(copy.isComputed, isTrue);
    expect(original.data, hasLength(1));
    expect(copy.data, hasLength(2));
  });

  test('transfer payload rows retain their signal identity by default', () {
    final row = MonitorRow.fromWaveformData(
      WaveformData(signalId: 'top/data', data: [Data(time: 0, value: '1')]),
    );

    expect(row.monitorId, 'top/data');
    expect(row.getValueByTime(0), '1');
  });
}
