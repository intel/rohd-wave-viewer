// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// app_version.dart
// Application version — read once from platform metadata at startup.
//
// The version is defined in pubspec.yaml and automatically embedded by
// Flutter into each platform's build artifacts.  package_info_plus
// reads it back at runtime so there is only ONE place to update.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:package_info_plus/package_info_plus.dart';

/// Application version string, initialised from pubspec.yaml via
/// [PackageInfo] during [initAppVersion].
///
/// Defaults to `'unknown'` until [initAppVersion] is called.
String appVersion = 'unknown';

/// Call once in `main()` before `runApp()`.
Future<void> initAppVersion() async {
  final info = await PackageInfo.fromPlatform();
  appVersion = info.version;
}
