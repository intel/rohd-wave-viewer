// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// waveform_module_event.dart
// The events for the waveform module BLoC.
//
// 2024 April
// Author(s): Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
//            Yao Jing Quek <yao.jing.quek@intel.com>

part of 'waveform_module_bloc.dart';

/// Base class for waveform cursor BLoC events.
sealed class WaveformModuleEvent extends Equatable {
  /// Creates a waveform module event.
  const WaveformModuleEvent();
}

/// Updates the waveform cursor to the tapped time.
final class WaveformModuleOnTap extends WaveformModuleEvent {
  /// The tapped cursor time in picoseconds.
  final int timePs;

  /// Creates a waveform tap event.
  const WaveformModuleOnTap(this.timePs);

  @override
  List<Object> get props => [timePs];
}

/// Resets waveform cursor state.
final class WaveformModuleReset extends WaveformModuleEvent {
  /// Creates a waveform reset event.
  const WaveformModuleReset();

  @override
  List<Object> get props => [];
}
