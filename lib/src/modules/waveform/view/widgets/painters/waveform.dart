// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// waveform.dart
// Abstract class for waveform painters.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter/material.dart';
import 'package:module_structure_api/module_structure_api.dart';

abstract class Waveform extends CustomPainter {
  final greenPaint = Paint()
    ..color = Colors.green
    ..strokeWidth = 1
    ..style = PaintingStyle.stroke;
  final redPaint = Paint()
    ..color = Colors.red
    ..strokeWidth = 1
    ..style = PaintingStyle.stroke;
  final orangePaint = Paint()
    ..color = Colors.orange
    ..strokeWidth = 1
    ..style = PaintingStyle.stroke;

  final List<Data> waveform;
  final int timescale;

  Waveform(this.waveform, this.timescale);

  String? getValueAtTime(List<Data> data, int time) {
    for (var dataItem in data) {
      if (dataItem.time == time) {
        return dataItem.value;
      }
    }
    return null;
  }

  void writeText(Canvas canvas, Offset offset,
      {required String text, TextStyle? customTextStyle}) {
    final textStyle = customTextStyle ??
        const TextStyle(
          color: Colors.green,
          fontSize: 12,
        );

    final textSpan = TextSpan(
      text: '0x$text',
      style: textStyle,
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();

    textPainter.paint(canvas, offset);
  }
}
