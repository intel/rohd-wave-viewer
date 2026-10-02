// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_value_panel.dart
// The signal value panel.
//
// 2024 April
// Author(s): Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
//            Yao Jing Quek <yao.jing.quek@intel.com>

import 'dart:async' show unawaited;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_wave_viewer/src/const/const.dart';
import 'package:rohd_wave_viewer/src/cubit/waveform_scale_cubit.dart';
import 'package:rohd_wave_viewer/src/modules/rohd_module/bloc/rohd_module_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/shared/widgets/widgets.dart';
import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/signal/view/signal_format_menu.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/bloc/waveform_module_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/view/widgets/painters/waveform.dart';
import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';

/// Panel that shows values for monitored signals at the active time.
class SignalValuePanel extends StatelessWidget {
  final ScrollController? _scrollController;
  static const double _autoScrollEdgePx = 24;
  static const double _autoScrollStepPx = baseSignalRowHeight;

  final DragReorderController? _dragController;
  final bool _isVideoMode;

  /// Creates the signal value panel.
  const SignalValuePanel({
    super.key,
    ScrollController? scrollController,
    DragReorderController? dragController,
    bool isVideoMode = false,
  })  : _scrollController = scrollController,
        _dragController = dragController,
        _isVideoMode = isVideoMode;

  /// Scroll the panel's controller by [delta] pixels (snapped to rows).
  void _scrollBy(double delta) {
    final controller = _scrollController;
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

    return BlocBuilder<WaveformScaleCubit, double>(
      builder: (context, scale) {
        final rh = context.read<WaveformScaleCubit>().scaledRowHeight;
        return _buildKeyboardScrollablePanel(
          context,
          rowHeight: rh,
          backgroundColor: backgroundColor,
        );
      },
    );
  }

  Widget _buildKeyboardScrollablePanel(
    BuildContext context, {
    required double rowHeight,
    required Color backgroundColor,
  }) =>
      Focus(
        onKeyEvent: (node, event) => _handleKeyEvent(event, rowHeight),
        child: Builder(
          builder: (focusContext) => Listener(
            onPointerDown: (_) => Focus.of(focusContext).requestFocus(),
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                _scrollBy(event.scrollDelta.dy > 0 ? rowHeight : -rowHeight);
              }
            },
            child: _buildSignalValuePanelBody(
              context,
              rowHeight: rowHeight,
              backgroundColor: backgroundColor,
            ),
          ),
        ),
      );

  KeyEventResult _handleKeyEvent(KeyEvent event, double rowHeight) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _scrollBy(-rowHeight);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _scrollBy(rowHeight);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  Widget _buildSignalValuePanelBody(
    BuildContext context, {
    required double rowHeight,
    required Color backgroundColor,
  }) =>
      BlocBuilder<SignalBloc, SignalState>(
        builder: (signalCtx, signalState) => Column(
          children: [
            const PanelHeader(headerText: signalsValuePanelTitle),
            Expanded(
              child: ClipRect(
                child: LayoutBuilder(
                  builder: (context, innerConstraints) {
                    final fullRows =
                        (innerConstraints.maxHeight / rowHeight).floor();
                    final effectiveHeight = fullRows * rowHeight;
                    return SizedBox(
                      height: effectiveHeight,
                      child: ColoredBox(
                        color: backgroundColor,
                        child: _buildWaveformValueContent(
                          context,
                          signalState: signalState,
                          rowHeight: rowHeight,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      );

  Widget _buildWaveformValueContent(
    BuildContext context, {
    required SignalState signalState,
    required double rowHeight,
  }) =>
      BlocBuilder<WaveformModuleBloc, WaveformModuleState>(
        builder: (context, state) {
          if (_isVideoMode) {
            return _buildVideoModeValueContent(context, signalState);
          }

          return switch (state) {
            InitialCursor() => _buildEmptyCursorList(context, rowHeight),
            UpdatedCursor() => updateSignalValue(
                context,
                state,
                signalState.monitorSignalsList,
              ),
            WaveformModuleError() => const Text(bugReport),
          };
        },
      );

  Widget _buildVideoModeValueContent(
    BuildContext context,
    SignalState signalState,
  ) {
    final rohdState = context.watch<RohdModuleBloc>().state;
    final endTime = rohdState.moduleStructure.metadata.endTime;
    int? dataEnd;
    if (rohdState is WaveformUpdated) {
      dataEnd = rohdState.dataEndTime;
    }

    final videoTime = dataEnd ?? endTime;
    if (videoTime <= 0) {
      return const SizedBox.shrink();
    }

    return updateSignalValue(
      context,
      UpdatedCursor(videoTime),
      signalState.monitorSignalsList,
    );
  }

  Widget _buildEmptyCursorList(BuildContext context, double rowHeight) =>
      ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: ListView.builder(
          controller: _scrollController,
          physics: const ClampingScrollPhysics(),
          itemExtent: rowHeight,
          padding: const EdgeInsets.only(bottom: 28),
          itemCount: 1,
          itemBuilder: (context, index) =>
              const SignalTabContainer(containerBody: Text('')),
        ),
      );

  /// Builds the list of signal values for the active cursor state.
  Widget updateSignalValue(
    BuildContext context,
    WaveformModuleState state,
    List<SignalWaveform> monitorSignalList,
  ) {
    final valueList = <String>[];

    for (final signal in monitorSignalList) {
      final scaleTime = state.timePs;
      final val = signal.getValueByTime(scaleTime);
      // Also compute the last-before value using the same binary-search
      // approach used by the waveform painters to detect mismatches.
      String? computed;
      final data = signal.data;
      if (data.isEmpty) {
        computed = null;
      } else {
        var lo = 0;
        var hi = data.length - 1;
        var res = -1;
        while (lo <= hi) {
          final mid = (lo + hi) >> 1;
          if (data[mid].time <= scaleTime) {
            res = mid;
            lo = mid + 1;
          } else {
            hi = mid - 1;
          }
        }
        if (res != -1) {
          computed = data[res].value;
        }
      }

      // Log any differences between the two lookup methods to help debug
      // marker vs painter/value-panel inconsistencies.
      if (computed != null && val != computed) {
        throw StateError(
          'Value mismatch for ${signal.fullPath ?? signal.name} '
          'at timePs=$scaleTime: getValueByTime=$val, '
          'getValueAtOrBefore=$computed, dataLen=${data.length}',
        );
      }

      valueList.add(
        Waveform.formatValueForDisplay(
          val,
          signal.valueFormat,
          signal.width,
        ),
      );
    }

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: ListenableBuilder(
        listenable: _dragController ?? ChangeNotifier(),
        builder: (context, _) => ListView.builder(
          controller: _scrollController,
          physics: const ClampingScrollPhysics(),
          clipBehavior: Clip.none,
          itemExtent: context.watch<WaveformScaleCubit>().scaledRowHeight,
          padding: EdgeInsets.only(
            bottom: context.watch<WaveformScaleCubit>().scaledRowHeight + 28.0,
          ),
          itemCount: monitorSignalList.length,
          itemBuilder: (context, index) {
            // If all values haven't been populated yet (e.g., when signals list
            // is empty), just show blank rows so the pane can still be scrolled
            // in sync with selected signals.
            if (index >= valueList.length) {
              return const SignalTabContainer(containerBody: Text(''));
            }
            final value = valueList[index];
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final ctrl = _dragController;
            final translateY = ctrl?.getRowTranslateY(index) ?? 0;
            final isSource = ctrl?.isSourceRow(index) ?? false;
            return Transform.translate(
              offset: Offset(0, translateY),
              child: GestureDetector(
                onSecondaryTapUp: (details) {
                  final currentSignal = monitorSignalList[index];
                  final loaded = context.read<SignalBloc>().state;
                  final selectedSignals = loaded is SignalLoaded &&
                          loaded.focusedSignalIds
                              .contains(currentSignal.monitorId)
                      ? loaded.focusedSignals
                      : <SignalWaveform>[currentSignal];
                  if (loaded is! SignalLoaded ||
                      !loaded.focusedSignalIds
                          .contains(currentSignal.monitorId)) {
                    context.read<SignalBloc>().add(
                          SignalFocusEvent(currentSignal),
                        );
                  }
                  unawaited(
                    showSignalFormatMenu(
                      context,
                      globalPosition: details.globalPosition,
                      signalPaths: selectedSignals
                          .map((signal) => signal.fullPath ?? signal.signalId)
                          .toSet(),
                      addresses: selectedSignals
                          .map((signal) => signal.signal?.address),
                    ),
                  );
                },
                onVerticalDragStart: (_) {
                  List<int>? groupIndices;
                  final signalState = context.read<SignalBloc>().state;
                  if (signalState is SignalLoaded &&
                      signalState.focusedSignalIds.length > 1) {
                    final list = signalState.monitorSignalsList;
                    if (index < list.length &&
                        signalState.focusedSignalIds
                            .contains(list[index].monitorId)) {
                      groupIndices = <int>[];
                      for (var i = 0; i < list.length; i++) {
                        if (signalState.focusedSignalIds
                            .contains(list[i].monitorId)) {
                          groupIndices.add(i);
                        }
                      }
                    }
                  }
                  ctrl?.startDrag(
                    index,
                    monitorSignalList.length,
                    groupIndices: groupIndices,
                  );
                },
                onVerticalDragUpdate: (details) {
                  _autoScrollWhileDragging(context, details.globalPosition);
                  ctrl?.updateDrag(details.delta.dy);
                },
                onVerticalDragEnd: (_) => _commitDrag(context),
                onVerticalDragCancel: () => ctrl?.cancelDrag(),
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: isSource
                          ? Colors.yellow.withValues(alpha: 0.35)
                          : null,
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
                      containerBody: Text(
                        value,
                        style: TextStyle(
                          fontSize:
                              14.0 * context.read<WaveformScaleCubit>().state,
                          // Yellow for computed/synthesized values
                          // (gate evaluation), matching schematic viewer.
                          color: (index < monitorSignalList.length &&
                                  monitorSignalList[index].isComputed)
                              ? const Color(0xFFFFD54F)
                              : isDark
                                  ? Colors.white
                                  : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _autoScrollWhileDragging(BuildContext context, Offset globalPosition) {
    final ctrl = _dragController;
    final controller = _scrollController;
    if (ctrl == null || !ctrl.isDragging) {
      return;
    }
    if (controller == null || !controller.hasClients) {
      return;
    }

    final scrollable = Scrollable.maybeOf(context);
    final box = scrollable?.context.findRenderObject() as RenderBox?;
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
    final result = _dragController?.endDrag();
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

  /// Converts gesture coordinates to waveform-relative coordinates.
  Offset adjustPropotion(BuildContext context, Offset adjustedOffset) {
    // 1. Get the width of the total canvas
    final canvasWidth = MediaQuery.of(context).size.width;

    // 2. Define the maximum scale value from module metadata (endTime)
    var maxScaleValue = 20.0;
    try {
      final rohdModuleState = BlocProvider.of<RohdModuleBloc>(context).state;
      final endTime = rohdModuleState.moduleStructure.metadata.endTime;
      if (endTime > 0) {
        maxScaleValue = endTime.toDouble();
      }
    } on Object catch (_) {
      // Keep default maxScaleValue if RohdModuleBloc isn't available
    }

    // 3. Calculate the ratio
    final ratio = maxScaleValue / canvasWidth;

    // 4. Adjust the offset based on the ratio
    final scaledOffset = Offset(
      adjustedOffset.dx * ratio,
      adjustedOffset.dy * ratio,
    );

    return scaledOffset;
  }
}
