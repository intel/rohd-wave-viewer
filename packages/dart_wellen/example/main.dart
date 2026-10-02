// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// main.dart
// Reads waveform metadata from a VCD, FST, or GHW file.
//
// 2026 September 28
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:dart_wellen/dart_wellen.dart';

/// Prints metadata for the waveform path passed on the command line.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    throw ArgumentError('Usage: dart run example/main.dart <waveform-file>');
  }

  await WellenReader.init();
  final reader = WellenReader();
  try {
    final metadata = await reader.loadFile(arguments.single);
    print('Source: ${metadata.source}');
    print('Timescale: ${metadata.timescale}');
    print('Format: ${metadata.format}');
  } finally {
    await reader.close();
  }
}
