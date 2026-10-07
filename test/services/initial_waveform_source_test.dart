// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// initial_waveform_source_test.dart
// Tests for startup waveform source parsing.
//
// 2026 October
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_wave_viewer/src/services/initial_waveform_source.dart';

void main() {
  test('reads and decodes the waveFormFile query parameter', () {
    final source = waveformSourceFromUri(
      Uri.parse(
        'https://viewer.example/?waveFormFile='
        'https%3A%2F%2Ffiles.example%2Ffilter_bank.fst%3Fdownload%3D1',
      ),
    );

    expect(
      source,
      'https://files.example/filter_bank.fst?download=1',
    );
  });

  test('ignores missing, empty, and differently cased parameters', () {
    expect(waveformSourceFromUri(Uri.parse('https://viewer.example/')), isNull);
    expect(
      waveformSourceFromUri(
        Uri.parse('https://viewer.example/?waveFormFile=%20'),
      ),
      isNull,
    );
    expect(
      waveformSourceFromUri(
        Uri.parse('https://viewer.example/?waveformFile=trace.fst'),
      ),
      isNull,
    );
  });

  test('recognizes Flutter assets and extracts display file names', () {
    expect(
      isFlutterAssetSource('assets/waveforms/filter_bank.fst'),
      isTrue,
    );
    expect(
      isFlutterAssetSource(
        'packages/rohd_wave_viewer/assets/waveforms/filter_bank.fst',
      ),
      isTrue,
    );
    expect(
      isFlutterAssetSource('https://files.example/filter_bank.fst'),
      isFalse,
    );
    expect(
      waveformFileNameFromSource(
        'https://files.example/waves/design%20run.fst?download=1',
      ),
      'design run.fst',
    );
  });

  test('reads repeated and comma-separated nested signal paths in order', () {
    final paths = signalPathsFromUri(
      Uri.parse(
        'https://viewer.example/?'
        'signalList=FilterBank%2Fsample1%2CFilterBank%2Fch0%2FdataOut'
        '&signalList=FilterBank%2Fch1%2FdataOut'
        '&signalList=%20',
      ),
    );

    expect(paths, [
      'FilterBank/sample1',
      'FilterBank/ch0/dataOut',
      'FilterBank/ch1/dataOut',
    ]);
  });
}
