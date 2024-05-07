// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// home.dart
// The home page for the waveform viewer.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:rohd_wave_viewer/src/const/locales.dart';
import 'package:rohd_wave_viewer/src/modules/rohd_module/rohd_module.dart';
import 'package:rohd_wave_viewer/src/modules/shared/widgets/panel_decoration.dart';
import 'package:rohd_wave_viewer/src/modules/shared/widgets/panel_header.dart';
import 'package:rohd_wave_viewer/src/modules/signal/view/selected_signal_panel.dart';
import 'package:rohd_wave_viewer/src/modules/signal/view/signal_panel.dart';
import 'package:rohd_wave_viewer/src/modules/signal/view/signal_value_panel.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/view/waveform_panel.dart';

class WaveFormViewerPage extends StatelessWidget {
  const WaveFormViewerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final bodyHeight = MediaQuery.of(context).size.height - 80;

    return Split(
      axis: Axis.horizontal,
      initialFractions: const [0.14, 0.13, 0.13, 0.6],
      minSizes: const [200, 150, 50, 600],
      children: [
        const ModuleSignalPanel(),
        Container(
          decoration: panelDecoration(),
          height: bodyHeight,
          child: ListView(children: const [SelectedSignalsPanel()]),
        ),
        // Add signal value panel here
        Container(
          decoration: panelDecoration(),
          height: bodyHeight,
          child: ListView(
            children: const [SignalValuePanel()],
          ),
        ),
        Container(
          decoration: panelDecoration(),
          height: bodyHeight,
          child: ListView(children: const [WaveformPanel()]),
        ),
      ],
    );
  }
}

class ModuleSignalPanel extends StatelessWidget {
  const ModuleSignalPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final bodyHeight = MediaQuery.of(context).size.height / 2 - 80;
    return Split(
      axis: Axis.vertical,
      initialFractions: const [0.5, 0.5],
      children: [
        Container(
          decoration: panelDecoration(),
          height: bodyHeight,
          child: ListView(
            children: const [
              Center(child: PanelHeader(headerText: modulePanelTitle)),
              RohdModulePanel(),
            ],
          ),
        ),
        Container(
          decoration: panelDecoration(),
          height: bodyHeight,
          child: ListView(
            children: const [
              Center(child: PanelHeader(headerText: 'Module Signals')),
              SignalPanel(),
            ],
          ),
        ),
      ],
    );
  }
}
