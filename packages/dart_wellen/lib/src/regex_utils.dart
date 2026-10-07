// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// regex_utils.dart
// Regular-expression compatibility helpers for native and web platforms.
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

// ignore_for_file: deprecated_member_use, unnecessary_ignore

Pattern regExpPattern(
  String source, {
  bool multiLine = false,
  bool caseSensitive = true,
  bool unicode = false,
  bool dotAll = false,
}) =>
    RegExp(
      source,
      multiLine: multiLine,
      caseSensitive: caseSensitive,
      unicode: unicode,
      dotAll: dotAll,
    );

Match? regExpFirstMatch(
  String source,
  String input, {
  bool multiLine = false,
  bool caseSensitive = true,
  bool unicode = false,
  bool dotAll = false,
}) =>
    RegExp(
      source,
      multiLine: multiLine,
      caseSensitive: caseSensitive,
      unicode: unicode,
      dotAll: dotAll,
    ).firstMatch(input);
