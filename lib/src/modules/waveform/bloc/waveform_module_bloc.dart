// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// waveform_module_bloc.dart
// The BLoC for the Waveform Module.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:module_structure_repository/module_structure_repository.dart';

part 'waveform_module_event.dart';
part 'waveform_module_state.dart';

class WaveformModuleBloc
    extends Bloc<WaveformModuleEvent, WaveformModuleState> {
  WaveformModuleBloc({
    required this.moduleStructureRepository,
  }) : super(const InitialCursor()) {
    on<WaveformModuleOnTap>(addWaveformCursor);
  }

  final ModuleStructureRepository moduleStructureRepository;

  Future<void> addWaveformCursor(
    WaveformModuleOnTap event,
    Emitter<WaveformModuleState> emit,
  ) async {
    try {
      emit(UpdatedCursor(newPos: event.pos));
    } catch (e) {
      emit(const Error());
    }
  }
}
