// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// selected_signal_panel.dart
// The selected signals panel.
//
// 2024 April
// Author(s): Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
//            Yao Jing Quek <yao.jing.quek@intel.com>

import 'dart:async' show unawaited;

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
        GoToSourceCallback,
        buildBitExpansionMenuItems,
        buildGotoSourceMenuItems,
        buildRohdPopupMenuItem,
        gotoSourceFormatFromValue,
        resolveBitExpansionMenuValue;
import 'package:rohd_wave_viewer/src/const/const.dart';
import 'package:rohd_wave_viewer/src/cubit/waveform_scale_cubit.dart';
import 'package:rohd_wave_viewer/src/modules/shared/widgets/widgets.dart';
import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/signal/utils/signal_display_utils.dart';
import 'package:rohd_wave_viewer/src/modules/signal/view/signal_format_menu.dart';
import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';

/// Panel that shows the currently monitored signals.
class SelectedSignalsPanel extends StatefulWidget {
  final ScrollController? _scrollController;
  final DragReorderController? _dragController;
  final void Function(List<String> signalPaths)? _onSendSignals;
  final GoToSourceCallback? _onGoToSource;
  final AvailableSourceFormats? _availableSourceFormats;

  /// Creates the selected-signals panel.
  const SelectedSignalsPanel({
    super.key,
    ScrollController? scrollController,
    DragReorderController? dragController,
    void Function(List<String> signalPaths)? onSendSignals,
    GoToSourceCallback? onGoToSource,
    AvailableSourceFormats? availableSourceFormats,
  })  : _scrollController = scrollController,
        _dragController = dragController,
        _onSendSignals = onSendSignals,
        _onGoToSource = onGoToSource,
        _availableSourceFormats = availableSourceFormats;

  @override
  State<SelectedSignalsPanel> createState() => _SelectedSignalsPanelState();
}

class _SelectedSignalsPanelState extends State<SelectedSignalsPanel> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'SelectedSignalsPanel');
  final GlobalKey _dragViewportKey = GlobalKey();
  static const double _autoScrollEdgePx = 24;
  static const double _autoScrollStepPx = baseSignalRowHeight;

  /// Anchor index for shift-click range selection.
  /// Tracks the last non-shift-click index.
  int? _anchorIndex;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Vertical scroll helpers (mouse-wheel & arrow keys)
  // ---------------------------------------------------------------------------

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      final rh = context.read<WaveformScaleCubit>().scaledRowHeight;
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _scrollBy(-rh);
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _scrollBy(rh);
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.delete ||
          event.logicalKey == LogicalKeyboardKey.backspace) {
        _removeFocusedSignals(context);
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.keyA &&
          (HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed)) {
        context.read<SignalBloc>().add(SignalFocusAllEvent());
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _removeFocusedSignals(BuildContext context) {
    final bloc = context.read<SignalBloc>();
    final state = bloc.state;
    if (state is! SignalLoaded) {
      return;
    }
    final focusedIds = state.focusedSignalIds;
    if (focusedIds.isEmpty) {
      return;
    }

    bloc.add(SignalRemoveManyEvent(focusedIds));
  }

  void _scrollBy(double delta) {
    final controller = widget._scrollController;
    if (controller == null || !controller.hasClients) {
      return;
    }
    final maxExtent = controller.position.maxScrollExtent;
    final newOffset = (controller.offset + delta).clamp(0.0, maxExtent);
    if ((controller.offset - newOffset).abs() > 0.5) {
      controller.jumpTo(newOffset);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor =
        isDarkTheme ? const Color(0xFF1E1E1E) : Colors.white;

    return MouseRegion(
      onEnter: (_) => _focusNode.requestFocus(),
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: _handleKeyEvent,
        child: BlocBuilder<WaveformScaleCubit, double>(
          builder: (context, scale) {
            final rh = context.read<WaveformScaleCubit>().scaledRowHeight;
            return BlocBuilder<SignalBloc, SignalState>(
              builder: (content, state) => Column(
                children: [
                  const PanelHeader(headerText: selectedSignalsPanelTitle),
                  Expanded(
                    child: ClipRect(
                      child: LayoutBuilder(
                        builder: (context, innerConstraints) {
                          final fullRows =
                              (innerConstraints.maxHeight / rh).floor();
                          final effectiveHeight = fullRows * rh;
                          return Column(
                            children: [
                              SizedBox(
                                key: _dragViewportKey,
                                height: effectiveHeight,
                                child: ColoredBox(
                                  color: backgroundColor,
                                  child: switch (state) {
                                    SignalLoading() => const SizedBox.shrink(),
                                    SignalLoaded() => _buildSignalList(
                                        context,
                                        state,
                                        rh,
                                      ),
                                  },
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Scrollbar + ListView wrapper for the loaded signal list.
  ///
  /// Drag-reorder is handled via a shared [DragReorderController] so that
  /// all three panels (Selected Signals, Value, Waveform) animate together.
  Widget _buildSignalList(
    BuildContext context,
    SignalLoaded state,
    double rh,
  ) =>
      Scrollbar(
        interactive: true,
        thumbVisibility: true,
        trackVisibility: true,
        controller: widget._scrollController,
        child: Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              _scrollBy(event.scrollDelta.dy > 0 ? rh : -rh);
            }
          },
          child: ScrollConfiguration(
            behavior:
                ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: ListenableBuilder(
              listenable: widget._dragController ?? ChangeNotifier(),
              builder: (context, _) => ListView.builder(
                controller: widget._scrollController,
                physics: const ClampingScrollPhysics(),
                itemCount: state.monitorSignalsList.length,
                padding: EdgeInsets.only(bottom: rh + 28.0),
                itemExtent: rh,
                itemBuilder: (context, index) {
                  final signal = state.monitorSignalsList[index];
                  final isFocused = state.isSignalFocused(signal.monitorId);
                  return _buildSignalRow(
                    context,
                    state: state,
                    signal: signal,
                    index: index,
                    isFocused: isFocused,
                  );
                },
              ),
            ),
          ),
        ),
      );

  /// A single signal row with drag-to-reorder and tap-to-focus behaviour.
  Widget _buildSignalRow(
    BuildContext context, {
    required SignalLoaded state,
    required SignalWaveform signal,
    required int index,
    required bool isFocused,
  }) {
    final ctrl = widget._dragController;
    final translateY = ctrl?.getRowTranslateY(index) ?? 0;
    final isSource = ctrl?.isSourceRow(index) ?? false;

    return Transform.translate(
      offset: Offset(0, translateY),
      child: GestureDetector(
        onVerticalDragStart: (_) {
          debugPrint(
            '[SelectedSignalDrag] startDrag: itemBuilder index=$index, '
            'signal=${signal.signalId}',
          );
          List<int>? groupIndices;
          if (isFocused && state.focusedSignalIds.length > 1) {
            groupIndices = <int>[];
            final list = state.monitorSignalsList;
            for (var i = 0; i < list.length; i++) {
              if (state.focusedSignalIds.contains(list[i].monitorId)) {
                groupIndices.add(i);
              }
            }
          }
          ctrl?.startDrag(
            index,
            state.monitorSignalsList.length,
            groupIndices: groupIndices,
          );
        },
        onVerticalDragUpdate: (details) {
          _autoScrollWhileDragging(details.globalPosition);
          ctrl?.updateDrag(details.delta.dy);
        },
        onVerticalDragEnd: (_) => _commitDrag(context),
        onVerticalDragCancel: () => ctrl?.cancelDrag(),
        onTap: () => _onSignalTap(context, signal, isFocused, index),
        onSecondaryTapUp: (details) {
          unawaited(
            _showSignalContextMenu(
              context,
              details.globalPosition,
              state,
              signal,
              index,
              isFocused,
            ),
          );
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: Container(
            height: context.read<WaveformScaleCubit>().scaledRowHeight,
            decoration: BoxDecoration(
              color: isSource
                  ? Colors.yellow.withValues(alpha: 0.35)
                  : _rowColor(index, isFocused),
              boxShadow: isSource
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: SignalTabContainer(
              containerBody: Row(
                children: [
                  // Indent expanded bit-slice children.
                  if (signal.signalId.contains('#')) const SizedBox(width: 16),
                  if (signal.signal != null &&
                      (signal.signal!.isStruct || signal.signal!.isArray))
                    _ExpandCollapseIcon(
                      isExpanded: state.expandedMonitorSignals.contains(
                        signal.id,
                      ),
                      onToggle: (globalPosition) {
                        // Collapse if already expanded.
                        if (state.expandedMonitorSignals.contains(signal.id)) {
                          context.read<SignalBloc>().add(
                                SignalCollapseMonitorEvent(waveform: signal),
                              );
                        } else {
                          unawaited(
                            _showFieldPickerMenu(
                              context,
                              signal: signal,
                              index: index,
                              tapPosition: globalPosition,
                            ),
                          );
                        }
                      },
                    )
                  else
                    const SizedBox(width: 24),
                  Expanded(
                    child: Tooltip(
                      message: '${signal.fullPath ?? signal.signalId} '
                          '(${signal.width})',
                      waitDuration: const Duration(milliseconds: 400),
                      child: Text(
                        formatSignalNameWithWidth(
                          state.getDisplayNameForSignal(signal),
                          signal.width,
                        ),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize:
                              14.0 * context.read<WaveformScaleCubit>().state,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white
                              : Colors.black87,
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

  void _autoScrollWhileDragging(Offset globalPosition) {
    final ctrl = widget._dragController;
    final controller = widget._scrollController;
    if (ctrl == null || !ctrl.isDragging) {
      return;
    }
    if (controller == null || !controller.hasClients) {
      return;
    }

    final box =
        _dragViewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }

    final viewportY = box.globalToLocal(globalPosition).dy;
    final viewportH = box.size.height;

    var desiredDelta = 0.0;
    if (viewportY < _autoScrollEdgePx) {
      desiredDelta = -_autoScrollStepPx;
    } else if (viewportY > viewportH - _autoScrollEdgePx) {
      desiredDelta = _autoScrollStepPx;
    }
    if (desiredDelta == 0.0) {
      return;
    }

    final oldOffset = controller.offset;
    final newOffset = (oldOffset + desiredDelta).clamp(
      0.0,
      controller.position.maxScrollExtent,
    );
    final appliedDelta = newOffset - oldOffset;
    if (appliedDelta.abs() <= 0.01) {
      return;
    }

    controller.jumpTo(newOffset);
    ctrl.updateDrag(appliedDelta);
  }

  /// Commit the current drag-reorder.
  void _commitDrag(BuildContext context) {
    final result = widget._dragController?.endDrag();
    if (result != null) {
      if (result.groupOldIndices != null) {
        context.read<SignalBloc>().add(
              SignalGroupReorderEvent(
                oldIndices: result.groupOldIndices!,
                anchorOldIndex: result.oldIndex,
                anchorNewIndex: result.newIndex,
              ),
            );
      } else {
        context.read<SignalBloc>().add(
              SignalReorderEvent(
                oldIndex: result.oldIndex,
                newIndex: result.newIndex,
              ),
            );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Handle tap on a signal row — focus, unfocus, multi-select, or
  /// shift-click range-select.
  void _onSignalTap(
    BuildContext context,
    SignalWaveform signal,
    bool isFocused,
    int index,
  ) {
    // Ensure this panel has keyboard focus so DEL/Backspace work immediately.
    _focusNode.requestFocus();

    final isMultiSelect = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    if (isShift && _anchorIndex != null) {
      // Shift-click: select range from anchor to current index
      context.read<SignalBloc>().add(
            SignalRangeFocusEvent(
                anchorIndex: _anchorIndex!, extentIndex: index),
          );
      // Don't update anchor — allow extending the range with another
      // shift-click from the same anchor.
      return;
    }

    if (isFocused && !isMultiSelect) {
      context.read<SignalBloc>().add(SignalUnfocusEvent());
      _anchorIndex = null;
    } else if (isFocused && isMultiSelect) {
      context.read<SignalBloc>().add(SignalUnfocusOneEvent(signal.id));
      // Keep anchor as-is for subsequent shift-clicks
    } else {
      context.read<SignalBloc>().add(
            SignalFocusEvent(signal, isMultiSelect: isMultiSelect),
          );
      // Update anchor to the clicked row (for future shift-clicks)
      _anchorIndex = index;
    }
  }

  /// Show a popup menu to select which sub-fields to expand.
  ///
  /// For structs: shows each field with name and width.
  /// For arrays: shows a scrollable list of elements + "All" + range option.
  ///
  /// If the number of fields/elements is at or below a threshold, expands
  /// immediately without prompting.
  Future<void> _showFieldPickerMenu(
    BuildContext context, {
    required SignalWaveform signal,
    required int index,
    required Offset tapPosition,
  }) async {
    final signalOccurrence = signal.signal!;
    final descriptors = signalOccurrence.subFieldDescriptors;
    if (descriptors.isEmpty) {
      return;
    }

    final isArray = signalOccurrence.isArray;
    final numFields = descriptors.length;

    // Small enough — expand all immediately without a popup.
    const expandThreshold = 8;
    if (numFields <= expandThreshold) {
      context.read<SignalBloc>().add(
            SignalExpandMonitorEvent(waveform: signal, index: index),
          );
      return;
    }

    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;

    // Position the menu near the tap.
    final local = overlay.globalToLocal(tapPosition);

    // Build menu items.
    final items = <PopupMenuEntry<dynamic>>[
      PopupMenuItem<String>(
        height: 32,
        value: 'all',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.unfold_more, size: 14),
            const SizedBox(width: 8),
            Text(
              'Expand All ($numFields ${isArray ? "elements" : "fields"})',
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
    ]
        // "Expand All" option.
        ;

    // For arrays with many elements, add a range option.
    if (isArray && numFields > 4) {
      items.add(
        PopupMenuItem<String>(
          height: 32,
          value: 'range',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.linear_scale, size: 14),
              const SizedBox(width: 8),
              Text(
                'Select Range (0:${numFields - 1})...',
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    items.add(const PopupMenuDivider(height: 8));

    // Individual field items (limit visible list for very large arrays).
    final maxVisible = isArray ? 20 : numFields;
    final showCount = numFields <= maxVisible ? numFields : maxVisible;
    for (var i = 0; i < showCount; i++) {
      final desc = descriptors[i];
      final label = isArray ? desc.fieldLabel : desc.fieldLabel;
      items.add(
        PopupMenuItem<int>(
          height: 28,
          value: i,
          child: Text(
            '$label  [${desc.width}b]',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      );
    }
    if (numFields > maxVisible) {
      items.add(
        PopupMenuItem<String>(
          height: 28,
          enabled: false,
          value: 'more',
          child: Text(
            '... ${numFields - maxVisible} more (use Range)',
            style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor),
          ),
        ),
      );
    }

    final value = await showMenu<dynamic>(
      context: context,
      position: RelativeRect.fromLTRB(
        local.dx,
        local.dy + 24,
        overlay.size.width - local.dx - 200,
        overlay.size.height - local.dy - 24,
      ),
      items: items,
    );

    if (value == null || !context.mounted) {
      return;
    }
    final bloc = context.read<SignalBloc>();
    if (value == 'all') {
      bloc.add(SignalExpandMonitorEvent(waveform: signal, index: index));
    } else if (value == 'range') {
      await _showRangeInputDialog(context, signal: signal, index: index);
    } else if (value is int) {
      bloc.add(
        SignalExpandMonitorEvent(
          waveform: signal,
          index: index,
          fieldIndices: [value],
        ),
      );
    }
  }

  /// Show a small dialog to input a range (start:end) for array expansion.
  Future<void> _showRangeInputDialog(
    BuildContext context, {
    required SignalWaveform signal,
    required int index,
  }) async {
    final signalOccurrence = signal.signal!;
    final numElements = signalOccurrence.subFieldDescriptors.length;
    final maxIndex = numElements - 1;
    final controller = TextEditingController(text: '0:$maxIndex');
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );

    final result = await showDialog<String>(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) => AlertDialog(
        title: Text(
          '${signalOccurrence.name}  [$numElements elements]',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Range (start:end) or single index',
            hintText: '0:$maxIndex',
            isDense: true,
          ),
          onSubmitted: (value) => Navigator.of(ctx).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    if (result == null || result.trim().isEmpty) {
      return;
    }
    final parsed = _parseSliceRange(result.trim(), maxIndex);
    if (parsed == null) {
      return;
    }

    final (start, end) = parsed;
    final indices = List.generate(end - start + 1, (i) => start + i);

    if (!context.mounted) {
      return;
    }
    context.read<SignalBloc>().add(
          SignalExpandMonitorEvent(
            waveform: signal,
            index: index,
            fieldIndices: indices,
          ),
        );
  }

  /// Parse a slice range string into (start, end) inclusive bounds.
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

  /// Show a right-click context menu for the signal row.
  Future<void> _showSignalContextMenu(
    BuildContext context,
    Offset globalPosition,
    SignalLoaded state,
    SignalWaveform signal,
    int index,
    bool isFocused,
  ) async {
    // If the right-clicked row isn't already focused, focus it (solo).
    if (!isFocused) {
      context.read<SignalBloc>().add(SignalFocusEvent(signal));
      _anchorIndex = index;
    }

    // Collect the effective selection: all focused signals, or just this one.
    final selectedSignals = isFocused
        ? state.monitorSignalsList
            .where((s) => state.focusedSignalIds.contains(s.monitorId))
            .toList()
        : <SignalWaveform>[signal];

    final paths = selectedSignals.map((s) => s.fullPath ?? s.signalId).toList();
    final leafNames = selectedSignals.map((s) => s.name).toList();
    final count = paths.length;

    // Check if this is a single multi-bit signal that can be bit-expanded.
    final canBitExpand = count == 1 && (selectedSignals.first.width) > 1;
    final signalWidth = canBitExpand ? selectedSignals.first.width : 0;

    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final local = overlay.globalToLocal(globalPosition);

    final bloc = context.read<SignalBloc>();

    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        local.dx,
        local.dy,
        overlay.size.width - local.dx,
        overlay.size.height - local.dy,
      ),
      items: [
        if (widget._onSendSignals != null)
          buildRohdPopupMenuItem<String>(
            value: 'send',
            icon: const Icon(Icons.send, size: 16),
            label: count == 1 ? 'Send Signal' : 'Send $count Signals',
            textStyle: const TextStyle(fontSize: 13),
          ),
        if (widget._onGoToSource != null)
          ...buildGotoSourceMenuItems(
            formats: widget._availableSourceFormats?.call() ?? const [],
            count: count,
            textStyle: const TextStyle(fontSize: 13),
          ),
        buildRohdPopupMenuItem<String>(
          value: 'copy_name',
          icon: const Icon(Icons.content_copy, size: 16),
          label: count == 1 ? 'Copy Name' : 'Copy $count Names',
          textStyle: const TextStyle(fontSize: 13),
        ),
        buildRohdPopupMenuItem<String>(
          value: 'copy_path',
          icon: const Icon(Icons.account_tree, size: 16),
          label: count == 1 ? 'Copy Full Path' : 'Copy $count Full Paths',
          textStyle: const TextStyle(fontSize: 13),
        ),
        if (canBitExpand) ...buildBitExpansionMenuItems(width: signalWidth),
        buildSignalFormatMenuItem(count: count),
        buildRohdPopupMenuItem<String>(
          value: 'remove',
          icon: const Icon(Icons.remove_circle_outline, size: 16),
          label: count == 1 ? 'Remove Signal' : 'Remove $count Signals',
          textStyle: const TextStyle(fontSize: 13),
        ),
      ],
    );

    if (!mounted) {
      return;
    }
    if (value == 'send') {
      // For sub-field signals (containing '#'), send the parent path
      // which has an actual OccurrenceAddress in the hierarchy.
      final sendPaths = paths
          .map((p) {
            final hashIdx = p.indexOf('#');
            return hashIdx >= 0 ? p.substring(0, hashIdx) : p;
          })
          .toSet()
          .toList();
      widget._onSendSignals?.call(sendPaths);
    } else if (value == 'copy_name') {
      await Clipboard.setData(ClipboardData(text: leafNames.join('\n')));
    } else if (value == 'copy_path') {
      await Clipboard.setData(ClipboardData(text: paths.join('\n')));
    } else if (value == 'remove') {
      for (final s in selectedSignals) {
        bloc.add(SignalRemoveEvent(s));
      }
    } else if (value == signalFormatMenuValue) {
      await showSignalFormatMenu(
        this.context,
        globalPosition: globalPosition,
        signalPaths:
            selectedSignals.map((s) => s.fullPath ?? s.signalId).toSet(),
        addresses: selectedSignals.map((s) => s.signal?.address),
      );
    } else if (gotoSourceFormatFromValue(value) != null) {
      widget._onGoToSource?.call(gotoSourceFormatFromValue(value)!, paths);
    } else if (value == BitExpansionMenuValues.expandBits ||
        value == BitExpansionMenuValues.defineFields) {
      await _handleBitExpansion(
        this.context,
        value!,
        selectedSignals.first,
        index,
      );
    }
  }

  /// Resolve a bit-expansion popup-menu selection and dispatch the
  /// matching [SignalBitExpandEvent] / [SignalBitFieldsEvent].
  Future<void> _handleBitExpansion(
    BuildContext context,
    String value,
    SignalWaveform signal,
    int index,
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
    final bloc = context.read<SignalBloc>();
    switch (action) {
      case BitExpandRangeAction(:final bitStart, :final bitEnd):
        bloc.add(
          SignalBitExpandEvent(
            waveform: signal,
            index: index,
            bitStart: bitStart,
            bitEnd: bitEnd,
          ),
        );
      case BitDefineFieldsAction(:final fields):
        bloc.add(
          SignalBitFieldsEvent(waveform: signal, index: index, fields: fields),
        );
    }
  }

  /// Determine the background colour for a signal row.
  Color _rowColor(int index, bool isFocused) {
    if (isFocused) {
      return Colors.blue.withValues(alpha: 0.35);
    }
    return Colors.transparent;
  }
}

/// A small expand/collapse icon that handles taps via raw pointer events,
/// bypassing the parent GestureDetector's gesture arena (which includes
/// a vertical drag recognizer that would otherwise swallow the tap).
class _ExpandCollapseIcon extends StatefulWidget {
  final bool _isExpanded;
  final void Function(Offset globalPosition) _onToggle;

  const _ExpandCollapseIcon({
    required bool isExpanded,
    required void Function(Offset globalPosition) onToggle,
  })  : _isExpanded = isExpanded,
        _onToggle = onToggle;

  @override
  State<_ExpandCollapseIcon> createState() => _ExpandCollapseIconState();
}

class _ExpandCollapseIconState extends State<_ExpandCollapseIcon> {
  @override
  Widget build(BuildContext context) => RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: <Type, GestureRecognizerFactory>{
          _EagerTapRecognizer:
              GestureRecognizerFactoryWithHandlers<_EagerTapRecognizer>(
            _EagerTapRecognizer.new,
            (instance) {
              instance.onTapUp =
                  (details) => widget._onToggle(details.globalPosition);
            },
          ),
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Icon(
              widget._isExpanded ? Icons.expand_more : Icons.chevron_right,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      );
}

/// A tap recognizer that immediately claims the gesture arena,
/// preventing parent GestureDetectors from receiving the event.
class _EagerTapRecognizer extends TapGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    // Immediately win the arena so the parent's drag/tap recognizers
    // never see this pointer.
    resolve(GestureDisposition.accepted);
  }
}
