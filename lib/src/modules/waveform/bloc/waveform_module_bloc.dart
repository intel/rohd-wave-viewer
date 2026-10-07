// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// waveform_module_bloc.dart
// The BLoC for the Waveform Module.
//
// 2024 April
// Author(s): Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
//            Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';

part 'waveform_module_event.dart';
part 'waveform_module_state.dart';

/// BLoC that tracks the active waveform cursor position.
class WaveformModuleBloc
    extends Bloc<WaveformModuleEvent, WaveformModuleState> {
  /// Creates a waveform module BLoC.
  WaveformModuleBloc({required this.signalWaveformRepository})
      : super(const InitialCursor()) {
    on<WaveformModuleOnTap>(addWaveformCursor);
    on<WaveformModuleReset>(resetCursor);
  }

  /// Repository used by waveform-related interactions.
  final SignalWaveformRepository signalWaveformRepository;

  /// Updates the cursor state after a waveform tap.
  Future<void> addWaveformCursor(
    WaveformModuleOnTap event,
    Emitter<WaveformModuleState> emit,
  ) async {
    try {
      emit(UpdatedCursor(event.timePs));
    } on Object catch (_) {
      emit(const WaveformModuleError());
    }
  }

  /// Resets the cursor to its initial state.
  Future<void> resetCursor(
    WaveformModuleReset event,
    Emitter<WaveformModuleState> emit,
  ) async {
    emit(const InitialCursor());
  }
}
