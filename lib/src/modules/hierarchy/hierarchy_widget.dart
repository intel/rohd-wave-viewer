// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// hierarchy_widget.dart
// Self-contained hierarchy navigation widget.
//
// This widget encapsulates the module tree and signal list navigation,
// emitting events when the user selects a port. It uses shared models
// (HierarchyOccurrence, Port) and can be reused across apps.
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart'
    show
        AvailableSourceFormats,
        BitDefineFieldsAction,
        BitExpandRangeAction,
        BitExpansionMenuValues,
        BitFieldDef,
        BitFieldUtils,
        GoToSourceCallback,
        RohdSourceFormat,
        buildBitExpansionMenuItems,
        buildGotoSourceMenuItems,
        buildRohdPopupMenuItem,
        gotoSourceFormatFromValue,
        resolveBitExpansionMenuValue;
import 'package:rohd_hierarchy/rohd_hierarchy.dart';
// const.dart import removed — modulePanelTitle no longer needed here.
import 'package:rohd_wave_viewer/src/const/app_theme.dart';
import 'package:rohd_wave_viewer/src/modules/hierarchy/context_menu_blocker_stub.dart'
    if (dart.library.js_interop) 'context_menu_blocker_web.dart';
import 'package:rohd_wave_viewer/src/modules/hierarchy/hierarchy_overlay.dart';
import 'package:rohd_wave_viewer/src/modules/hierarchy/module_tree_panel.dart';
import 'package:rohd_wave_viewer/src/modules/rohd_module/bloc/rohd_module_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/rohd_module/view/rohd_module_panel.dart';
import 'package:rohd_wave_viewer/src/modules/shared/widgets/widgets.dart';
import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/signal/utils/signal_display_utils.dart';
import 'package:rohd_wave_viewer/src/modules/signal/view/signal_filter_field.dart';
import 'package:rohd_wave_viewer/src/modules/signal/view/signal_format_menu.dart';
import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';

/// Callback signature for when a port is selected in the hierarchy.
///
/// [port] is the selected Port (shared model, immutable) [module] is the
/// HierarchyOccurrence containing the port (optional context) [signal] is
/// the SignalOccurrence object with waveform data (for backward
/// compatibility).
typedef OnPortSelectedCallback = void Function(
  SignalOccurrence port,
  HierarchyOccurrence? module,
  SignalOccurrence? signal,
);

/// Self-contained hierarchy navigation widget.
///
/// This widget provides a complete hierarchy navigation experience:
/// - Module tree view (navigating HierarchyOccurrence structure)
/// - SignalOccurrence list view (displaying Port/SignalOccurrence for selected module)
/// - Selection callbacks when user picks a signal
///
/// The widget uses shared models (HierarchyOccurrence, Port) as its interface,
/// making it reusable across different apps that share the same data models.
///
/// Usage:
/// ```dart
/// HierarchyWidget(
///   repository: signalWaveformRepository,
///   onPortSelected: (port, module, signal) {
///     // Add signal to waveform display
///     waveformBloc.add(AddSignal(port));
///   },
/// )
/// ```
///
/// For multi-app integration, the callback can emit events to other apps:
/// ```dart
/// onPortSelected: (port, module, signal) {
///   eventBus.fire(SignalSelectedEvent(port: port));
/// }
/// ```
class HierarchyWidget extends StatelessWidget {
  /// Repository to load and cache module structure.
  final SignalWaveformRepository _repository;

  /// Callback when user selects a port/signal.
  ///
  /// Provides the Port (shared model), the containing module
  /// (HierarchyOccurrence), and the SignalOccurrence with waveform data
  /// (for backward compatibility).
  final OnPortSelectedCallback? _onPortSelected;

  /// Whether to create its own blocs or use existing ones from context.
  ///
  /// When true (default), creates RohdModuleBloc and SignalBloc internally.
  /// When false, expects these blocs to be provided by a parent BlocProvider.
  final bool _createOwnBlocs;

  /// Whether the widget is embedded in a host app (e.g. DevTools extension).
  ///
  /// When true, the separate Module panel is replaced with a compact inline
  /// text showing the selected module name.  Standalone mode keeps the full
  /// module selection pane.
  final bool _isEmbedded;

  /// Callback when user wants to send selected signals to other viewers
  /// (cross-probing).  When non-null, a "Send Signal" item appears in the
  /// right-click context menu of the module signal list.
  final void Function(List<String> signalPaths)? _onSendSignals;

  /// Callback when user wants to navigate to a signal's source for a chosen
  /// [RohdSourceFormat].
  final GoToSourceCallback? _onGoToSource;

  /// Discovers which source formats are navigable for the current module.
  final AvailableSourceFormats? _availableSourceFormats;

  /// Creates the hierarchy widget.
  const HierarchyWidget({
    required SignalWaveformRepository repository,
    super.key,
    OnPortSelectedCallback? onPortSelected,
    bool createOwnBlocs = false,
    bool isEmbedded = false,
    void Function(List<String> signalPaths)? onSendSignals,
    GoToSourceCallback? onGoToSource,
    AvailableSourceFormats? availableSourceFormats,
  })  : _repository = repository,
        _onPortSelected = onPortSelected,
        _createOwnBlocs = createOwnBlocs,
        _isEmbedded = isEmbedded,
        _onSendSignals = onSendSignals,
        _onGoToSource = onGoToSource,
        _availableSourceFormats = availableSourceFormats;

  @override
  Widget build(BuildContext context) {
    if (_createOwnBlocs) {
      return MultiBlocProvider(
        providers: [
          BlocProvider<RohdModuleBloc>(
            create: (context) =>
                RohdModuleBloc(signalWaveformRepository: _repository)
                  ..add(const RohdModuleInit()),
          ),
          BlocProvider<SignalBloc>(
            create: (context) => SignalBloc(_repository),
          ),
        ],
        child: _HierarchyContent(
          onPortSelected: _onPortSelected,
          isEmbedded: _isEmbedded,
          onSendSignals: _onSendSignals,
          onGoToSource: _onGoToSource,
          availableSourceFormats: _availableSourceFormats,
        ),
      );
    }

    // Use existing blocs from context
    return _HierarchyContent(
      onPortSelected: _onPortSelected,
      isEmbedded: _isEmbedded,
      onSendSignals: _onSendSignals,
      onGoToSource: _onGoToSource,
      availableSourceFormats: _availableSourceFormats,
    );
  }
}

/// Internal content widget that displays the hierarchy panels.
class _HierarchyContent extends StatefulWidget {
  final OnPortSelectedCallback? _onPortSelected;
  final bool _isEmbedded;
  final void Function(List<String> signalPaths)? _onSendSignals;
  final GoToSourceCallback? _onGoToSource;
  final AvailableSourceFormats? _availableSourceFormats;

  const _HierarchyContent({
    OnPortSelectedCallback? onPortSelected,
    bool isEmbedded = false,
    void Function(List<String> signalPaths)? onSendSignals,
    GoToSourceCallback? onGoToSource,
    AvailableSourceFormats? availableSourceFormats,
  })  : _onPortSelected = onPortSelected,
        _isEmbedded = isEmbedded,
        _onSendSignals = onSendSignals,
        _onGoToSource = onGoToSource,
        _availableSourceFormats = availableSourceFormats;

  @override
  State<_HierarchyContent> createState() => _HierarchyContentState();
}

class _HierarchyContentState extends State<_HierarchyContent> {
  /// Fraction of the available height allocated to the module tree panel.
  /// Clamped to [_minFraction, _maxFraction] during drag.
  double _treeFraction = 0.5;
  static const double _minFraction = 0.15;
  static const double _maxFraction = 0.85;

  /// Height of the draggable divider handle.
  static const double _dividerHeight = 6;

  /// Build a [HierarchyService] from the current module structure.
  ///
  /// If the [ModuleStructure] carries a pre-built [HierarchyService] (e.g.
  /// from an external hierarchy source), use it directly — this preserves
  /// the original adapter's internal state (flat maps, connectivity, etc.).
  ///
  /// Otherwise, wrap the raw [HierarchyOccurrence] tree with
  /// [BaseHierarchyAdapter.fromTree].
  HierarchyService? _buildHierarchy(ModuleStructure structure) {
    // Prefer the original service when available.
    if (structure.hierarchyService != null) {
      return structure.hierarchyService;
    }

    final modules = structure.modules;
    if (modules.isEmpty) {
      return null;
    }
    if (modules.length == 1) {
      return BaseHierarchyAdapter.fromTree(modules.first);
    }
    // Multiple roots — create a synthetic container
    final syntheticRoot = HierarchyOccurrence(name: 'root', children: modules);
    return BaseHierarchyAdapter.fromTree(syntheticRoot);
  }

  @override
  Widget build(BuildContext context) {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor =
        isDarkTheme ? const Color(0xFF1E1E1E) : Colors.white;

    return BlocBuilder<RohdModuleBloc, RohdModuleState>(
      buildWhen: (prev, curr) => prev.moduleStructure != curr.moduleStructure,
      builder: (context, rohdState) {
        final hierarchy = _buildHierarchy(rohdState.moduleStructure);

        // In embedded mode the module tree is hidden; no split needed.
        if (widget._isEmbedded) {
          return Column(
            children: [
              Expanded(
                child: DecoratedBox(
                  decoration: panelDecoration(
                    isDark: isDarkTheme,
                    backgroundColor: backgroundColor,
                  ),
                  child: Column(
                    children: [
                      const RohdModulePanel(),
                      _ModuleSignalsHeader(
                        hierarchy: hierarchy,
                        showDockToggle: true,
                      ),
                      Expanded(
                        child: _SignalListWithCallback(
                          onPortSelected: widget._onPortSelected,
                          onSendSignals: widget._onSendSignals,
                          onGoToSource: widget._onGoToSource,
                          availableSourceFormats:
                              widget._availableSourceFormats,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }

        // Standalone mode: module tree + draggable divider + signal list.
        return LayoutBuilder(
          builder: (context, constraints) {
            final totalH = constraints.maxHeight;
            final usableH = totalH - _dividerHeight;
            final treeH = (usableH * _treeFraction).clamp(0.0, usableH);
            final signalH = usableH - treeH;

            return Column(
              children: [
                // Module tree panel
                SizedBox(
                  height: treeH,
                  child: DecoratedBox(
                    decoration: panelDecoration(
                      isDark: isDarkTheme,
                      backgroundColor: backgroundColor,
                    ),
                    child: const ModuleTreePanel(),
                  ),
                ),
                // Draggable horizontal divider
                MouseRegion(
                  cursor: SystemMouseCursors.resizeRow,
                  child: GestureDetector(
                    onVerticalDragUpdate: (details) {
                      setState(() {
                        _treeFraction =
                            (_treeFraction + details.delta.dy / usableH).clamp(
                          _minFraction,
                          _maxFraction,
                        );
                      });
                    },
                    child: Container(
                      height: _dividerHeight,
                      color: isDarkTheme
                          ? DarkThemeColors.divider
                          : LightThemeColors.divider,
                    ),
                  ),
                ),
                // SignalOccurrence list panel
                SizedBox(
                  height: signalH,
                  child: DecoratedBox(
                    decoration: panelDecoration(
                      isDark: isDarkTheme,
                      backgroundColor: backgroundColor,
                    ),
                    child: Column(
                      children: [
                        _ModuleSignalsHeader(hierarchy: hierarchy),
                        Expanded(
                          child: _SignalListWithCallback(
                            onPortSelected: widget._onPortSelected,
                            onSendSignals: widget._onSendSignals,
                            onGoToSource: widget._onGoToSource,
                            availableSourceFormats:
                                widget._availableSourceFormats,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Module Signals header with sort buttons
// ─────────────────────────────────────────────────────────────────────

class _ModuleSignalsHeader extends StatelessWidget {
  final HierarchyService? _hierarchy;
  final bool _showDockToggle;

  const _ModuleSignalsHeader({
    required HierarchyService? hierarchy,
    bool showDockToggle = false,
  })  : _hierarchy = hierarchy,
        _showDockToggle = showDockToggle;

  @override
  Widget build(BuildContext context) => BlocBuilder<SignalBloc, SignalState>(
        buildWhen: (prev, curr) => prev.sortAscending != curr.sortAscending,
        builder: (context, state) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final sortAsc = state.sortAscending;

          return Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 36),
            decoration: BoxDecoration(
              color: isDark
                  ? DarkThemeColors.panelHeader
                  : LightThemeColors.panelHeader,
              border: Border(
                bottom: BorderSide(
                  color: isDark
                      ? DarkThemeColors.divider
                      : LightThemeColors.divider,
                ),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              children: [
                if (_showDockToggle) ...[
                  Builder(
                    builder: (context) {
                      final pinState = HierarchyPinState.of(context);
                      if (pinState == null) {
                        return const SizedBox.shrink();
                      }
                      return _SortButton(
                        iconBuilder: (color) => LayoutDockIcon(
                          edge: LayoutDockEdge.left,
                          locked: pinState.isPinned,
                          color: color,
                        ),
                        tooltip: pinState.isPinned
                            ? 'Unpin panel'
                            : 'Pin panel open',
                        isActive: pinState.isPinned,
                        onTap: () {
                          pinState.onPinChanged?.call(!pinState.isPinned);
                        },
                      );
                    },
                  ),
                  const SizedBox(width: 4),
                ],
                // Inline filter field — fills available space
                const SizedBox(width: 6),
                Expanded(child: SignalFilterField(hierarchy: _hierarchy)),
                const SizedBox(width: 4),
                // Sort ascending button
                _SortButton(
                  icon: Icons.arrow_upward,
                  tooltip: 'Sort A→Z',
                  isActive: sortAsc ?? false,
                  onTap: () {
                    context.read<SignalBloc>().add(
                          SignalSortEvent(
                              ascending: sortAsc ?? false ? null : true),
                        );
                  },
                ),
                const SizedBox(width: 2),
                // Sort descending button
                _SortButton(
                  icon: Icons.arrow_downward,
                  tooltip: 'Sort Z→A',
                  isActive: sortAsc == false,
                  onTap: () {
                    context.read<SignalBloc>().add(
                          SignalSortEvent(
                              ascending: sortAsc == false ? null : false),
                        );
                  },
                ),
              ],
            ),
          );
        },
      );
}

class _SortButton extends StatelessWidget {
  final IconData? _icon;
  final Widget Function(Color color)? _iconBuilder;
  final String _tooltip;
  final bool _isActive;
  final VoidCallback _onTap;

  const _SortButton({
    required String tooltip,
    required bool isActive,
    required VoidCallback onTap,
    IconData? icon,
    Widget Function(Color color)? iconBuilder,
  })  : assert(
          icon != null || iconBuilder != null,
          'Provide either an icon or an iconBuilder',
        ),
        _icon = icon,
        _iconBuilder = iconBuilder,
        _tooltip = tooltip,
        _isActive = isActive,
        _onTap = onTap;

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

// ─────────────────────────────────────────────────────────────────────
// SignalOccurrence list with click/ctrl/shift selection + right-click context menu
// ─────────────────────────────────────────────────────────────────────

/// SignalOccurrence list that supports:
/// - Click: select single signal
/// - Ctrl+Click: toggle signal in selection
/// - Shift+Click: range select from anchor to click
/// - Double-click: add to monitor (Selected Signals) immediately
/// - Right-click: context menu with Add/Remove from monitor
class _SignalListWithCallback extends StatefulWidget {
  final OnPortSelectedCallback? _onPortSelected;
  final void Function(List<String> signalPaths)? _onSendSignals;
  final GoToSourceCallback? _onGoToSource;
  final AvailableSourceFormats? _availableSourceFormats;

  const _SignalListWithCallback({
    OnPortSelectedCallback? onPortSelected,
    void Function(List<String> signalPaths)? onSendSignals,
    GoToSourceCallback? onGoToSource,
    AvailableSourceFormats? availableSourceFormats,
  })  : _onPortSelected = onPortSelected,
        _onSendSignals = onSendSignals,
        _onGoToSource = onGoToSource,
        _availableSourceFormats = availableSourceFormats;

  @override
  State<_SignalListWithCallback> createState() =>
      _SignalListWithCallbackState();
}

class _SignalListWithCallbackState extends State<_SignalListWithCallback> {
  /// Anchor index for shift-click range selection.
  int? _anchorIndex;

  /// Currently selected expanded sub-field row, tracked locally because
  /// sub-fields are display-only rows rather than first-class module rows.
  String? _selectedSubFieldId;

  /// Signal paths that are currently expanded to show sub-fields.
  final Set<String> _expandedSignals = {};

  /// For array signals, the currently visible element slice [start, end]
  /// (inclusive).  Absent key = struct (show all fields).
  final Map<String, (int, int)> _arraySliceRanges = {};

  /// User-defined bit-field definitions for signals, keyed by signal path.
  /// When present, the signal is shown expanded with these named fields.
  final Map<String, List<BitFieldDef>> _definedBitFields = {};

  /// Focus node for keyboard event handling (e.g. Ctrl-A select all).
  late final FocusNode _focusNode;

  /// ScrollController for the signal list ListView.
  /// Replaced with a new instance (with initialScrollOffset) when jumping
  /// to a target after clearing the filter, to avoid a visual flash.
  ScrollController _scrollController = ScrollController();

  /// Bumped each time [_scrollController] is replaced so the ListView
  /// is keyed differently, forcing Flutter to create a new Scrollable
  /// (and thus a new ScrollPosition that honours initialScrollOffset).
  int _scrollGeneration = 0;

  /// Estimated height of a single signal row (padding + text + border).
  static const _estimatedRowHeight = 24.0;

  /// Direct DOM event listener that prevents the browser's native
  /// context-menu inside DevTools extension iframes where Flutter's
  /// [BrowserContextMenu.disableContextMenu] alone is insufficient.
  Object? _contextMenuBlocker;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'ModuleSignalList');
    // On web, disable the browser's native context menu so our
    // Flutter right-click popup isn't hidden behind it.
    if (kIsWeb) {
      unawaited(BrowserContextMenu.disableContextMenu());
      // Belt-and-suspenders: add a capturing listener directly on the
      // document so the native menu is suppressed even inside iframes
      // (e.g. DevTools extensions) where the Flutter engine-level
      // prevention may not take effect.
      _contextMenuBlocker = createContextMenuBlocker();
      addContextMenuBlocker(_contextMenuBlocker);
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _scrollController.dispose();
    if (kIsWeb) {
      if (_contextMenuBlocker != null) {
        removeContextMenuBlocker(_contextMenuBlocker);
        _contextMenuBlocker = null;
      }
      unawaited(BrowserContextMenu.enableContextMenu());
    }
    super.dispose();
  }

  /// Handle keyboard events — Ctrl-A selects all module signals.
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyA &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed)) {
      context.read<SignalBloc>().add(ModuleSignalSelectAllEvent());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Show a dialog to select the array element range to expand.
  ///
  /// Accepts formats: `start:end` for a range, or `index` for a single
  /// element.  Both bounds are inclusive and zero-based.
  Future<void> _showArraySliceDialog(
    BuildContext context,
    SignalOccurrence signal,
    Offset tapPosition,
  ) async {
    final numElements = signal.subFieldDescriptors.length;
    final maxIndex = numElements - 1;
    final controller = TextEditingController(text: '0:$maxIndex');
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );

    final overlayHold = HierarchyOverlayHold.of(context);
    overlayHold?.hold();
    final result = await showDialog<String>(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) => Stack(
        children: [
          Positioned(
            left: tapPosition.dx,
            top: tapPosition.dy,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 280,
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${signal.name}  [$numElements elements]',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Range (start:end) or index',
                        hintText: '0:$maxIndex',
                        isDense: true,
                      ),
                      onSubmitted: (value) => Navigator.of(ctx).pop(value),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () =>
                              Navigator.of(ctx).pop(controller.text),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    overlayHold?.release();
    if (result == null || result.trim().isEmpty) {
      return;
    }
    final parsed = _parseSliceRange(result.trim(), maxIndex);
    if (parsed == null) {
      return;
    }

    setState(() {
      _expandedSignals.add(signal.path());
      _arraySliceRanges[signal.path()] = parsed;
    });
  }

  /// Show a slice dialog for a nested sub-array item.
  Future<void> _showArraySliceDialogForSubField(
    BuildContext context,
    _DisplayItem item,
    Offset tapPosition,
  ) async {
    final logicType = item._subLogicType!;
    final arrayDims = logicType['arrayDims'] as List<dynamic>?;
    if (arrayDims == null || arrayDims.isEmpty) {
      return;
    }
    final numElements = arrayDims.first as int;
    final maxIndex = numElements - 1;
    final controller = TextEditingController(text: '0:$maxIndex');
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );

    final overlayHold2 = HierarchyOverlayHold.of(context);
    overlayHold2?.hold();
    final result = await showDialog<String>(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) => Stack(
        children: [
          Positioned(
            left: tapPosition.dx,
            top: tapPosition.dy,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 280,
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item._fieldLabel}  [$numElements elements]',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Range (start:end) or index',
                        hintText: '0:$maxIndex',
                        isDense: true,
                      ),
                      onSubmitted: (value) => Navigator.of(ctx).pop(value),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () =>
                              Navigator.of(ctx).pop(controller.text),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    overlayHold2?.release();
    if (result == null || result.trim().isEmpty) {
      return;
    }
    final parsed = _parseSliceRange(result.trim(), maxIndex);
    if (parsed == null) {
      return;
    }

    setState(() {
      _expandedSignals.add(item._subFieldPath!);
      _arraySliceRanges[item._subFieldPath] = parsed;
    });
  }

  /// Parse a slice range string into (start, end) inclusive bounds.
  ///
  /// Accepts `start:end` or a single `index`.  Returns null on invalid input.
  /// Clamps to [0, maxIndex].
  static (int, int)? _parseSliceRange(String input, int maxIndex) {
    if (input.contains(':')) {
      final parts = input.split(':');
      if (parts.length != 2) {
        return null;
      }
      final start = int.tryParse(parts[0].trim());
      final end = int.tryParse(parts[1].trim());
      if (start == null || end == null) {
        return null;
      }
      final s = start.clamp(0, maxIndex);
      final e = end.clamp(0, maxIndex);
      return s <= e ? (s, e) : (e, s);
    }
    final idx = int.tryParse(input);
    if (idx == null) {
      return null;
    }
    final clamped = idx.clamp(0, maxIndex);
    return (clamped, clamped);
  }

  /// Recursively expand nested sub-array items into the flat display list.
  ///
  /// Only adds items if [parentSubPath] is in [_expandedSignals].
  void _expandSubArrayItems(
    List<_DisplayItem> displayItems, {
    required SignalOccurrence parentSignal,
    required String parentSubPath,
    required int parentStartBit,
    required Map<String, Object?>? logicType,
    required String parentName,
    required int depth,
  }) {
    if (logicType == null) {
      return;
    }
    if (!_expandedSignals.contains(parentSubPath)) {
      return;
    }

    final descs = SignalOccurrence.subFieldDescriptorsForType(
      logicType,
      parentName,
    );
    final sliceRange = _arraySliceRanges[parentSubPath];
    for (var i = 0; i < descs.length; i++) {
      if (sliceRange != null) {
        final (start, end) = sliceRange;
        if (i < start || i > end) {
          continue;
        }
      }
      final desc = descs[i];
      final subPath = '$parentSubPath#${desc.fieldLabel}';
      // startBit is relative to the root signal, so offset by parent's
      // position.
      final absoluteStartBit = parentStartBit + desc.startBit;
      // Build the field label for the signal bloc's subFieldId construction.
      // Uses '.' separator between nested array indices so _resolveFieldBits
      // can parse them: e.g. "[0].[2]" for 2nd element inside 1st element.
      final parentFieldPart = parentSubPath.substring(
        parentSubPath.indexOf('#') + 1,
      );
      final nestedFieldLabel = '$parentFieldPart.${desc.fieldLabel}';
      displayItems.add(
        _DisplayItem.subField(
          parent: parentSignal,
          fieldLabel: nestedFieldLabel,
          width: desc.width,
          startBit: absoluteStartBit,
          subLogicType: desc.subLogicType,
          depth: depth,
          subFieldPath: subPath,
        ),
      );
      _appendDefinedSubFieldBits(
        displayItems,
        parentSignal: parentSignal,
        parentSubPath: subPath,
        parentStartBit: absoluteStartBit,
        depth: depth + 1,
      );
      // Recurse into deeper levels.
      _expandSubArrayItems(
        displayItems,
        parentSignal: parentSignal,
        parentSubPath: subPath,
        parentStartBit: absoluteStartBit,
        logicType: desc.subLogicType,
        parentName: desc.expectedName,
        depth: depth + 1,
      );
    }
  }

  void _appendDefinedSubFieldBits(
    List<_DisplayItem> displayItems, {
    required SignalOccurrence parentSignal,
    required String parentSubPath,
    required int parentStartBit,
    required int depth,
  }) {
    if (!_expandedSignals.contains(parentSubPath)) {
      return;
    }
    final fields = _definedBitFields[parentSubPath];
    if (fields == null || fields.isEmpty) {
      return;
    }

    final parentPath = parentSignal.path();
    final parentOperations = parentSubPath.substring(parentPath.length + 1);
    final fieldDisplayName = parentOperations.contains('#')
        ? '${parentSignal.name}${parentOperations.replaceAll('#', '')}'
        : '${parentSignal.name}_$parentOperations';
    for (final field in fields) {
      final bitSlice = field.high == field.low
          ? 'b[${field.low}]'
          : 'b[${field.high}:${field.low}]';
      displayItems.add(
        _DisplayItem.subField(
          parent: parentSignal,
          fieldLabel: '$parentOperations#$bitSlice',
          width: field.width,
          startBit: parentStartBit + field.low,
          depth: depth,
          subFieldPath: '$parentSubPath#$bitSlice',
          bitFieldName: field.name,
          monitorDisplayName: field.name.startsWith('[')
              ? '$fieldDisplayName${field.name}'
              : '$fieldDisplayName.${field.name}',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => _focusNode.requestFocus(),
        child: Focus(
          focusNode: _focusNode,
          onKeyEvent: _handleKeyEvent,
          child: BlocListener<SignalBloc, SignalState>(
            listenWhen: (prev, curr) => prev.filterText != curr.filterText,
            listener: (context, state) {
              // When filter is cleared, prepare to scroll to the first
              // previously-matched signal so the user sees where it lives.
              if (state.filterText.isEmpty) {
                final targetId = _lastFirstFilteredId;
                _lastFirstFilteredId = null;

                if (targetId != null) {
                  // Compute the target index in the full (now unfiltered) list
                  // that the builder is about to display.
                  final fullList = state.filteredSignals;
                  final idx = fullList.indexWhere((s) => s.path() == targetId);
                  if (idx > 0) {
                    final targetOffset = idx * _estimatedRowHeight;
                    // Replace the controller with one whose initialScrollOffset
                    // is at the target.  The builder runs after this listener,
                    // so the ListView will pick up the new controller and
                    // render at the right position on the very first frame — no
                    // flash.
                    final old = _scrollController;
                    _scrollController = ScrollController(
                      initialScrollOffset: targetOffset,
                    );
                    _scrollGeneration++;
                    // Dispose the old controller after this frame completes
                    // (it's still attached to the outgoing ListView until the
                    // rebuild finishes).
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => old.dispose(),
                    );
                  }
                }
              } else {
                // While filtering, remember the first match so we can scroll
                // to it when the filter is cleared.
                final filtered = state.filteredSignals;
                _lastFirstFilteredId =
                    filtered.isNotEmpty ? filtered.first.path() : null;
              }
            },
            child: BlocBuilder<SignalBloc, SignalState>(
              builder: (context, state) {
                if (state is SignalLoaded) {
                  return _buildSignalList(
                      context, state.filteredSignals, state);
                }
                return _buildSignalList(context, const [], state);
              },
            ),
          ),
        ),
      );

  /// The hierarchy path of the first signal from the last non-empty filter.
  String? _lastFirstFilteredId;

  Widget _buildSignalList(
    BuildContext context,
    List<SignalOccurrence> signals,
    SignalState state,
  ) {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkTheme ? Colors.white : Colors.black;

    if (signals.isEmpty) {
      return ListView(
        key: ValueKey(_scrollGeneration),
        controller: _scrollController,
        primary: false,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Center(
            child: Text(
              'No signals available',
              style: TextStyle(color: textColor),
            ),
          ),
        ],
      );
    }

    // Build a flat display list that includes sub-field rows for expanded
    // struct/array signals.
    final displayItems = <_DisplayItem>[];
    for (final signal in signals) {
      displayItems.add(_DisplayItem.signal(signal));
      final sigPath = signal.path();
      if (_expandedSignals.contains(sigPath)) {
        final descs = signal.subFieldDescriptors;
        final bitFields = _definedBitFields[sigPath];

        if (descs.isNotEmpty) {
          // Struct/array expansion via sub-field descriptors.
          final sliceRange = _arraySliceRanges[sigPath];
          for (var i = 0; i < descs.length; i++) {
            // For arrays with a slice range, skip elements outside the range.
            if (sliceRange != null) {
              final (start, end) = sliceRange;
              if (i < start || i > end) {
                continue;
              }
            }
            final desc = descs[i];
            // Check if sub-field exists as a tracked signal in the same module.
            final parentOcc = signal.parent;
            final childIdx = parentOcc?.signalIndexByName(desc.expectedName);
            final childSignal = (childIdx != null && childIdx >= 0)
                ? parentOcc!.signals[childIdx]
                : null;
            final subPath = '$sigPath#${desc.fieldLabel}';
            displayItems.add(
              _DisplayItem.subField(
                parent: signal,
                fieldLabel: desc.fieldLabel,
                width: desc.width,
                startBit: desc.startBit,
                childSignal: childSignal,
                subLogicType: desc.subLogicType,
                subFieldPath: subPath,
              ),
            );
            // Recursively expand nested sub-arrays.
            _expandSubArrayItems(
              displayItems,
              parentSignal: signal,
              parentSubPath: subPath,
              parentStartBit: desc.startBit,
              logicType: desc.subLogicType,
              parentName: desc.expectedName,
              depth: 1,
            );
            _appendDefinedSubFieldBits(
              displayItems,
              parentSignal: signal,
              parentSubPath: subPath,
              parentStartBit: desc.startBit,
              depth: 1,
            );
          }
        }

        // User-defined bit-field items (appended after structural fields).
        if (bitFields != null && bitFields.isNotEmpty) {
          for (final field in bitFields) {
            final fieldLabel = field.high == field.low
                ? 'b[${field.low}]'
                : 'b[${field.high}:${field.low}]';
            final subPath = '$sigPath#$fieldLabel';
            displayItems.add(
              _DisplayItem.subField(
                parent: signal,
                fieldLabel: fieldLabel,
                width: field.width,
                startBit: field.low,
                subFieldPath: subPath,
                bitFieldName: field.name,
              ),
            );
          }
        }
      }
    }

    return ListView.builder(
      key: ValueKey(_scrollGeneration),
      controller: _scrollController,
      primary: false,
      physics: const AlwaysScrollableScrollPhysics(),
      itemExtent: _estimatedRowHeight,
      itemCount: displayItems.length,
      itemBuilder: (context, index) {
        final item = displayItems[index];
        if (item._isSubField) {
          return _buildSubFieldRow(
            context,
            item,
            isDarkTheme,
            textColor,
            state,
          );
        }
        final signal = item._signal!;
        final isSelected = state.isModuleSignalSelected(signal.path());
        final isInMonitor = state.monitorSignalsList.any(
          (w) => w.matchesOccurrence(signal),
        );
        final isExpandable = signal.isStruct || signal.isArray;
        final isExpanded = _expandedSignals.contains(signal.path());

        return Padding(
          padding: const EdgeInsets.only(top: 1, left: 10),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _onSignalTap(context, signal, index),
              onDoubleTap: () => _onSignalDoubleTap(context, signal),
              onSecondaryTapUp: (details) {
                unawaited(
                  _showContextMenu(context, details.globalPosition, signal),
                );
              },
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.blue.withValues(alpha: 0.30)
                      : Colors.transparent,
                  border: Border(
                    bottom: BorderSide(
                      color: isDarkTheme ? Colors.white24 : Colors.black12,
                      width: 0.5,
                    ),
                  ),
                ),
                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
                child: Row(
                  children: [
                    if (isExpandable)
                      GestureDetector(
                        onTapDown: (details) {
                          if (isExpanded) {
                            setState(() {
                              _expandedSignals.remove(signal.path());
                              _arraySliceRanges.remove(signal.path());
                            });
                          } else if (signal.isArray &&
                              signal.subFieldDescriptors.length >= 10) {
                            unawaited(
                              _showArraySliceDialog(
                                context,
                                signal,
                                details.globalPosition,
                              ),
                            );
                          } else {
                            setState(() {
                              _expandedSignals.add(signal.path());
                            });
                          }
                        },
                        child: Icon(
                          isExpanded ? Icons.expand_more : Icons.chevron_right,
                          size: 14,
                          color: textColor,
                        ),
                      ),
                    if (isExpandable)
                      const SizedBox(width: 2)
                    else
                      const SizedBox(width: 16),
                    Expanded(
                      child: Tooltip(
                        message: signal.path(),
                        waitDuration: const Duration(milliseconds: 400),
                        child: Text(
                          formatSignalNameWithWidth(signal.name, signal.width),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isInMonitor
                                ? (isDarkTheme
                                    ? Colors.white38
                                    : Colors.black38)
                                : textColor,
                            fontStyle: signal.direction == null
                                ? FontStyle.italic
                                : FontStyle.normal,
                          ),
                        ),
                      ),
                    ),
                    if (signal.typeName != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text(
                          signal.typeName!,
                          style: TextStyle(
                            fontSize: 10,
                            color:
                                isDarkTheme ? Colors.white38 : Colors.black38,
                          ),
                        ),
                      ),
                    if (isSelected)
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(Icons.check, size: 14, color: Colors.blue),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Build a sub-field row (indented, with different styling).
  /// Format the display text for a sub-field row, showing the bit range
  /// rather than the width (e.g. `fieldName [7:4]` instead of `fieldName [4]`).
  static String _subFieldDisplayText(_DisplayItem item) {
    final startBit = item._startBit ?? 0;
    final width = item._width ?? 1;
    final rangeStr = BitFieldUtils.formatBitRange(startBit, width);
    if (item._bitFieldName != null) {
      // Anonymous bracket-style labels (e.g. "[7]" / "[7:4]") already encode
      // the range, so don't append it again. Named fields show "name [7:4]".
      if (item._bitFieldName.startsWith('[')) {
        return item._bitFieldName;
      }
      return '${item._bitFieldName} $rangeStr';
    }
    return '${item._fieldLabel} $rangeStr';
  }

  Widget _buildSubFieldRow(
    BuildContext context,
    _DisplayItem item,
    bool isDarkTheme,
    Color textColor,
    SignalState state,
  ) {
    final fieldLabel = item._fieldLabel!;
    final hasTracked = item._childSignal != null;
    final subFieldId = hasTracked
        ? item._childSignal.path()
        : '${item._parent!.path()}#$fieldLabel';
    final isSelected = _selectedSubFieldId == subFieldId;
    final isInMonitor = state.monitorSignalsList.any((w) => w.id == subFieldId);
    final isExpandable = item._isExpandableSubField;
    final isExpanded = isExpandable &&
        item._subFieldPath != null &&
        _expandedSignals.contains(item._subFieldPath);
    // Indent based on nesting depth.
    final leftPad = 30.0 + item._depth * 16.0;

    return Padding(
      padding: EdgeInsets.only(top: 1, left: leftPad),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            if (event.buttons == kPrimaryMouseButton) {
              _selectSubField(context, subFieldId);
            } else if (event.buttons == kSecondaryMouseButton) {
              if (!isSelected) {
                _selectSubField(context, subFieldId);
              }
              unawaited(
                _showSubFieldContextMenu(context, event.position, item),
              );
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: () => _addSubFieldToMonitor(context, item),
            child: Container(
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.blue.withValues(alpha: 0.30)
                    : Colors.transparent,
                border: Border(
                  bottom: BorderSide(
                    color: isDarkTheme ? Colors.white12 : Colors.black12,
                    width: 0.5,
                  ),
                ),
              ),
              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
              child: Row(
                children: [
                  if (isExpandable)
                    GestureDetector(
                      onTapDown: (details) {
                        final path = item._subFieldPath!;
                        if (isExpanded) {
                          setState(() {
                            _expandedSignals.remove(path);
                            _arraySliceRanges.remove(path);
                          });
                        } else {
                          final logicType = item._subLogicType!;
                          final arrayDims =
                              logicType['arrayDims'] as List<dynamic>?;
                          final numElements =
                              (arrayDims != null && arrayDims.isNotEmpty)
                                  ? arrayDims.first as int
                                  : 0;
                          if (numElements >= 10) {
                            unawaited(
                              _showArraySliceDialogForSubField(
                                context,
                                item,
                                details.globalPosition,
                              ),
                            );
                          } else {
                            setState(() {
                              _expandedSignals.add(path);
                            });
                          }
                        }
                      },
                      child: Icon(
                        isExpanded ? Icons.expand_more : Icons.chevron_right,
                        size: 12,
                        color: isDarkTheme ? Colors.white54 : Colors.black54,
                      ),
                    ),
                  if (!isExpandable)
                    Icon(
                      item._bitFieldName != null
                          ? Icons.segment
                          : hasTracked
                              ? Icons.subdirectory_arrow_right
                              : Icons.functions,
                      size: 12,
                      color: isDarkTheme ? Colors.white54 : Colors.black54,
                    ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Tooltip(
                      message: subFieldId,
                      waitDuration: const Duration(milliseconds: 400),
                      child: Text(
                        _subFieldDisplayText(item),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: isInMonitor
                              ? (isDarkTheme ? Colors.white38 : Colors.black38)
                              : (isDarkTheme ? Colors.white70 : Colors.black87),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _selectSubField(BuildContext context, String subFieldId) {
    setState(() {
      _selectedSubFieldId = subFieldId;
    });
  }

  void _addSubFieldToMonitor(BuildContext context, _DisplayItem item) {
    if (item._childSignal != null) {
      context.read<SignalBloc>().add(SignalSelectedEvent(item._childSignal));
      return;
    }

    context.read<SignalBloc>().add(
          SignalSubFieldSelectedEvent(
            parentSignal: item._parent!,
            fieldLabel: item._fieldLabel!,
            startBit: item._startBit!,
            width: item._width!,
            displayName: item._bitFieldName != null
                ? item._monitorDisplayName ??
                    (item._bitFieldName.startsWith('[')
                        ? '${item._parent.name}${item._bitFieldName}'
                        : item._bitFieldName)
                : null,
          ),
        );
  }

  Future<void> _showSubFieldContextMenu(
    BuildContext context,
    Offset globalPosition,
    _DisplayItem item,
  ) async {
    final signalBloc = context.read<SignalBloc>();
    final subFieldId = item._childSignal?.path() ??
        item._subFieldPath ??
        '${item._parent!.path()}#${item._fieldLabel!}';
    final actionPath = item._childSignal?.path() ?? item._parent!.path();
    final leafName = item._bitFieldName != null
        ? item._monitorDisplayName ??
            (item._bitFieldName.startsWith('[')
                ? '${item._parent!.name}${item._bitFieldName}'
                : item._bitFieldName)
        : _subFieldDisplayText(item);
    final monitoredWaveform = signalBloc.state.monitorSignalsList
        .where((w) => w.id == subFieldId || w.signalId == subFieldId)
        .firstOrNull;

    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final overlayPosition = overlay.localToGlobal(Offset.zero);
    final overlayHold = HierarchyOverlayHold.of(context);
    overlayHold?.hold();

    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx - overlayPosition.dx,
        globalPosition.dy - overlayPosition.dy,
        overlay.size.width - (globalPosition.dx - overlayPosition.dx),
        overlay.size.height - (globalPosition.dy - overlayPosition.dy),
      ),
      items: [
        buildRohdPopupMenuItem<String>(
          value: 'add',
          icon: const Icon(Icons.add_circle_outline, size: 16),
          label: 'Add to Selected Signals',
        ),
        if (monitoredWaveform != null)
          buildRohdPopupMenuItem<String>(
            value: 'remove',
            icon: const Icon(Icons.remove_circle_outline, size: 16),
            label: 'Remove from Selected Signals',
          ),
        buildSignalFormatMenuItem(count: 1),
        if ((item._width ?? 1) > 1)
          ...buildBitExpansionMenuItems(width: item._width!),
        if (widget._onSendSignals != null)
          buildRohdPopupMenuItem<String>(
            value: 'send',
            icon: const Icon(Icons.send, size: 16),
            label: 'Send Signal',
          ),
        if (widget._onGoToSource != null)
          ...buildGotoSourceMenuItems(
            formats: widget._availableSourceFormats?.call() ?? const [],
          ),
        buildRohdPopupMenuItem<String>(
          value: 'copy_name',
          icon: const Icon(Icons.content_copy, size: 16),
          label: 'Copy Name',
        ),
        buildRohdPopupMenuItem<String>(
          value: 'copy_path',
          icon: const Icon(Icons.account_tree, size: 16),
          label: 'Copy Full Path',
        ),
      ],
    );

    overlayHold?.release();
    if (value == null || !context.mounted) {
      return;
    }

    final gotoFormat = gotoSourceFormatFromValue(value);
    if (gotoFormat != null) {
      widget._onGoToSource?.call(gotoFormat, [actionPath]);
      return;
    }

    switch (value) {
      case 'add':
        _addSubFieldToMonitor(context, item);
      case 'remove':
        if (monitoredWaveform != null) {
          signalBloc.add(SignalRemoveEvent(monitoredWaveform));
        }
      case signalFormatMenuValue:
        await showSignalFormatMenu(
          context,
          globalPosition: globalPosition,
          signalPaths: {subFieldId},
          addresses: [item._childSignal?.address],
        );
      case BitExpansionMenuValues.expandBits:
      case BitExpansionMenuValues.defineFields:
        await _handleSubFieldBitExpansion(
          context,
          value,
          item,
          subFieldId,
        );
      case 'send':
        widget._onSendSignals?.call([actionPath]);
      case 'copy_name':
        await Clipboard.setData(ClipboardData(text: leafName));
      case 'copy_path':
        await Clipboard.setData(ClipboardData(text: subFieldId));
    }
  }

  Future<void> _handleSubFieldBitExpansion(
    BuildContext context,
    String value,
    _DisplayItem item,
    String subFieldId,
  ) async {
    final width = item._width ?? 1;
    final action = await resolveBitExpansionMenuValue(
      context,
      value: value,
      signalName: _subFieldDisplayText(item),
      width: width,
    );
    if (action == null || !context.mounted) {
      return;
    }

    switch (action) {
      case BitExpandRangeAction(:final bitStart, :final bitEnd):
        setState(() {
          _definedBitFields[subFieldId] = [
            for (var bit = bitEnd; bit >= bitStart; bit--)
              BitFieldDef(name: '[$bit]', high: bit, low: bit),
          ];
          _expandedSignals.add(subFieldId);
        });
      case BitDefineFieldsAction(:final fields):
        setState(() {
          _definedBitFields[subFieldId] = fields;
          _expandedSignals.add(subFieldId);
        });
    }
  }

  // ─── Tap handlers ──────────────────────────────────────────────────

  void _onSignalTap(BuildContext context, SignalOccurrence signal, int index) {
    if (_selectedSubFieldId != null) {
      setState(() {
        _selectedSubFieldId = null;
      });
    }
    final bloc = context.read<SignalBloc>();
    final isCtrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    if (isShift && _anchorIndex != null) {
      // Shift+click: range select from anchor to current index.
      bloc.add(
        ModuleSignalRangeSelectEvent(
          anchorIndex: _anchorIndex!,
          extentIndex: index,
        ),
      );
      return;
    }

    if (isCtrl) {
      // Ctrl+click: toggle this signal in selection.
      bloc.add(ModuleSignalToggleEvent(signal.path()));
    } else {
      // Plain click: select only this signal.
      bloc.add(ModuleSignalSelectEvent(signal.path()));
    }
    _anchorIndex = index;
  }

  /// Double-click adds to the monitor (Selected Signals) panel directly.
  void _onSignalDoubleTap(BuildContext context, SignalOccurrence signal) {
    // Fire the legacy onPortSelected callback.
    final rohdModuleState = context.read<RohdModuleBloc>().state;
    final selectedModule =
        rohdModuleState is ModuleSelected ? rohdModuleState.singleModule : null;
    final port = _signalToPort(signal);
    widget._onPortSelected?.call(port, selectedModule, signal);

    // Also add to monitor list.
    context.read<SignalBloc>().add(SignalSelectedEvent(signal));
  }

  // ─── Bit expand ────────────────────────────────────────────────────

  // ─── Define Bit Fields dialog ──────────────────────────────────────

  // ─── Context menu ──────────────────────────────────────────────────

  Future<void> _showContextMenu(
    BuildContext context,
    Offset globalPosition,
    SignalOccurrence signal,
  ) async {
    final bloc = context.read<SignalBloc>();
    final state = bloc.state;

    // If the right-clicked signal isn't selected, select it first.
    if (!state.isModuleSignalSelected(signal.path())) {
      bloc.add(ModuleSignalSelectEvent(signal.path()));
    }

    final selectedIds = state.isModuleSignalSelected(signal.path())
        ? state.moduleSelectedSignalIds
        : {signal.path()};
    final selectedSignals =
        state.signals.where((s) => selectedIds.contains(s.path()));
    final anyInMonitor = selectedSignals.any(
      (selectedSignal) => state.monitorSignalsList
          .any((waveform) => waveform.matchesOccurrence(selectedSignal)),
    );

    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final overlayPosition = overlay.localToGlobal(Offset.zero);

    // Hold the hierarchy overlay open while the context menu is visible.
    final overlayHold = HierarchyOverlayHold.of(context);
    overlayHold?.hold();

    final count = selectedIds.length;

    // Collect leaf names and full paths for copy operations.
    final leafNames = <String>[];
    final fullPaths = <String>[];
    for (final id in selectedIds) {
      final parts = id.split('/');
      leafNames.add(parts.last);
      fullPaths.add(id);
    }

    // Check if this is a single multi-bit signal that can be bit-expanded.
    final canBitExpand = count == 1 && signal.width > 1;

    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx - overlayPosition.dx,
        globalPosition.dy - overlayPosition.dy,
        overlay.size.width - (globalPosition.dx - overlayPosition.dx),
        overlay.size.height - (globalPosition.dy - overlayPosition.dy),
      ),
      items: [
        buildRohdPopupMenuItem<String>(
          value: 'add',
          icon: const Icon(Icons.add_circle_outline, size: 16),
          label: 'Add to Selected Signals',
        ),
        if (anyInMonitor)
          buildRohdPopupMenuItem<String>(
            value: 'remove',
            icon: const Icon(Icons.remove_circle_outline, size: 16),
            label: 'Remove from Selected Signals',
          ),
        buildSignalFormatMenuItem(count: count),
        if (canBitExpand) ...buildBitExpansionMenuItems(width: signal.width),
        if (widget._onSendSignals != null)
          buildRohdPopupMenuItem<String>(
            value: 'send',
            icon: const Icon(Icons.send, size: 16),
            label: count == 1 ? 'Send Signal' : 'Send $count Signals',
          ),
        if (widget._onGoToSource != null)
          ...buildGotoSourceMenuItems(
            formats: widget._availableSourceFormats?.call() ?? const [],
            count: count,
          ),
        buildRohdPopupMenuItem<String>(
          value: 'copy_name',
          icon: const Icon(Icons.content_copy, size: 16),
          label: count == 1 ? 'Copy Name' : 'Copy $count Names',
        ),
        buildRohdPopupMenuItem<String>(
          value: 'copy_path',
          icon: const Icon(Icons.account_tree, size: 16),
          label: count == 1 ? 'Copy Full Path' : 'Copy $count Full Paths',
        ),
      ],
    );

    // Release the hold so the overlay can auto-hide again.
    overlayHold?.release();

    if (!mounted) {
      return;
    }

    if (value == 'add') {
      bloc.add(ModuleSignalAddToMonitorEvent());
    } else if (value == 'remove') {
      bloc.add(ModuleSignalRemoveFromMonitorEvent());
    } else if (value == signalFormatMenuValue) {
      final addressById = {
        for (final s in state.signals) s.path(): s.address,
      };
      await showSignalFormatMenu(
        this.context,
        globalPosition: globalPosition,
        signalPaths: selectedIds,
        addresses: selectedIds.map((id) => addressById[id]),
      );
    } else if (value == BitExpansionMenuValues.expandBits ||
        value == BitExpansionMenuValues.defineFields) {
      await _handleBitExpansion(this.context, value!, signal);
    } else if (value == 'send') {
      widget._onSendSignals?.call(selectedIds.toList());
    } else if (gotoSourceFormatFromValue(value) != null) {
      widget._onGoToSource?.call(
        gotoSourceFormatFromValue(value)!,
        selectedIds.toList(),
      );
    } else if (value == 'copy_name') {
      await Clipboard.setData(ClipboardData(text: leafNames.join('\n')));
    } else if (value == 'copy_path') {
      await Clipboard.setData(ClipboardData(text: fullPaths.join('\n')));
    }
  }

  Future<void> _handleBitExpansion(
    BuildContext context,
    String value,
    SignalOccurrence signal,
  ) async {
    final action = await resolveBitExpansionMenuValue(
      context,
      value: value,
      signalName: signal.name,
      width: signal.width,
    );
    if (action == null || !context.mounted) {
      return;
    }
    switch (action) {
      case BitExpandRangeAction(:final bitStart, :final bitEnd):
        // Expand the bit range inline within the signal-selection list,
        // adding one single-bit sub-field row per bit (MSB→LSB to match
        // the waveform's bit ordering). This mirrors the inline behaviour
        // of "Define Bit Fields" rather than pushing bits straight into the
        // monitor/waveform list (which is what the Selected-Signals pane
        // intentionally does).
        final fields = <BitFieldDef>[
          for (var bit = bitEnd; bit >= bitStart; bit--)
            BitFieldDef(name: '[$bit]', high: bit, low: bit),
        ];
        setState(() {
          _definedBitFields[signal.path()] = fields;
          _expandedSignals.add(signal.path());
        });
      case BitDefineFieldsAction(:final fields):
        setState(() {
          _definedBitFields[signal.path()] = fields;
          _expandedSignals.add(signal.path());
        });
    }
  }

  // ─── Helpers ───────────────────────────────────────────────────────

  /// Convert SignalOccurrence to Port for callback.
  SignalOccurrence _signalToPort(SignalOccurrence signal) => SignalOccurrence(
        name: signal.name,
        direction: signal.direction ?? 'unknown',
        width: signal.width,
      );
}

/// A display item in the flattened signal list — either a signal row or an
/// expanded sub-field row.
class _DisplayItem {
  final SignalOccurrence? _signal;
  final SignalOccurrence? _parent;
  final String? _fieldLabel;
  final int? _width;
  final int? _startBit;
  final SignalOccurrence? _childSignal;

  /// For sub-fields that are themselves sub-arrays, the logicType map
  /// describing remaining dimensions.  Non-null means this item is expandable.
  final Map<String, Object?>? _subLogicType;

  /// Depth of nesting (0 = direct sub-field of a signal, 1 = sub-sub-field…).
  final int _depth;

  /// Composite path for identifying this item in expansion tracking.
  /// e.g. "serializer/deserialized#[0]#[1]"
  final String? _subFieldPath;

  /// User-defined display name for a bit-field (e.g. "exponent").
  /// When non-null, this item is a user-defined bit-field slice.
  final String? _bitFieldName;

  /// Display name assigned when this synthetic item is monitored.
  final String? _monitorDisplayName;

  bool get _isSubField => _signal == null;
  bool get _isExpandableSubField => _subLogicType != null;

  _DisplayItem.signal(SignalOccurrence s)
      : _signal = s,
        _parent = null,
        _fieldLabel = null,
        _width = null,
        _startBit = null,
        _childSignal = null,
        _subLogicType = null,
        _depth = 0,
        _subFieldPath = null,
        _bitFieldName = null,
        _monitorDisplayName = null;

  _DisplayItem.subField({
    required SignalOccurrence parent,
    required String fieldLabel,
    required int width,
    required int startBit,
    SignalOccurrence? childSignal,
    Map<String, Object?>? subLogicType,
    int depth = 0,
    String? subFieldPath,
    String? bitFieldName,
    String? monitorDisplayName,
  })  : _signal = null,
        _parent = parent,
        _fieldLabel = fieldLabel,
        _width = width,
        _startBit = startBit,
        _childSignal = childSignal,
        _subLogicType = subLogicType,
        _depth = depth,
        _subFieldPath = subFieldPath,
        _bitFieldName = bitFieldName,
        _monitorDisplayName = monitorDisplayName;
}
