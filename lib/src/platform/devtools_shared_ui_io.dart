// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// devtools_shared_ui_io.dart
// Standalone implementation of shared DevTools UI components.
//
// 2026 August
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:material_ui/material_ui.dart';

/// Header row used for area panes in standalone layouts.
class AreaPaneHeader extends StatelessWidget {
  /// Header title widget.
  final Widget title;

  /// Action widgets shown on the trailing edge.
  final List<Widget> actions;

  /// Creates an area pane header.
  const AreaPaneHeader({
    required this.title,
    this.actions = const <Widget>[],
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF3C3C3C) : const Color(0xFFE0E0E0),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: DefaultTextStyle.merge(
              style: const TextStyle(fontWeight: FontWeight.w600),
              child: title,
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// Resizable split pane for arranging multiple child areas.
class SplitPane extends StatefulWidget {
  /// Split direction.
  final Axis _axis;

  /// Initial fractional sizes for each child.
  final List<double> _initialFractions;

  /// Minimum pixel sizes for each child.
  final List<double> _minSizes;

  /// Child panes to render.
  final List<Widget> _children;

  /// Creates a resizable split pane.
  const SplitPane({
    required Axis axis,
    required List<double> initialFractions,
    required List<Widget> children,
    super.key,
    List<double> minSizes = const <double>[],
  })  : _axis = axis,
        _initialFractions = initialFractions,
        _children = children,
        _minSizes = minSizes;

  @override
  State<SplitPane> createState() => _SplitPaneState();
}

class _SplitPaneState extends State<SplitPane> {
  static const _dividerExtent = 6.0;
  late List<double> _fractions;

  @override
  void initState() {
    super.initState();
    _fractions = List<double>.from(widget._initialFractions);
    final sum =
        _fractions.fold<double>(0, (total, fraction) => total + fraction);
    if (sum > 0) {
      _fractions = _fractions.map((fraction) => fraction / sum).toList();
    }
  }

  void _dragDivider(int index, double deltaPx, double totalMainAxis) {
    if (totalMainAxis <= 0) {
      return;
    }

    final deltaFraction = deltaPx / totalMainAxis;
    final minBefore = index < widget._minSizes.length
        ? widget._minSizes[index] / totalMainAxis
        : 0.0;
    final minAfter = index + 1 < widget._minSizes.length
        ? widget._minSizes[index + 1] / totalMainAxis
        : 0.0;
    final next = List<double>.from(_fractions);
    var before = next[index] + deltaFraction;
    var after = next[index + 1] - deltaFraction;

    if (before < minBefore) {
      after -= minBefore - before;
      before = minBefore;
    }
    if (after < minAfter) {
      before -= minAfter - after;
      after = minAfter;
    }
    if (before <= 0 || after <= 0) {
      return;
    }

    next[index] = before;
    next[index + 1] = after;
    setState(() => _fractions = next);
  }

  @override
  Widget build(BuildContext context) {
    if (widget._children.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final total = widget._axis == Axis.horizontal
            ? constraints.maxWidth -
                _dividerExtent * (widget._children.length - 1)
            : constraints.maxHeight -
                _dividerExtent * (widget._children.length - 1);
        final items = <Widget>[];
        for (var index = 0; index < widget._children.length; index++) {
          items.add(
            Expanded(
              flex: (_fractions[index] * 10000).round().clamp(1, 10000),
              child: widget._children[index],
            ),
          );
          if (index < widget._children.length - 1) {
            final isHorizontal = widget._axis == Axis.horizontal;
            items.add(
              MouseRegion(
                cursor: isHorizontal
                    ? SystemMouseCursors.resizeLeftRight
                    : SystemMouseCursors.resizeUpDown,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanUpdate: (details) => _dragDivider(
                    index,
                    isHorizontal ? details.delta.dx : details.delta.dy,
                    total,
                  ),
                  child: SizedBox(
                    width: isHorizontal ? _dividerExtent : null,
                    height: isHorizontal ? null : _dividerExtent,
                    child: Center(
                      child: Container(
                        width: isHorizontal ? 1 : 24,
                        height: isHorizontal ? 24 : 1,
                        color: Theme.of(context).dividerColor,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }
        }
        return Flex(direction: widget._axis, children: items);
      },
    );
  }
}
