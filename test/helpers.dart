// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// helpers.dart
// Helpers for testing.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:module_structure_repository/module_structure_repository.dart';
import 'package:rohd_wave_viewer/src/modules/rohd_module/bloc/rohd_module_bloc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/bloc/waveform_module_bloc.dart';

// reference: https://github.com/felangel/bloc/blob/master/examples/flutter_shopping_cart/test/helper.dart
class MockRohdModuleBloc extends MockBloc<RohdModuleEvent, RohdModuleState>
    implements RohdModuleBloc {}

class MockSignalBloc extends MockBloc<SignalEvent, SignalState>
    implements SignalBloc {}

class MockModuleStructureRepository extends Mock
    implements ModuleStructureRepository {}

class MockWaveformModuleBloc extends Mock implements WaveformModuleBloc {}

extension PumpApp on WidgetTester {
  Future<void> pumpApp({
    required Widget child,
    RohdModuleBloc? rohdModuleBloc,
    SignalBloc? signalBloc,
    WaveformModuleBloc? waveformModuleBloc,
  }) {
    return pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            if (rohdModuleBloc != null)
              BlocProvider.value(value: rohdModuleBloc)
            else
              BlocProvider(
                create: (_) => MockRohdModuleBloc(),
              ),
            if (signalBloc != null)
              BlocProvider.value(value: signalBloc)
            else
              BlocProvider(create: (_) => MockSignalBloc()),
            if (waveformModuleBloc != null)
              BlocProvider.value(value: waveformModuleBloc)
            else
              BlocProvider(create: (_) => MockWaveformModuleBloc()),
          ],
          child: child,
        ),
      ),
    );
  }
}
