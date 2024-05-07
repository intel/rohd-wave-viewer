// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// selected_signal_panel.dart
// The selected signals panel.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rohd_wave_viewer/src/const/locales.dart';
import 'package:rohd_wave_viewer/src/modules/shared/widgets/signal_tab_container.dart';
import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/shared/widgets/panel_header.dart';

class SelectedSignalsPanel extends StatelessWidget {
  const SelectedSignalsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SignalBloc, SignalState>(builder: (content, state) {
      return switch (state) {
        SignalLoading() => const Column(
            children: [
              PanelHeader(headerText: selectedSignalsPanelTitle),
            ],
          ),
        SignalLoaded() => Column(
            children: [
              const PanelHeader(headerText: selectedSignalsPanelTitle),
              ...state.monitorSignalsList.map(
                (signal) => MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    child: SignalTabContainer(
                      showBorder: true,
                      containerBody: Text(signal.name),
                    ),
                  ),
                ),
              ),
              const SignalTabContainer(containerBody: Text('')),
            ],
          ),
      };
    });
  }
}
