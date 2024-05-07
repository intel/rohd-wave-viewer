// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// waveform_binary.dart
// Paints the binary waveform.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter/material.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/view/widgets/painters/waveform.dart';

class WaveformBinary extends Waveform {
  WaveformBinary(super.waveform, super.timescale);

  @override
  void paint(Canvas canvas, Size size) {
    final binValPath = Path();
    final xValPath = Path();
    final zValPath = Path();

    String currentVal = waveform.first.value;
    final containerWidth = size.width;

    for (int i = 0; i < timescale; i++) {
      String? value = getValueAtTime(waveform, i);

      final startX = containerWidth / timescale * i;
      final endX = containerWidth / timescale * (i + 1);
      double posY;

      if (currentVal.toLowerCase().contains('x') ||
          currentVal.toLowerCase().contains('z')) {
        posY = size.height;
      } else {
        posY = size.height * (1 - int.parse(currentVal));
      }

      double newPosY = posY;

      binValPath.moveTo(startX, posY);
      xValPath.moveTo(startX, posY);
      zValPath.moveTo(startX, posY);
      if (value != null) {
        if (value.toLowerCase().contains('x')) {
          currentVal = value;
          newPosY = size.height;
          xValPath.lineTo(startX, newPosY);
        } else if (value.toLowerCase().contains('z')) {
          currentVal = value;
          newPosY = size.height;
          zValPath.lineTo(startX, newPosY);
        } else {
          currentVal = value;
          newPosY = size.height * (1 - int.parse(currentVal));
          binValPath.lineTo(startX, newPosY);
        }
      }

      if (currentVal.toLowerCase().contains('x')) {
        xValPath.lineTo(endX, newPosY);
      } else if (currentVal.toLowerCase().contains('z')) {
        zValPath.lineTo(endX, newPosY);
      } else {
        binValPath.lineTo(endX, newPosY);
      }
    }

    canvas.drawPath(binValPath, greenPaint);
    canvas.drawPath(xValPath, redPaint);
    canvas.drawPath(zValPath, orangePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
