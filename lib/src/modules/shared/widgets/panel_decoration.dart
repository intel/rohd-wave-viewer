// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// panel_decoration.dart
// Decoration for the panels.
//
// 2024 April
// Author(s): Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
//            Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:material_ui/material_ui.dart';
import 'package:rohd_wave_viewer/src/const/app_theme.dart';

/// Returns the standard panel decoration for the current theme.
BoxDecoration panelDecoration({bool isDark = true, Color? backgroundColor}) =>
    BoxDecoration(
      color: backgroundColor ??
          (isDark
              ? DarkThemeColors.panelBackground
              : LightThemeColors.panelBackground),
      border: Border.all(
        color: isDark ? DarkThemeColors.divider : LightThemeColors.divider,
      ),
    );
