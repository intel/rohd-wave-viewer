// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// main_io.dart
// Native platform (IO) initialization for ROHD Wave Viewer.
//
// 2026 January 03
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:io';

import 'package:dart_wellen/dart_wellen.dart' hide SignalWaveform;
import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';

/// Initializes the waveform API for native platforms.
///
/// [environment] overrides the process environment for startup integrations
/// and deterministic tests.
Future<SignalWaveformApi> initializeSignalWaveformApi(
  List<String> args, {
  Map<String, String>? environment,
}) async {
  if (args.isNotEmpty) {
    // First argument is assumed to be a waveform file path
    final filePath = args[0];
    final file = File(filePath);

    if (!file.existsSync()) {
      stderr
        ..writeln('Error: File not found: $filePath')
        ..writeln('Usage: rohd_wave_viewer [path/to/waveform.vcd]');
      exit(1);
    }

    final wellenApi = WellenSignalWaveformApi();

    try {
      await wellenApi.loadFile(filePath);
      return wellenApi;
    } on Object catch (e, stackTrace) {
      stderr
        ..writeln('Error loading waveform: $e')
        ..writeln(stackTrace);
      exit(1);
    }
  } else {
    // No CLI args — allow environment variable fallback for desktop debug runs
    final envPath = (environment ?? Platform.environment)['ROHD_WAVE_VCD'];
    if (envPath != null && envPath.isNotEmpty) {
      final file = File(envPath);
      if (file.existsSync()) {
        final wellenApi = WellenSignalWaveformApi();
        try {
          await wellenApi.loadFile(envPath);
          return wellenApi;
        } on Object catch (e, stackTrace) {
          stderr
            ..writeln('Error loading waveform from env: $e')
            ..writeln(stackTrace);
          exit(1);
        }
      }
    }
  }

  return WellenSignalWaveformApi();
}
