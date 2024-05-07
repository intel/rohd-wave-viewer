// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// waveform_module_state.dart
// The states for the waveform module BLoC.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

part of 'waveform_module_bloc.dart';

sealed class WaveformModuleState extends Equatable {
  final Offset pos;

  const WaveformModuleState(this.pos);

  @override
  List<Object> get props => [pos];
}

final class InitialCursor extends WaveformModuleState {
  final initialPos = const Offset(0, 0);

  const InitialCursor() : super(const Offset(0, 0));

  @override
  List<Object> get props => [initialPos];
}

final class UpdatedCursor extends WaveformModuleState {
  final Offset newPos;

  const UpdatedCursor({required this.newPos}) : super(newPos);

  @override
  List<Object> get props => [newPos];
}

final class Error extends WaveformModuleState {
  const Error() : super(const Offset(0, 0));

  @override
  List<Object> get props => [];
}
