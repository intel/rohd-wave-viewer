// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_event.dart
// The events for the Signal BLoC.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

part of 'signal_bloc.dart';

sealed class SignalEvent extends Equatable {}

class SignalUpdateEvent extends SignalEvent {
  final Module selectedModule;

  SignalUpdateEvent(this.selectedModule);

  @override
  List<Object?> get props => [selectedModule];
}

class SignalSelectedEvent extends SignalEvent {
  final Signal selectedSignal;
  SignalSelectedEvent(this.selectedSignal);

  @override
  List<Object?> get props => [selectedSignal];
}
