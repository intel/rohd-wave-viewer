// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// flutter_test_runner_guard.dart
// Directs root-package tests to the Flutter test runner.
//
// 2026 November 05
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:test/test.dart';

void main() {
  test('Use the Flutter test runner for the root package', () {
    fail(
      'This is a Flutter package; dart test cannot run its Flutter tests.\n'
      'Run `flutter test` for the root package or `make test` for the '
      'whole workspace.',
    );
  });
}
