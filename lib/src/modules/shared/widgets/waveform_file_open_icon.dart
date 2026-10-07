// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// waveform_file_open_icon.dart
// Renders the composite icon for opening a waveform file.
//
// 2026 October
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// An open-file icon badged with a signal waveform.
class WaveformFileOpenIcon extends StatelessWidget {
  /// Creates an icon for opening a waveform file.
  const WaveformFileOpenIcon({
    this.size,
    this.color,
    super.key,
  });

  /// The square icon size.
  ///
  /// Defaults to the ambient [IconTheme] size.
  final double? size;

  /// The color of both icon layers.
  ///
  /// Defaults to the ambient [IconTheme] color so disabled [IconButton] states
  /// remain visible.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final resolvedSize = size ?? iconTheme.size ?? 24;
    final resolvedColor = color ?? iconTheme.color;

    return SizedBox.square(
      dimension: resolvedSize,
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: Icon(
              Icons.file_open,
              size: resolvedSize * 0.88,
              color: resolvedColor,
            ),
          ),
          Align(
            alignment: Alignment.bottomRight,
            child: Icon(
              Icons.ssid_chart,
              size: resolvedSize * 0.5,
              color: resolvedColor,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DoubleProperty('size', size))
      ..add(ColorProperty('color', color));
  }
}
