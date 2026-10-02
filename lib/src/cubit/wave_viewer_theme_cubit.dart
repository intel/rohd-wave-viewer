// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// wave_viewer_theme_cubit.dart
// Manages light/dark theme toggle for the wave viewer.
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter_bloc/flutter_bloc.dart';

/// Enum for theme modes.
enum WaveViewerThemeMode {
  /// Light theme mode.
  light,

  /// Dark theme mode.
  dark,
}

/// Cubit for managing wave viewer theme state.
class WaveViewerThemeCubit extends Cubit<WaveViewerThemeMode> {
  /// Creates a theme cubit with an optional initial state.
  WaveViewerThemeCubit([super.initialState = WaveViewerThemeMode.dark]);

  /// Toggle between light and dark themes.
  void toggleTheme() {
    emit(
      state == WaveViewerThemeMode.dark
          ? WaveViewerThemeMode.light
          : WaveViewerThemeMode.dark,
    );
  }

  /// Set a specific theme mode.
  void setTheme(WaveViewerThemeMode mode) {
    emit(mode);
  }
}
