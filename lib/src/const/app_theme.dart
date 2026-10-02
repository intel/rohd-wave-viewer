// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// app_theme.dart
// Centralized theme definitions for the ROHD Wave Viewer. This file contains
// theme-related constants to avoid duplication across the app.
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:material_ui/material_ui.dart';

/// Dark theme color constants used throughout the wave viewer.
class DarkThemeColors {
  /// Background color for app scaffolds.
  static const scaffoldBackground = Color(0xFF1E1E1E);

  /// Background color for cards.
  static const cardBackground = Color(0xFF252526);

  /// Background color for secondary panels.
  static const panelBackground = Color(0xFF252526);

  /// Background color for panel headers.
  static const panelHeader = Color(0xFF333333);

  /// Divider color between panels and sections.
  static const divider = Color(0xFF3C3C3C);

  /// Primary text color.
  static const text = Colors.white;

  /// Secondary text color.
  static const textSecondary = Colors.white70;

  // Waveform-specific colors
  /// Color for a high logic value.
  static const waveformSignalHigh = Colors.green;

  /// Color for a low logic value.
  static const waveformSignalLow = Colors.green;

  /// Color for an unknown logic value.
  static const waveformSignalX = Colors.red;

  /// Color for a high-impedance logic value.
  static const waveformSignalZ = Colors.yellow;

  /// Color for hexadecimal bus traces.
  static const waveformHexBus = Colors.green;

  /// Value label text: high-contrast neutral (matches Surfer's foreground).
  /// Separate from signal color for readability at small sizes.
  static const waveformText = Color(0xFFD4D4D4);

  /// Color for the waveform cursor.
  static const waveformCursor = Colors.red;

  /// Color for timescale tick labels and markers.
  static const waveformTimescale = Colors.blue;

  /// Background color for the waveform area.
  static const waveformBackground = Color(0xFF1E1E1E);

  /// Alternate row background color for waveform rows.
  static const waveformRowAlternate = Color(0xFF252526);
}

/// Light theme color constants used throughout the wave viewer.
class LightThemeColors {
  /// Background color for app scaffolds.
  static const scaffoldBackground = Colors.white;

  /// Background color for cards.
  static const cardBackground = Colors.white;

  /// Background color for secondary panels.
  static const panelBackground = Colors.white;

  /// Background color for panel headers.
  static const panelHeader = Color(0xFFF5F5F5);

  /// Divider color between panels and sections.
  static const divider = Colors.black26;

  /// Primary text color.
  static const text = Colors.black87;

  /// Secondary text color.
  static const textSecondary = Colors.black54;

  // Waveform-specific colors
  /// Color for a high logic value.
  static const waveformSignalHigh = Color(0xFF1B5E20); // Dark green

  /// Color for a low logic value.
  static const waveformSignalLow = Color(0xFF1B5E20);

  /// Color for an unknown logic value.
  static const waveformSignalX = Color(0xFFC62828); // Dark red

  /// Color for a high-impedance logic value.
  static const waveformSignalZ = Color(0xFFF57F17); // Dark amber/yellow

  /// Color for hexadecimal bus traces.
  static const waveformHexBus = Color(0xFF1B5E20);

  /// Value label text: near-black for high contrast on white background.
  static const waveformText = Color(0xFF333333);

  /// Color for the waveform cursor.
  static const waveformCursor = Color(0xFFC62828);

  /// Color for timescale tick labels and markers.
  static const waveformTimescale = Color(0xFF0D47A1); // Dark blue

  /// Background color for the waveform area.
  static const waveformBackground = Colors.white;

  /// Alternate row background color for waveform rows.
  static const waveformRowAlternate = Color(0xFFF5F5F5);
}

/// Waveform colors resolved from the active theme context.
class WaveformColors {
  /// Color for a high logic value.
  final Color signalHigh;

  /// Color for a low logic value.
  final Color signalLow;

  /// Color for an unknown logic value.
  final Color signalX;

  /// Color for a high-impedance logic value.
  final Color signalZ;

  /// Color for hexadecimal bus traces.
  final Color hexBus;

  /// Color for waveform text labels.
  final Color text;

  /// Color for the waveform cursor.
  final Color cursor;

  /// Color for timescale text and markers.
  final Color timescale;

  /// Background color behind the timescale area.
  final Color timescaleBackground;

  /// Background color for the waveform viewport.
  final Color background;

  /// Alternate row background color for waveform rows.
  final Color rowAlternate;

  /// Creates a set of waveform colors.
  const WaveformColors({
    required this.signalHigh,
    required this.signalLow,
    required this.signalX,
    required this.signalZ,
    required this.hexBus,
    required this.text,
    required this.cursor,
    required this.timescale,
    required this.timescaleBackground,
    required this.background,
    required this.rowAlternate,
  });

  /// Waveform colors for dark theme rendering.
  static const dark = WaveformColors(
    signalHigh: DarkThemeColors.waveformSignalHigh,
    signalLow: DarkThemeColors.waveformSignalLow,
    signalX: DarkThemeColors.waveformSignalX,
    signalZ: DarkThemeColors.waveformSignalZ,
    hexBus: DarkThemeColors.waveformHexBus,
    text: DarkThemeColors.waveformText,
    cursor: DarkThemeColors.waveformCursor,
    timescale: DarkThemeColors.waveformTimescale,
    timescaleBackground: DarkThemeColors.panelHeader,
    background: DarkThemeColors.waveformBackground,
    rowAlternate: DarkThemeColors.waveformRowAlternate,
  );

  /// Waveform colors for light theme rendering.
  static const light = WaveformColors(
    signalHigh: LightThemeColors.waveformSignalHigh,
    signalLow: LightThemeColors.waveformSignalLow,
    signalX: LightThemeColors.waveformSignalX,
    signalZ: LightThemeColors.waveformSignalZ,
    hexBus: LightThemeColors.waveformHexBus,
    text: LightThemeColors.waveformText,
    cursor: LightThemeColors.waveformCursor,
    timescale: LightThemeColors.waveformTimescale,
    timescaleBackground: LightThemeColors.panelHeader,
    background: LightThemeColors.waveformBackground,
    rowAlternate: LightThemeColors.waveformRowAlternate,
  );

  /// Returns waveform colors for the given [brightness].
  static WaveformColors fromBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// Returns waveform colors from the ambient theme in [context].
  static WaveformColors of(BuildContext context) =>
      fromBrightness(Theme.of(context).brightness);
}

/// App bar theme presets used by the wave viewer.
class AppBarThemes {
  /// Dark theme AppBar - matches VS Code dark theme
  static const dark = AppBarTheme(
    backgroundColor: DarkThemeColors.cardBackground,
    elevation: 0,
    scrolledUnderElevation: 0,
    shadowColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
  );

  /// Light theme AppBar.
  static const light = AppBarTheme(
    backgroundColor: LightThemeColors.scaffoldBackground,
    elevation: 0,
    scrolledUnderElevation: 0,
    surfaceTintColor: Colors.transparent,
  );
}
