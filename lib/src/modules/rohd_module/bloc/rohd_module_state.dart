// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_module_state.dart
// The state for the ROHD module BLoC.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

part of 'rohd_module_bloc.dart';

sealed class RohdModuleState extends Equatable {
  final ModuleStructure moduleStructure;

  const RohdModuleState(this.moduleStructure);

  @override
  List<Object> get props => [moduleStructure];
}

final class Loading extends RohdModuleState {
  const Loading(super.moduleStructure);

  @override
  List<Object> get props => [moduleStructure];
}

final class Rendered extends RohdModuleState {
  final ModuleStructure module;

  const Rendered(this.module) : super(module);

  @override
  List<Object> get props => [module];
}

final class ModuleSelected extends RohdModuleState {
  final Module singleModule;

  const ModuleSelected(super.moduleStructure, this.singleModule);

  @override
  List<Object> get props => [singleModule];
}

final class Error extends RohdModuleState {
  const Error(super.moduleStructure);

  @override
  List<Object> get props => [moduleStructure];
}
