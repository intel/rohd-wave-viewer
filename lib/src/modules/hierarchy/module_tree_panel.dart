// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module_tree_panel.dart
// Expandable module tree for standalone (non-embedded) mode.
//
// Uses flutter_simple_treeview for the tree layout, matching the DevTools
// extension's ModuleTreeCard visual style (Icons.memory bullets, blue
// selection highlight).
//
// 2026 March
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_simple_treeview/flutter_simple_treeview.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_wave_viewer/src/const/app_theme.dart';
import 'package:rohd_wave_viewer/src/modules/hierarchy/hierarchy_overlay.dart';
import 'package:rohd_wave_viewer/src/modules/rohd_module/bloc/rohd_module_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/shared/widgets/layout_dock_icon.dart';
import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';
import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';

/// Command sent from the header buttons to the tree widget.
enum _TreeCommand { expandAll, collapseAll }

/// Expandable module tree that lets the user navigate the hierarchy
/// and select sub-modules.
///
/// Shown in standalone mode (non-embedded) in place of the compact module
/// label.  In embedded / DevTools mode the parent app provides its own tree.
class ModuleTreePanel extends StatefulWidget {
  /// Creates a module tree panel.
  const ModuleTreePanel({super.key});

  @override
  State<ModuleTreePanel> createState() => _ModuleTreePanelState();
}

class _ModuleTreePanelState extends State<ModuleTreePanel> {
  bool _initAttempted = false;
  bool _signalsInitialized = false;

  /// Command channel from header buttons → tree widget.
  final ValueNotifier<_TreeCommand?> _treeCommand = ValueNotifier(null);

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
      _initAttempted = true;
      bloc.add(const RohdModuleInit());
    }
  }

  @override
  void dispose() {
    _treeCommand.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          _ModuleTreeHeader(command: _treeCommand),
          Expanded(child: _buildTree()),
        ],
      );

  Widget _buildTree() => BlocBuilder<RohdModuleBloc, RohdModuleState>(
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
            return _ModuleTree(
              moduleStructure: state.moduleStructure,
              command: _treeCommand,
            );
          } else if (state is RohdModuleError) {
            return const SizedBox.shrink();
          } else if (state is ModuleSelected) {
            return _ModuleTree(
              key: ValueKey(state.singleModule.path()),
              moduleStructure: state.moduleStructure,
              selectedModule: state.singleModule,
              command: _treeCommand,
            );
          } else if (state is WaveformUpdated) {
            return _ModuleTree(
              moduleStructure: state.moduleStructure,
              selectedModule: state.selectedModule,
              command: _treeCommand,
            );
          } else {
            return const SizedBox.shrink();
          }
        },
      );
}

// ---------------------------------------------------------------------------
// Tree widget — uses flutter_simple_treeview (matching DevTools style)
// ---------------------------------------------------------------------------

class _ModuleTree extends StatefulWidget {
  final ModuleStructure _moduleStructure;
  final HierarchyOccurrence? _selectedModule;
  final ValueNotifier<_TreeCommand?>? _command;

  const _ModuleTree({
    required ModuleStructure moduleStructure,
    super.key,
    HierarchyOccurrence? selectedModule,
    ValueNotifier<_TreeCommand?>? command,
  })  : _moduleStructure = moduleStructure,
        _selectedModule = selectedModule,
        _command = command;

  @override
  State<_ModuleTree> createState() => _ModuleTreeState();
}

class _ModuleTreeState extends State<_ModuleTree> {
  late TreeController _treeController;

  @override
  void initState() {
    super.initState();
    _treeController = TreeController(allNodesExpanded: false);
    widget._command?.addListener(_onCommand);
  }

  void _onCommand() {
    final cmd = widget._command?.value;
    if (cmd == null) {
      return;
    }
    switch (cmd) {
      case _TreeCommand.expandAll:
        _treeController.expandAll();
      case _TreeCommand.collapseAll:
        _treeController.collapseAll();
    }
    widget._command?.value = null;
  }

  @override
  void dispose() {
    widget._command?.removeListener(_onCommand);
    super.dispose();
  }

  /// Indentation applied per tree depth level by [TreeView].
  static const double _indent = 28;

  /// Horizontal space reserved for the expand/collapse icon button and the
  /// node's own icon + padding, so the label text can be width-constrained.
  static const double _rowChrome = 48;

  @override
  Widget build(BuildContext context) {
    final roots = widget._moduleStructure.modules;
    if (roots.isEmpty) {
      return const Center(child: Text('No modules'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 408.0;

        final treeNodes = <TreeNode>[];
        for (final root in roots) {
          final node = _buildNode(context, root, viewportWidth, 0);
          if (node != null) {
            treeNodes.add(node);
          }
        }

        if (treeNodes.isEmpty) {
          return const Center(child: Text('No modules'));
        }

        return SingleChildScrollView(
          child: IconButtonTheme(
            data: IconButtonThemeData(
              style: IconButton.styleFrom(
                minimumSize: const Size(24, 24),
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            child: TreeView(
              nodes: treeNodes,
              treeController: _treeController,
              indent: _indent,
              iconSize: 18,
            ),
          ),
        );
      },
    );
  }

  TreeNode? _buildNode(
    BuildContext context,
    HierarchyOccurrence module,
    double viewportWidth,
    int depth,
  ) {
    final childNodes = _buildChildrenNodes(
      context,
      module,
      viewportWidth,
      depth + 1,
    );

    // Width available to this node's content after subtracting the
    // indentation for its depth and the row chrome (expand icon + padding).
    final maxContentWidth = (viewportWidth - depth * _indent - _rowChrome)
        .clamp(48.0, viewportWidth);

    return TreeNode(
      key: ValueKey(module.path()),
      content: RepaintBoundary(
        child: GestureDetector(
          onTap: () {
            context.read<RohdModuleBloc>().add(
                  RohdModuleSelect(widget._moduleStructure, module),
                );
          },
          child: _NodeContent(
            module: module,
            isSelected: widget._selectedModule != null &&
                module.path() == widget._selectedModule!.path(),
            maxWidth: maxContentWidth,
          ),
        ),
      ),
      children: childNodes,
    );
  }

  List<TreeNode> _buildChildrenNodes(
    BuildContext context,
    HierarchyOccurrence parent,
    double viewportWidth,
    int depth,
  ) {
    final nodes = <TreeNode>[];
    for (final child in parent.children) {
      if (child.isPrimitiveCell) {
        continue;
      }
      if (child.name.contains('struct_assign')) {
        continue;
      }
      final node = _buildNode(context, child, viewportWidth, depth);
      if (node != null) {
        nodes.add(node);
      }
    }
    return nodes;
  }
}

// ---------------------------------------------------------------------------
// Tree node content — Icons.memory bullet with selection highlight
// ---------------------------------------------------------------------------

class _NodeContent extends StatelessWidget {
  final HierarchyOccurrence _module;
  final bool _isSelected;
  final double _maxWidth;

  const _NodeContent({
    required HierarchyOccurrence module,
    required bool isSelected,
    required double maxWidth,
  })  : _module = module,
        _isSelected = isSelected,
        _maxWidth = maxWidth;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedBg = isDark
        ? Colors.blue.shade800.withValues(alpha: 0.5)
        : Colors.blue.shade100;
    final selectedText = isDark ? Colors.white : Colors.blue.shade900;
    final textColor = isDark ? Colors.white : Colors.black;

    return Container(
      clipBehavior: Clip.hardEdge,
      constraints: BoxConstraints(maxWidth: _maxWidth),
      decoration: BoxDecoration(
        color: _isSelected ? selectedBg : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.memory,
            size: 16,
            color: _isSelected
                ? selectedText
                : Theme.of(context).colorScheme.onSurface,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Tooltip(
              message: _module.path(),
              waitDuration: const Duration(milliseconds: 400),
              child: Text(
                _module.name,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: _isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                  color: _isSelected ? selectedText : textColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Module Tree header with expand-all / collapse-all buttons
// ---------------------------------------------------------------------------

class _ModuleTreeHeader extends StatelessWidget {
  final ValueNotifier<_TreeCommand?> _command;

  const _ModuleTreeHeader({required ValueNotifier<_TreeCommand?> command})
      : _command = command;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 36),
      decoration: BoxDecoration(
        color:
            isDark ? DarkThemeColors.panelHeader : LightThemeColors.panelHeader,
        border: Border(
          bottom: BorderSide(
            color: isDark ? DarkThemeColors.divider : LightThemeColors.divider,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          // Dock toggle on the LHS: locks the panel open (pinned) so it does
          // not slide closed.  A vertical divider represents a left panel.
          Builder(
            builder: (context) {
              final pinState = HierarchyPinState.of(context);
              if (pinState == null) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _TreeHeaderButton(
                  iconBuilder: (color) => LayoutDockIcon(
                    edge: LayoutDockEdge.left,
                    locked: pinState.isPinned,
                    color: color,
                  ),
                  tooltip: pinState.isPinned ? 'Unpin panel' : 'Pin panel open',
                  onTap: () {
                    pinState.onPinChanged?.call(!pinState.isPinned);
                  },
                  isActive: pinState.isPinned,
                ),
              );
            },
          ),
          Expanded(
            child: Text(
              'Module Tree',
              softWrap: true,
              style: TextStyle(
                color: isDark ? DarkThemeColors.text : LightThemeColors.text,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          _TreeHeaderButton(
            icon: Icons.expand,
            tooltip: 'Expand all',
            onTap: () => _command.value = _TreeCommand.expandAll,
          ),
          const SizedBox(width: 2),
          _TreeHeaderButton(
            icon: Icons.compress,
            tooltip: 'Collapse all',
            onTap: () => _command.value = _TreeCommand.collapseAll,
          ),
        ],
      ),
    );
  }
}

class _TreeHeaderButton extends StatelessWidget {
  final IconData? _icon;
  final Widget Function(Color color)? _iconBuilder;
  final String _tooltip;
  final VoidCallback _onTap;
  final bool _isActive;

  const _TreeHeaderButton({
    required String tooltip,
    required VoidCallback onTap,
    IconData? icon,
    Widget Function(Color color)? iconBuilder,
    bool isActive = false,
  })  : assert(
          icon != null || iconBuilder != null,
          'Provide either an icon or an iconBuilder',
        ),
        _icon = icon,
        _iconBuilder = iconBuilder,
        _tooltip = tooltip,
        _onTap = onTap,
        _isActive = isActive;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = _isActive
        ? Theme.of(context).colorScheme.primary
        : (isDark ? Colors.white54 : Colors.black54);
    return Tooltip(
      message: _tooltip,
      child: InkWell(
        onTap: _onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: _iconBuilder != null
              ? _iconBuilder(color)
              : Icon(_icon, size: 16, color: color),
        ),
      ),
    );
  }
}
