// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_value_panel.dart
// The signal value panel.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rohd_wave_viewer/src/const/const.dart';
import 'package:rohd_wave_viewer/src/modules/shared/widgets/panel_header.dart';
import 'package:rohd_wave_viewer/src/modules/shared/widgets/signal_tab_container.dart';
import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/bloc/waveform_module_bloc.dart';

class SignalValuePanel extends StatelessWidget {
  const SignalValuePanel({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WaveformModuleBloc, WaveformModuleState>(
      builder: (context, state) {
        return switch (state) {
          InitialCursor() => const Column(
              children: [
                PanelHeader(headerText: signalsValuePanelTitle),
                SignalTabContainer(containerBody: Text('')),
              ],
            ),
          UpdatedCursor() => updateSignalValue(context, state),
          Error() => const Text(bugReport),
        };
      },
    );
  }

  Widget updateSignalValue(BuildContext context, WaveformModuleState state) {
    final signalBloc = BlocProvider.of<SignalBloc>(context);
    final monitorSignalList = signalBloc.state.monitorSignalsList;

    final valueList = [];

    for (final signal in monitorSignalList) {
      final scaleTime = adjustPropotion(context, state.pos).dx.toInt();
      final val = signal.getValueByTime(scaleTime);
      valueList.add(val);
    }

    return Column(
      children: [
        const PanelHeader(headerText: signalsValuePanelTitle),
        ...valueList.map(
          (value) {
            return SignalTabContainer(containerBody: Text(value));
          },
        ),
      ],
    );
  }

  Offset adjustPropotion(BuildContext context, Offset adjustedOffset) {
    // 1. Get the width of the total canvas
    double canvasWidth = MediaQuery.of(context).size.width;

    // 2. Define the maximum scale value
    double maxScaleValue = 20.0;

    // 3. Calculate the ratio
    double ratio = maxScaleValue / canvasWidth;

    // 4. Adjust the offset based on the ratio
    Offset scaledOffset =
        Offset(adjustedOffset.dx * ratio, adjustedOffset.dy * ratio);

    return scaledOffset;
  }
}
