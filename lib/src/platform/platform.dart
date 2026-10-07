// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// platform.dart
// Facade for platform-specific implementations.
// Consumers should import this file to get platform helpers.
//
// 2024 April
// Author(s): Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
//            Max Korbel <max.korbel@intel.com>

export 'platform_io.dart' if (dart.library.html) 'platform_web.dart';
