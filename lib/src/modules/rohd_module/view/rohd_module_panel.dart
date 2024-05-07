// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_module_panel.dart
// The ROHD module panel.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_fancy_tree_view/flutter_fancy_tree_view.dart';
import 'package:rohd_wave_viewer/src/const/locales.dart';
import 'package:rohd_wave_viewer/src/modules/rohd_module/bloc/rohd_module_bloc.dart';
import 'package:module_structure_api/module_structure_api.dart';
import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';

class RohdModulePanel extends StatelessWidget {
  const RohdModulePanel({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RohdModuleBloc, RohdModuleState>(
      builder: (context, state) {
        if (state is Loading) {
          return const Text('');
        } else if (state is Rendered) {
          return ModuleTree(moduleStructure: state.moduleStructure);
        } else if (state is Error) {
          return const Text(bugReport);
        } else if (state is ModuleSelected) {
          // Trigger the SignalBloc
          context.read<SignalBloc>().add(SignalUpdateEvent(state.singleModule));
          return ModuleTree(moduleStructure: state.moduleStructure);
        } else {
          return Container(); // Add a default return for safety
        }
      },
    );
  }
}

class ModuleTree extends StatelessWidget {
  final ModuleStructure moduleStructure;

  const ModuleTree({super.key, required this.moduleStructure});

  @override
  Widget build(BuildContext context) {
    final bodyHeight = MediaQuery.of(context).size.height / 2 - 80;
    final treeController = TreeController<Module>(
      roots: moduleStructure.modules,
      childrenProvider: (Module module) => module.subModules,
    );

    // TreeView have unbounded height
    return SizedBox(
      height: bodyHeight,
      child: TreeView<Module>(
        treeController: treeController,
        nodeBuilder: (BuildContext context, TreeEntry<Module> entry) {
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () {
                context
                    .read<RohdModuleBloc>()
                    .add(RohdModuleSelect(moduleStructure, entry.node));
              },
              child: TreeIndentation(
                entry: entry,
                child: Row(
                  children: [
                    ExpandIcon(
                      key: GlobalObjectKey(entry.node),
                      isExpanded: entry.isExpanded,
                      onPressed: (_) =>
                          treeController.toggleExpansion(entry.node),
                    ),
                    Flexible(
                      child: Text(entry.node.name),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
