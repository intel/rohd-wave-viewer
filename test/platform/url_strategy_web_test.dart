// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// url_strategy_web_test.dart
// Tests for browser URL strategy configuration.
//
// 2026 October
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

@TestOn('browser')
library;

import 'package:flutter_web_plugins/url_strategy.dart' as flutter_web;
import 'package:rohd_wave_viewer/src/platform/platform.dart' as platform;
import 'package:test/test.dart';

void main() {
  test('disables browser history in Wasm builds', () {
    platform.setUrlStrategySafe(null);

    expect(flutter_web.urlStrategy, isNull);
  });
}
