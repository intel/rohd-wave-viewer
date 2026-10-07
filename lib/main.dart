// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// main.dart
// The main entry point for ROHD Wave Viewer.
//
// 2024 April
// Author(s): Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
//            Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:devtools_app_shared/ui.dart';
import 'package:devtools_app_shared/utils.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:rohd_wave_viewer/embedded_wave_viewer.dart';
import 'package:rohd_wave_viewer/main_io.dart'
    if (dart.library.js_interop) 'main_web.dart' as platform;
import 'package:rohd_wave_viewer/src/const/app_version.dart';
import 'package:rohd_wave_viewer/src/platform/platform.dart' as plat;
import 'package:rohd_waveform/rohd_waveform.dart' show SignalWaveformApi;

// Use platform facade for setUrlStrategy so implementations are selected
// centrally

// Conditional import for dart:io (only available on non-web platforms)

void main(List<String> args) async {
  // Disable URL strategies on web to avoid replaceState errors in webviews
  if (kIsWeb) {
    plat.setUrlStrategySafe(null);
  }

  WidgetsFlutterBinding.ensureInitialized();
  await initAppVersion();
  setGlobal(IdeTheme, getIdeTheme());

  // Create the appropriate SignalWaveformApi based on platform
  SignalWaveformApi? signalWaveformApi;

  if (kIsWeb) {
    // Web extension entry points supply their API after host initialization.
    signalWaveformApi = null;
  } else {
    // On native platforms, use the platform-specific initialization
    signalWaveformApi = await platform.initializeSignalWaveformApi(args);
  }

  runApp(
    EmbeddedWaveViewer(waveformApi: signalWaveformApi),
  );
}
