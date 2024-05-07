// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_module_event.dart
// The events for the ROHD module BLoC.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

part of 'rohd_module_bloc.dart';

sealed class RohdModuleEvent extends Equatable {
  const RohdModuleEvent();
}

final class RohdModuleInit extends RohdModuleEvent {
  @override
  List<Object> get props => [];
}

final class RohdModuleRequest extends RohdModuleEvent {
  @override
  List<Object> get props => [];
}

final class RohdModuleSelect extends RohdModuleEvent {
  final Module selectedModule;
  final ModuleStructure moduleStructure;

  const RohdModuleSelect(this.moduleStructure, this.selectedModule);

  @override
  List<Object> get props => [];
}
