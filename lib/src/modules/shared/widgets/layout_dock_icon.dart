// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// layout_dock_icon.dart
// A small VS Code-style "layout" icon: a rounded window rectangle with a
// strip along one edge representing a dockable panel.  When the strip is
// shaded (locked) the panel is pinned open and will not slide closed.
//
// 2026 June
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// Which edge of the layout the dockable panel occupies.
///
/// [left] draws a vertical divider (for a left-hand side panel such as the
/// signal-selection pane); [top] draws a horizontal divider (for a top bar
/// such as the app menubar).
enum LayoutDockEdge {
  /// Docked panel is along the top edge.
  top,

  /// Docked panel is along the left edge.
  left,
}

/// A VS Code-style layout icon: a rounded "window" rectangle with a strip
/// along one [edge] representing a dockable panel.
///
/// When [locked] the strip is shaded (filled), indicating the panel is pinned
/// open and will not slide closed.  When unlocked only the outline and divider
/// are drawn, so the panel is free to auto-hide.
class LayoutDockIcon extends StatelessWidget {
  /// Creates a layout dock icon.
  const LayoutDockIcon({
    required this.edge,
    required this.locked,
    required this.color,
    this.size = 16,
    super.key,
  });

  /// The edge the dockable panel occupies.
  final LayoutDockEdge edge;

  /// Whether the panel is locked (pinned) open — shades the strip.
  final bool locked;

  /// Icon color (used for the outline, divider and — when [locked] — the
  /// shaded strip).
  final Color color;

  /// Square icon side length in logical pixels.
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _LayoutDockPainter(edge: edge, locked: locked, color: color),
      );

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(EnumProperty<LayoutDockEdge>('edge', edge))
      ..add(FlagProperty('locked', value: locked, ifTrue: 'locked'))
      ..add(ColorProperty('color', color))
      ..add(DoubleProperty('size', size));
  }
}

class _LayoutDockPainter extends CustomPainter {
  _LayoutDockPainter({
    required this.edge,
    required this.locked,
    required this.color,
  });

  final LayoutDockEdge edge;
  final bool locked;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = (size.width / 16 * 1.4).clamp(1.0, 2.0);
    final inset = stroke;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - inset * 2,
      size.height - inset * 2,
    );
    final rrect =
        RRect.fromRectAndRadius(rect, Radius.circular(size.width * 0.14));

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = color
      ..isAntiAlias = true;

    // Strip geometry along the docked edge (~38% of the cross dimension).
    late final Rect strip;
    late final Offset dividerStart;
    late final Offset dividerEnd;
    if (edge == LayoutDockEdge.left) {
      final w = rect.width * 0.38;
      strip = Rect.fromLTWH(rect.left, rect.top, w, rect.height);
      dividerStart = Offset(rect.left + w, rect.top);
      dividerEnd = Offset(rect.left + w, rect.bottom);
    } else {
      final h = rect.height * 0.38;
      strip = Rect.fromLTWH(rect.left, rect.top, rect.width, h);
      dividerStart = Offset(rect.left, rect.top + h);
      dividerEnd = Offset(rect.right, rect.top + h);
    }

    // Shade the strip when the panel is locked (pinned open).
    if (locked) {
      canvas
        ..save()
        ..clipRRect(rrect)
        ..drawRect(
          strip,
          Paint()
            ..style = PaintingStyle.fill
            ..color = color.withValues(alpha: 0.9)
            ..isAntiAlias = true,
        )
        ..restore();
    }

    // Outer window border and the divider between the strip and main area.
    canvas
      ..drawRRect(rrect, line)
      ..drawLine(dividerStart, dividerEnd, line);
  }

  @override
  bool shouldRepaint(_LayoutDockPainter oldDelegate) =>
      oldDelegate.locked != locked ||
      oldDelegate.color != color ||
      oldDelegate.edge != edge;
}
