// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_tab_container.dart
// The container for the signal tab.
//
// 2024 April
// Author(s): Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
//            Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_wave_viewer/src/cubit/waveform_scale_cubit.dart';

/// Container widget used for signal rows aligned with waveform rows.
class SignalTabContainer extends StatelessWidget {
  final Widget _containerBody;
  final bool _showBorder;
  final Color _borderColor;

  /// Creates a signal tab container.
  const SignalTabContainer({
    required Widget containerBody,
    super.key,
    bool showBorder = false,
    Color borderColor = Colors.transparent,
  })  : _containerBody = containerBody,
        _showBorder = showBorder,
        _borderColor = borderColor;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.centerLeft,
        decoration: _showBorder
            ? BoxDecoration(border: Border.all(color: _borderColor))
            : null,
        width: double.infinity,
        height: context
            .watch<WaveformScaleCubit>()
            .scaledRowHeight, // Scaled height to match waveform rows
        child: _containerBody,
      );
}
