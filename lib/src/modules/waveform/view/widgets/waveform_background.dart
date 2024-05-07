// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// waveform_background.dart
// The waveform background widget.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rohd_wave_viewer/src/const/const.dart';
import 'package:rohd_wave_viewer/src/modules/shared/widgets/panel_header.dart';
import 'package:rohd_wave_viewer/src/modules/shared/widgets/signal_tab_container.dart';
import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/bloc/waveform_module_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/view/widgets/cursor.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/view/widgets/painters/waveform_hexavalue.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/view/widgets/timescale.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/view/widgets/painters/waveform_binary.dart';
import 'package:module_structure_api/module_structure_api.dart';

enum SignalType { binary, hexadecimal }

class WaveformBackground extends StatelessWidget {
  final int timescale;

  const WaveformBackground({super.key, required this.timescale});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Container(
              padding: const EdgeInsets.all(20),
              height: 200,
              child: const TimescaleWidget(
                zoomLevel: 10,
                finalTime: 20,
              ),
            ),
          ),
          Positioned.fill(
            child: BlocBuilder<WaveformModuleBloc, WaveformModuleState>(
              builder: (context, state) {
                return CursorWidget(state.pos);
              },
            ),
          ),
          BlocBuilder<SignalBloc, SignalState>(builder: (content, state) {
            return switch (state) {
              SignalLoading() => const Column(children: [
                  PanelHeader(headerText: ''),
                ]),
              SignalLoaded() => GestureDetector(
                  onTapDown: (TapDownDetails tapDownDetails) {
                    final positionClicked =
                        getPosition(content, tapDownDetails);
                    context
                        .read<WaveformModuleBloc>()
                        .add(WaveformModuleOnTap(positionClicked));
                  },
                  child: ListView(
                    children: [
                      const PanelHeader(headerText: ''),
                      ..._preprocessWaveform(state.monitorSignalsList),
                      const SignalTabContainer(
                        containerBody: Text(''),
                      )
                    ],
                  ),
                ),
            };
          }),
        ],
      ),
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

  Offset getPosition(BuildContext context, TapDownDetails details) {
    final RenderBox box = context.findRenderObject() as RenderBox;
    final Offset localOffset = box.globalToLocal(details.globalPosition);

    final adjustedOffset = Offset(
        localOffset.dx - waveformPadding, localOffset.dx - waveformPadding);

    // 1.Get the width of the total canvas
    if (kDebugMode) {
      print(MediaQuery.of(context).size.width);
    }

    // 2. divide by timescale
    return adjustedOffset;
  }

  List<Widget> _preprocessWaveform(List<Signal> signals) {
    return signals.map((signal) {
      SignalType sigType;
      if (signal.type == 'hex') {
        sigType = SignalType.hexadecimal;
      } else {
        sigType = SignalType.binary;
      }
      return drawWaveform(signal.data, sigType);
    }).toList();
  }

  Widget drawWaveform(List<Data> data, SignalType sigType) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SignalTabContainer(
        showBorder: true,
        borderColor: Colors.transparent,
        containerBody: CustomPaint(
          size: const Size(30, 20),
          painter: sigType == SignalType.hexadecimal
              ? WaveformHexaValue(data, timescale)
              : WaveformBinary(data, timescale),
        ),
      ),
    );
  }
}
