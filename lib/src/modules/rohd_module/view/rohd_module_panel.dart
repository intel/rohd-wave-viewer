// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_module_panel.dart
// The ROHD module panel.
//
// 2024 April
// Author(s): Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
//            Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_wave_viewer/src/const/const.dart';
import 'package:rohd_wave_viewer/src/modules/rohd_module/bloc/rohd_module_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';

/// Displays the currently selected module name as a compact text label.
///
/// Replaces the former ModuleTree widget. Module Signals now gets the
/// full remaining panel space.
class RohdModulePanel extends StatefulWidget {
  /// Creates the ROHD module panel.
  const RohdModulePanel({super.key});

  @override
  State<RohdModulePanel> createState() => _RohdModulePanelState();
}

class _RohdModulePanelState extends State<RohdModulePanel> {
  bool _initAttempted = false;
  bool _signalsInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryInitializeBloc();
    });
  }

  void _tryInitializeBloc() {
    if (_initAttempted) {
      return;
    }

    final bloc = context.read<RohdModuleBloc>();
    if (bloc.state is Loading) {
      debugPrint('[RohdModulePanel] Initializing RohdModuleBloc');
      _initAttempted = true;
      bloc.add(const RohdModuleInit());
    }
  }

  // NOTE: SignalUpdateEvent is fired from the always-mounted listener
  // in home.dart — do NOT duplicate it here.
  @override
  Widget build(BuildContext context) =>
      BlocBuilder<RohdModuleBloc, RohdModuleState>(
        builder: (context, state) {
          if (state is Loading) {
            if (!_initAttempted) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _tryInitializeBloc();
              });
            }
            return const SizedBox.shrink();
          } else if (state is Rendered) {
            if (!_signalsInitialized &&
                state.moduleStructure.modules.isNotEmpty) {
              _signalsInitialized = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                final firstRoot = state.moduleStructure.modules.first;
                context.read<SignalBloc>().add(SignalUpdateEvent(firstRoot));
              });
            }
            return const _SelectedModuleLabel(moduleName: null);
          } else if (state is RohdModuleError) {
            return const Text(bugReport);
          } else if (state is ModuleSelected) {
            return _SelectedModuleLabel(moduleName: state.singleModule.name);
          } else if (state is WaveformUpdated) {
            return _SelectedModuleLabel(moduleName: state.selectedModule?.name);
          } else {
            return const SizedBox.shrink();
          }
        },
      );
}

/// Compact text label showing the currently selected module name.
class _SelectedModuleLabel extends StatelessWidget {
  final String? _moduleName;

  const _SelectedModuleLabel({required String? moduleName})
      : _moduleName = moduleName;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white70 : Colors.black87;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(
        _moduleName ?? 'Select a module',
        style: TextStyle(
          color: textColor,
          fontSize: 13,
          fontStyle: _moduleName == null ? FontStyle.italic : FontStyle.normal,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
