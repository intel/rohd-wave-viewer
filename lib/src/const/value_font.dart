// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// value_font.dart
// Font choices for waveform and signal values.
//
// 2026 October
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:material_ui/material_ui.dart';

/// Font choices for values displayed by the wave viewer.
enum ValueFont {
  /// Roboto Mono bundled by `devtools_app_shared`.
  robotoMono(
    label: 'Roboto Mono',
    fontFamily: 'RobotoMono',
    fontPackage: 'devtools_app_shared',
    isMonospace: true,
  ),

  /// Adobe Source Code Pro bundled by the wave viewer.
  sourceCodePro(
    label: 'Source Code Pro',
    fontFamily: 'SourceCodePro',
    isMonospace: true,
  ),

  /// Canonical Ubuntu Mono bundled by the wave viewer.
  ubuntuMono(
    label: 'Ubuntu Mono',
    fontFamily: 'UbuntuMono',
    isMonospace: true,
  ),

  /// Proportional Roboto bundled by `devtools_app_shared`.
  roboto(
    label: 'Roboto',
    fontFamily: 'Roboto',
    fontPackage: 'devtools_app_shared',
    isMonospace: false,
  );

  /// Creates a font choice.
  const ValueFont({
    required this.label,
    required this.fontFamily,
    required this.isMonospace,
    this.fontPackage,
  });

  /// Human-readable menu label.
  final String label;

  /// Font family declared in the Flutter font manifest.
  final String fontFamily;

  /// Package that supplies the font, when it is not an application asset.
  final String? fontPackage;

  /// Whether every glyph uses the same advance width.
  final bool isMonospace;

  /// Fully resolved family name stored by [TextStyle].
  String get resolvedFontFamily =>
      fontPackage == null ? fontFamily : 'packages/$fontPackage/$fontFamily';

  /// Builds a value text style while preserving the caller's visual settings.
  TextStyle textStyle({
    required double fontSize,
    required Color color,
    FontWeight? fontWeight,
  }) =>
      TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontFamily: fontFamily,
        package: fontPackage,
      );
}
