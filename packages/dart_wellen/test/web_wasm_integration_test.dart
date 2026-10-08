// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// web_wasm_integration_test.dart
// Web/WASM integration tests for Wellen via WellenSignalWaveformApi
//
// 2026 January 03
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

@TestOn('browser')
library;

// Web/WASM integration tests for Wellen via WellenSignalWaveformApi
import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:dart_wellen/dart_wellen.dart';
import 'package:dart_wellen/src/external_library_io.dart'
    if (dart.library.js_interop) 'package:dart_wellen/src/external_library_web.dart'
    as platform;

void main() {
  setUpAll(() async {
    await platform.waitForWasmInit();
    await WellenSignalWaveformApi.init();
  });

  test('loads inline VCD bytes through the browser bridge', () async {
    const vcd = r'''
$date today $end
$version dart_wellen test $end
$timescale 1ns $end
$scope module top $end
$var wire 1 ! clk $end
$upscope $end
$enddefinitions $end
#0
0!
#1
1!
''';
    final api = WellenSignalWaveformApi();
    await api.loadBytes(utf8.encode(vcd), fileName: 'inline.vcd');

    expect((await api.getModuleStructureOnly()).modules.single.name, 'top');
  });

  test('loads tracked VCD values through the browser WASM bridge', () async {
    final bytes =
        await platform.fetchBytes('fixtures/xz_transitions.vcd').timeout(
              const Duration(seconds: 10),
              onTimeout: () => throw TimeoutException('fetching VCD fixture'),
            );
    final api = WellenSignalWaveformApi();
    await api.loadBytes(bytes.toList(), fileName: 'xz_transitions.vcd').timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw TimeoutException('loading VCD bytes'),
        );

    final structure = await api.getModuleStructureOnly().timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw TimeoutException('reading VCD hierarchy'),
        );
    expect(structure.modules.single.name, 'test');

    final binXzId = structure.allSignalIds.singleWhere(
      (signalId) => signalId.endsWith('/bin_xz'),
    );
    final data8Id = structure.allSignalIds.singleWhere(
      (signalId) => signalId.endsWith('/data8'),
    );
    final waveforms = await api.getWaveformData(
      signalIds: [binXzId, data8Id],
    ).timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException('reading VCD values'),
    );
    final valuesById = {
      for (final waveform in waveforms)
        waveform.signalId: [
          for (final datum in waveform.data) (datum.time, datum.value),
        ],
    };

    expect(
      valuesById[binXzId],
      containsAll([
        (0, 'x'),
        (80000, '1'),
        (90000, 'z'),
        (120000, '0'),
      ]),
    );
    expect(
      valuesById[data8Id],
      containsAll([
        (0, 'xxxxxxxx'),
        (80000, '00001111'),
        (90000, 'zzzzzzzz'),
        (140000, '10101010'),
      ]),
    );
  });
}
