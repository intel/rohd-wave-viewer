// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// waveform_hexavalue.dart
// Paints the waveform with hexadecimal values.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter/material.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/view/widgets/painters/waveform.dart';

class WaveformHexaValue extends Waveform {
  WaveformHexaValue(super.waveform, super.timescale);

  @override
  void paint(Canvas canvas, Size size) {
    const space = 3;

    final topPath = Path();
    final bottomPath = Path();

    final xPathTop = Path();
    final xPathBottom = Path();

    final zPathTop = Path();
    final zPathBottom = Path();

    final timeScaleLength = timescale;

    String currSignal = waveform.first.value;

    for (int i = 0; i < timeScaleLength; i++) {
      final startX = size.width / timeScaleLength * i;
      final endX = size.width / timeScaleLength * (i + 1);

      const double posYTop = 0;
      final double posYBottom = size.height;

      String? value = getValueAtTime(waveform, i);

      topPath.moveTo(startX, posYTop);
      bottomPath.moveTo(startX, posYBottom);
      bool prevValChanged = false;

      if (value != null && i != waveform[0].time) {
        currSignal = value;
        prevValChanged = true;

        if (value.toLowerCase().contains('x')) {
          xPathTop.moveTo(startX - space, posYTop);
          xPathTop.lineTo(startX + space, posYBottom);
          xPathTop.moveTo(startX + space, posYTop);
          xPathTop.lineTo(endX - space, posYTop);
          xPathTop.moveTo(startX, posYTop);

          xPathBottom.moveTo(startX - space, posYBottom);
          xPathBottom.lineTo(startX + space, posYTop);
          xPathBottom.moveTo(startX + space, posYBottom);
          xPathBottom.lineTo(endX - space, posYBottom);

          const txtPaddingLeft = 5;
          final offset = Offset(startX + txtPaddingLeft, size.height / 6);
          writeText(
            canvas,
            offset,
            text: currSignal,
            customTextStyle: const TextStyle(
              color: Colors.red,
              fontSize: 10,
            ),
          );
        } else if (value.toLowerCase().contains('z')) {
          zPathTop.moveTo(startX - space, posYTop);
          zPathTop.lineTo(startX + space, posYBottom);
          zPathTop.moveTo(startX + space, posYTop);
          zPathTop.lineTo(endX - space, posYTop);
          zPathTop.moveTo(startX, posYTop);

          zPathBottom.moveTo(startX - space, posYBottom);
          zPathBottom.lineTo(startX + space, posYTop);
          zPathBottom.moveTo(startX + space, posYBottom);
          zPathBottom.lineTo(endX - space, posYBottom);

          const txtPaddingLeft = 5;
          final offset = Offset(startX + txtPaddingLeft, size.height / 6);
          writeText(
            canvas,
            offset,
            text: currSignal,
            customTextStyle: const TextStyle(
              color: Colors.orange,
              fontSize: 10,
            ),
          );
        } else {
          topPath.moveTo(startX - space, posYTop);
          topPath.lineTo(startX + space, posYBottom);
          topPath.moveTo(startX + space, posYTop);
          topPath.lineTo(endX - space, posYTop);
          topPath.moveTo(startX, posYTop);

          bottomPath.moveTo(startX - space, posYBottom);
          bottomPath.lineTo(startX + space, posYTop);
          bottomPath.moveTo(startX + space, posYBottom);
          bottomPath.lineTo(endX - space, posYBottom);

          const txtPaddingLeft = 5;
          final offset = Offset(startX + txtPaddingLeft, size.height / 6);
          writeText(
            canvas,
            offset,
            text: currSignal,
            customTextStyle: const TextStyle(
              color: Colors.green,
              fontSize: 10,
            ),
          );
        }
      } else {
        if (currSignal.toLowerCase().contains('x')) {
          if (prevValChanged == false || i == 0) {
            xPathTop.moveTo(startX - space, posYTop);
            xPathBottom.moveTo(startX - space, posYBottom);
          }
          xPathTop.lineTo(endX - space, posYTop);
          xPathBottom.lineTo(endX - space, posYBottom);
        } else if (currSignal.toLowerCase().contains('z')) {
          if (prevValChanged == false || i == 0) {
            zPathTop.moveTo(startX - space, posYTop);
            zPathBottom.moveTo(startX - space, posYBottom);
          }
          zPathTop.lineTo(endX - space, posYTop);
          zPathBottom.lineTo(endX - space, posYBottom);
        } else {
          if (prevValChanged == false || i == 0) {
            topPath.moveTo(startX - space, posYTop);
            bottomPath.moveTo(startX - space, posYBottom);
          }

          topPath.lineTo(endX - space, posYTop);
          bottomPath.lineTo(endX - space, posYBottom);
        }

        prevValChanged = false;
      }

      if (i == 0) {
        const txtPaddingLeft = 5;
        final offset = Offset(startX + txtPaddingLeft, size.height / 6);
        Color txtColor = Colors.green;
        if (currSignal.toLowerCase().contains('x')) {
          txtColor = Colors.red;
        } else if (currSignal.toLowerCase().contains('z')) {
          txtColor = Colors.orange;
        } else {
          txtColor = Colors.green;
        }

        writeText(
          canvas,
          offset,
          text: currSignal,
          customTextStyle: TextStyle(
            color: txtColor,
            fontSize: 10,
          ),
        );
      }
    }

    topPath.addPath(bottomPath, const Offset(0, 0));
    canvas.drawPath(topPath, greenPaint);

    canvas.drawPath(xPathTop, redPaint);
    canvas.drawPath(xPathBottom, redPaint);

    canvas.drawPath(zPathTop, orangePaint);
    canvas.drawPath(zPathBottom, orangePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
