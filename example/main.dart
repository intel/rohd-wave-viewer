// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// main.dart
// Example of embedding the ROHD Wave Viewer in a Flutter application.
//
// 2026 September 28
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

/// Runs an application containing an embedded ROHD Wave Viewer.
library;

import 'package:material_ui/material_ui.dart';
import 'package:rohd_wave_viewer/rohd_wave_viewer.dart';
import 'package:rohd_wave_viewer/testing.dart';

/// Runs the embedding example with deterministic sample waveform data.
void main() {
  runApp(
    EmbeddedWaveViewer(
      waveformApi: MockSignalWaveformApi(),
      title: 'Embedded ROHD Wave Viewer',
      isExtensionMode: true,
    ),
  );
}
