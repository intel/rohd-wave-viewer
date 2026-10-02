// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// dart_wellen_io.dart
// IO-specific exports for dart_wellen (not available on web).
// These classes use dart:io for file operations.
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

// Dartdoc uses this name to select the package's public IO library.
// ignore_for_file: unnecessary_library_name

/// IO-specific wellen exports for native platforms.
///
/// Import this separately when you need waveform writing capabilities:
/// ```dart
/// import 'package:dart_wellen/dart_wellen.dart'; // Core reading
/// import 'package:dart_wellen/dart_wellen_io.dart'; // Writing (native only)
/// ```
library dart_wellen_io;

export 'src/wellen_wave_dumper.dart';
export 'src/wellen_writer.dart';
