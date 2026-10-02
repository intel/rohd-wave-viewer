// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// platform_icon.dart
// Provides platform-aware icon rendering with emoji fallback.
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:material_ui/material_ui.dart';

/// A widget that renders either a Material Icon or emoji text based on
/// platform emoji font availability.
///
/// On platforms with color emoji support, uses the provided emoji string.
/// On platforms without (or with `hasColorEmoji: false`), falls back to
/// the Material IconData.
class PlatformIcon extends StatelessWidget {
  final IconData _nativeIcon;
  final String _emoji;
  final double? _size;
  final Color? _color;
  final double? _opacity;
  final bool _grayscale;
  final bool _brighten;
  final bool _hasColorEmoji;

  /// Creates a platform-aware icon widget.
  const PlatformIcon(
    IconData nativeIcon,
    String emoji, {
    double? size,
    Color? color,
    double? opacity,
    bool grayscale = false,
    bool brighten = false,
    bool hasColorEmoji = true,
    super.key,
  })  : _nativeIcon = nativeIcon,
        _emoji = emoji,
        _size = size,
        _color = color,
        _opacity = opacity,
        _grayscale = grayscale,
        _brighten = brighten,
        _hasColorEmoji = hasColorEmoji;

  // Luminance-preserving grayscale color matrix.
  static const _grayscaleMatrix = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  // Brightness boost: scale RGB by 1.8x and add 40 to each channel.
  static const _brightenMatrix = ColorFilter.matrix(<double>[
    1.8, 0, 0, 0, 40, //
    0, 1.8, 0, 0, 40,
    0, 0, 1.8, 0, 40,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    if (_hasColorEmoji) {
      Widget child = Text(
        _emoji,
        style: TextStyle(fontSize: _size ?? 16, color: _color),
      );
      if (_grayscale) {
        child = ColorFiltered(colorFilter: _grayscaleMatrix, child: child);
      }
      if (_brighten) {
        child = ColorFiltered(colorFilter: _brightenMatrix, child: child);
      }
      if (_opacity != null && _opacity < 1.0) {
        child = Opacity(opacity: _opacity, child: child);
      }
      return child;
    }
    return Icon(_nativeIcon, size: _size, color: _color);
  }
}

/// Helper function for quick construction of PlatformIcon widgets.
///
/// Returns a PlatformIcon widget that renders either emoji or Material icon
/// based on platform capabilities.
///
/// Example:
/// ```dart
/// platformIcon(Icons.waves, '🌊', size: 24)
/// ```
///
/// Returns a [PlatformIcon] configured with the provided rendering options.
Widget platformIcon(
  IconData nativeIcon,
  String emoji, {
  double? size,
  Color? color,
  double? opacity,
  bool grayscale = false,
  bool brighten = false,
  bool hasColorEmoji = true,
}) =>
    PlatformIcon(
      nativeIcon,
      emoji,
      size: size,
      color: color,
      opacity: opacity,
      grayscale: grayscale,
      brighten: brighten,
      hasColorEmoji: hasColorEmoji,
    );
