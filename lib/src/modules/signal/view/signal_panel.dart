// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_panel.dart
// The signal panel.
//
// 2024 April
// Author(s): Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
//            Yao Jing Quek <yao.jing.quek@intel.com>

import 'dart:async' show unawaited;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_wave_viewer/src/modules/hierarchy/hierarchy_overlay.dart';
import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/signal/utils/signal_display_utils.dart';

/// Panel that shows signals available in the selected module.
class SignalPanel extends StatelessWidget {
  /// Creates the signal panel.
  const SignalPanel({super.key});

  @override
  Widget build(BuildContext context) => BlocBuilder<SignalBloc, SignalState>(
        builder: (content, state) {
          if (state is SignalLoading) {
            return const Text('');
          } else if (state is SignalLoaded) {
            return SignalList(signals: state.filteredSignals);
          } else {
            return Container();
          }
        },
      );
}

/// Scrollable list of available signals for the selected module.
class SignalList extends StatefulWidget {
  final List<SignalOccurrence> _signals;

  /// Creates a signal list.
  const SignalList({required List<SignalOccurrence> signals, super.key})
      : _signals = signals;

  @override
  State<SignalList> createState() => _SignalListState();
}

class _SignalListState extends State<SignalList> {
  /// Set of signal names that are currently expanded to show sub-fields.
  final Set<String> _expandedSignals = {};

  /// For array signals, the currently visible element slice [start, end]
  /// (inclusive).  Absent key = struct (show all fields).
  final Map<String, (int, int)> _arraySliceRanges = {};

  @override
  Widget build(BuildContext context) {
    if (widget._signals.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No signals available'),
      );
    }

    // Build flat display list with expanded sub-fields interleaved.
    final rows = <Widget>[];
    for (final signal in widget._signals) {
      final isExpandable = signal.isStruct || signal.isArray;
      final isExpanded = _expandedSignals.contains(signal.name);

      rows.add(_buildSignalRow(context, signal, isExpandable, isExpanded));

      // If expanded, show sub-field rows indented below.
      if (isExpanded) {
        rows.addAll(_buildSubFieldRows(context, signal));
      }
    }

    return ListView(children: rows);
  }

  Widget _buildSignalRow(
    BuildContext context,
    SignalOccurrence signal,
    bool isExpandable,
    bool isExpanded,
  ) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          context.read<SignalBloc>().add(SignalSelectedEvent(signal));
        },
        child: Padding(
          padding: const EdgeInsets.only(top: 5, left: 10, right: 10),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              color: Colors.transparent,
              child: Row(
                children: [
                  if (isExpandable)
                    GestureDetector(
                      onTapDown: (details) {
                        if (isExpanded) {
                          setState(() {
                            _expandedSignals.remove(signal.name);
                            _arraySliceRanges.remove(signal.name);
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
                            _expandedSignals.add(signal.name);
                          });
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(
                          isExpanded ? Icons.expand_more : Icons.chevron_right,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      formatSignalNameWithWidth(signal.name, signal.width),
                    ),
                  ),
                  if (isExpandable)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        signal.typeName ??
                            (signal.isArray ? 'array' : 'struct'),
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).hintColor,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );

  /// Show a dialog to select the array element range to expand.
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
      _expandedSignals.add(signal.name);
      _arraySliceRanges[signal.name] = parsed;
    });
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

  /// Build indented sub-field rows for an expanded struct/array signal.
  List<Widget> _buildSubFieldRows(
    BuildContext context,
    SignalOccurrence parentSignal,
  ) {
    final module = parentSignal.parent;
    final descriptors = parentSignal.subFieldDescriptors;
    if (descriptors.isEmpty) {
      return const [];
    }

    final sliceRange = _arraySliceRanges[parentSignal.name];
    return descriptors.indexed.where((entry) {
      if (sliceRange == null) {
        return true;
      }
      final (start, end) = sliceRange;
      return entry.$1 >= start && entry.$1 <= end;
    }).map((entry) {
      final desc = entry.$2;
      // Try to find the sub-field as a real signal in the same module.
      SignalOccurrence? childSignal;
      if (module != null) {
        final idx = module.signalIndexByName(desc.expectedName);
        if (idx >= 0) {
          childSignal = module.signals[idx];
        }
      }

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (childSignal != null) {
            // Sub-field exists as its own tracked signal — add it directly.
            context.read<SignalBloc>().add(
                  SignalSelectedEvent(childSignal),
                );
          } else {
            // Fallback: use bit-slice path for computed extraction.
            context.read<SignalBloc>().add(
                  SignalSubFieldSelectedEvent(
                    parentSignal: parentSignal,
                    fieldLabel: desc.fieldLabel,
                    startBit: desc.startBit,
                    width: desc.width,
                  ),
                );
          }
        },
        child: Padding(
          padding: const EdgeInsets.only(top: 2, left: 30, right: 10),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              color: Colors.transparent,
              child: Row(
                children: [
                  Icon(
                    childSignal != null
                        ? Icons.subdirectory_arrow_right
                        : Icons.functions,
                    size: 14,
                    color: Theme.of(context).hintColor,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      formatSignalNameWithWidth(
                        desc.fieldLabel,
                        desc.width,
                      ),
                      style: TextStyle(
                        fontSize: 13,
                        color: childSignal != null
                            ? null
                            : Theme.of(context).hintColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }).toList();
  }
}
