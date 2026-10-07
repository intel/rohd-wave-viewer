// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// platform_io_test.dart
// Tests for native platform byte fetching.
//
// 2026 October
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:io';

import 'package:rohd_wave_viewer/src/platform/platform_io.dart';
import 'package:test/test.dart';

void main() {
  test('fetchBytes loads waveform bytes from an HTTP URL', () async {
    final expected = File(
      'assets/waveforms/filter_bank.fst',
    ).readAsBytesSync();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.add(expected);
      await request.response.close();
    });

    final actual = await fetchBytes(
      'http://${server.address.address}:${server.port}/filter_bank.fst',
    );

    expect(actual, expected);
  });
}
