// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// waveform_module_state.dart
// The states for the waveform module BLoC.
//
// 2024 April
// Author(s): Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
//            Yao Jing Quek <yao.jing.quek@intel.com>

part of 'waveform_module_bloc.dart';

/// Base class for waveform cursor BLoC states.
sealed class WaveformModuleState extends Equatable {
  /// Current cursor time in picoseconds.
  final int timePs;

  /// Creates a waveform module state.
  const WaveformModuleState(this.timePs);

  @override
  List<Object> get props => [timePs];
}

/// Initial waveform state with no cursor selection.
final class InitialCursor extends WaveformModuleState {
  /// Creates the initial cursor state.
  const InitialCursor() : super(-1);
}

/// State emitted when the cursor moves to a concrete time.
final class UpdatedCursor extends WaveformModuleState {
  /// Creates an updated cursor state.
  const UpdatedCursor(super.timePs);
}

/// State emitted when waveform cursor handling fails.
final class WaveformModuleError extends WaveformModuleState {
  /// Creates an error cursor state.
  const WaveformModuleError() : super(0);
}
