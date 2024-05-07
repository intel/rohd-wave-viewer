// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// timescale.dart
// The timescale widget for the waveform display.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter/material.dart';

class TimescaleWidget extends StatelessWidget {
  final int zoomLevel;
  final int finalTime;
  final Color lineColor;

  const TimescaleWidget({
    super.key,
    required this.zoomLevel,
    required this.finalTime,
    this.lineColor = Colors.blue,
  });

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.of(context).size.width;
    return CustomPaint(
      size: Size(width, 50), // this is the canvas to draw
      painter: TimescalePainter(
        timeScale: zoomLevel.toDouble(),
        finalTime: 20,
      ),
    );
  }
}

class TimescalePainter extends CustomPainter {
  /// The unit if the timescale, default to pico seconds
  final String timeUnit;

  /// The zoom level of the painter.
  final double timeScale;

  /// The final time of the simulation timescale. Interval of the time in
  /// between.
  final double finalTime;

  TimescalePainter({
    this.timeUnit = 'ps',
    required this.timeScale,
    required this.finalTime,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 1;

    // this one should be in the constant folder
    const double initPosY = 0;

    /// Draw the horizontal scale line
    canvas.drawLine(
      const Offset(0, initPosY),
      Offset(size.width, initPosY),
      paint,
    );

    /// Draw the scale ticks and labels (Major Ticks)
    /// This loop is used to draw the major ticks and labels on the timescale.
    /// The loop variable i represents the x-coordinate of each major tick and
    /// label. It starts at 0 and increments by size.width / [finalTime] on each
    /// iteration, which means there will be [finalTime] major ticks evenly
    /// spacedcacross the width of the widget.
    ///
    /// Basically, given a finalTime, calculate the interval in between the
    /// screen.
    for (double i = 0; i <= size.width; i += size.width / finalTime) {
      final textPainter = TextPainter(
        text: TextSpan(
          text:
              '${((i / (size.width / finalTime)) * timeScale).round()}$timeUnit',
          style: const TextStyle(
            color: Colors.blue,
            fontSize: 12,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      final offset = Offset(
        i - textPainter.width / 2,
        initPosY - 20,
      );
      // Paint the text on the canvas
      textPainter.paint(canvas, offset);

      // Draw the major line.
      canvas.drawLine(
        Offset(i, initPosY),
        Offset(i, size.height),
        paint,
      );

      /// Draw minor ticks
      /// This nested loop is used to draw the minor ticks between each pair of
      /// major ticks. The loop variable j represents the x-coordinate of each
      /// minor tick. It starts at i + size.width / 50 and
      /// increments by size.width / 50 on each iteration, which means
      /// there will be 50 minor ticks between each pair of major ticks.
      const totalMinorTicks = 10;
      if (i + size.width / finalTime <= size.width) {
        for (double j = i + size.width / (finalTime * totalMinorTicks);
            j < i + size.width / finalTime;
            j += size.width / (finalTime * totalMinorTicks)) {
          canvas.drawLine(
            Offset(j, initPosY),
            Offset(j, initPosY + 5),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant TimescalePainter oldDelegate) {
    // return oldDelegate.timeScale != timeScale;
    return false;
  }
}
