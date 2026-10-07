// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// cursor.dart
// The cursor painter for the waveform display.
//
// 2024 April
// Author(s): Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
//            Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:material_ui/material_ui.dart';

/// Painter that draws the active vertical waveform cursor.
class Cursor extends CustomPainter {
  /// Cursor position in the paint area.
  final Offset clickedOffset;

  /// Color used to draw the cursor line.
  final Color cursorColor;

  late final Paint _cursorPaint;

  /// Creates a cursor painter.
  Cursor(this.clickedOffset, {this.cursorColor = Colors.red}) {
    _cursorPaint = Paint()
      ..color = cursorColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final p1 = Offset(clickedOffset.dx, 0);
    final p2 = Offset(clickedOffset.dx, size.height);

    canvas.drawLine(p1, p2, _cursorPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
