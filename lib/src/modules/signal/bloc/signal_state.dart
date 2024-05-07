// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_state.dart
// The state for the Signal BLoC.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

part of 'signal_bloc.dart';

sealed class SignalState extends Equatable {
  final List<Signal> signals;
  final List<Signal> monitorSignalsList;

  const SignalState(this.signals, this.monitorSignalsList);

  @override
  List<Object> get props => [monitorSignalsList, signals];
}

final class SignalLoading extends SignalState {
  SignalLoading() : super([], []);
}

final class SignalLoaded extends SignalState {
  const SignalLoaded(super.signals, super.monitorSignalsList);
}
