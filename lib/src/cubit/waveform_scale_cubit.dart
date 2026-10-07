// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// waveform_scale_cubit.dart
// Manages the vertical scale factor for waveform rows.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rohd_wave_viewer/src/const/layout.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/view/widgets/painters/waveform.dart';

/// Cubit managing the vertical scale factor for waveform signal rows.
///
/// The scale factor is applied uniformly to row heights, fonts, and
/// related spacing so that all panels (selected signals, values, and
/// waveforms) remain aligned.
class WaveformScaleCubit extends Cubit<double> {
  /// Creates a waveform scale cubit with an optional initial state.
  WaveformScaleCubit([super.initialState = 1.0]);

  /// The multiplicative step for each scale increment/decrement (10%).
  static const double _step = 0.1;

  /// Minimum scale factor.
  static const double minScale = 0.5;

  /// Maximum scale factor.
  static const double maxScale = 3;

  /// The current scaled signal row height.
  double get scaledRowHeight => baseSignalRowHeight * state;

  /// Increase the scale by 10%.
  void scaleUp() {
    final next = (state + _step).clamp(minScale, maxScale);
    if (next != state) {
      Waveform.clearCaches();
      emit(double.parse(next.toStringAsFixed(2)));
    }
  }

  /// Decrease the scale by 10%.
  void scaleDown() {
    final next = (state - _step).clamp(minScale, maxScale);
    if (next != state) {
      Waveform.clearCaches();
      emit(double.parse(next.toStringAsFixed(2)));
    }
  }

  /// Reset to default scale.
  void resetScale() {
    if (state != 1.0) {
      Waveform.clearCaches();
      emit(1);
    }
  }

  /// Restores a persisted scale, clamped to the supported range.
  void setScale(double scale) {
    final next = double.parse(
      scale.clamp(minScale, maxScale).toStringAsFixed(2),
    );
    if (next != state) {
      Waveform.clearCaches();
      emit(next);
    }
  }
}
