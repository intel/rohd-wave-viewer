// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_wave_viewer.dart
// Main barrel file for the ROHD Wave Viewer package.
//
// 2026 January 12
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

// Dartdoc uses this name to select the package's public library.
// ignore_for_file: unnecessary_library_name

/// Public API for embedding the ROHD Wave Viewer.
library rohd_wave_viewer;

export 'embedded_wave_viewer.dart' show EmbeddedWaveViewer;
export 'src/cubit/wave_viewer_theme_cubit.dart' show WaveViewerThemeMode;
export 'src/modules/shared/widgets/wave_viewer_help_button.dart'
    show WaveViewerHelpButton;
