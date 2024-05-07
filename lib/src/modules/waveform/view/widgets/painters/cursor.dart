// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// cursor.dart
// The cursor painter for the waveform display.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter/material.dart';

class Cursor extends CustomPainter {
  final redPaint = Paint()
    ..color = Colors.red
    ..strokeWidth = 1
    ..style = PaintingStyle.stroke;

  final Offset clickedOffset;

  Cursor(this.clickedOffset);

  @override
  void paint(Canvas canvas, Size size) {
    var p1 = Offset(clickedOffset.dx, 0);
    var p2 = Offset(clickedOffset.dx, size.height);

    canvas.drawLine(p1, p2, redPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
