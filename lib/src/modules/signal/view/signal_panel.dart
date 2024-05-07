// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_panel.dart
// The signal panel.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/shared/widgets/signal_tab_container.dart';
import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';
import 'package:module_structure_api/module_structure_api.dart';

class SignalPanel extends StatelessWidget {
  const SignalPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SignalBloc, SignalState>(builder: (content, state) {
      if (state is SignalLoading) {
        return const Text('');
      } else if (state is SignalLoaded) {
        return SignalList(signals: state.signals);
      } else {
        return Container();
      }
    });
  }
}

class SignalList extends StatelessWidget {
  final List<Signal> signals;
  const SignalList({super.key, required this.signals});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: signals
          .map(
            (signal) => Padding(
              padding: const EdgeInsets.only(top: 5, left: 10),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onDoubleTap: () {
                    context.read<SignalBloc>().add(
                          SignalSelectedEvent(signal),
                        );
                  },
                  child: SignalTabContainer(
                    containerBody: Text(signal.name),
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}
