// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// helpers.dart
// Helpers for testing.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rohd_wave_viewer/src/cubit/wave_viewer_theme_cubit.dart';
import 'package:rohd_wave_viewer/src/cubit/waveform_scale_cubit.dart';
import 'package:rohd_wave_viewer/src/modules/rohd_module/bloc/rohd_module_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/bloc/waveform_module_bloc.dart';
import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';

// reference: https://github.com/felangel/bloc/blob/master/examples/flutter_shopping_cart/test/helper.dart
class MockRohdModuleBloc extends MockBloc<RohdModuleEvent, RohdModuleState>
    implements RohdModuleBloc {}

class MockSignalBloc extends MockBloc<SignalEvent, SignalState>
    implements SignalBloc {}

class MockSignalWaveformRepository extends Mock
    implements SignalWaveformRepository {}

class MockWaveformModuleBloc extends Mock implements WaveformModuleBloc {}

extension PumpApp on WidgetTester {
  Future<void> pumpApp({
    required Widget child,
    RohdModuleBloc? rohdModuleBloc,
    SignalBloc? signalBloc,
    WaveformModuleBloc? waveformModuleBloc,
    WaveViewerThemeCubit? themeCubit,
    WaveformScaleCubit? scaleCubit,
  }) =>
      pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiBlocProvider(
              providers: [
                BlocProvider<WaveViewerThemeCubit>(
                  create: (_) => themeCubit ?? WaveViewerThemeCubit(),
                ),
                BlocProvider<WaveformScaleCubit>(
                  create: (_) => scaleCubit ?? WaveformScaleCubit(),
                ),
                if (rohdModuleBloc != null)
                  BlocProvider.value(value: rohdModuleBloc)
                else
                  BlocProvider(create: (_) => MockRohdModuleBloc()),
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
        ),
      );
}
