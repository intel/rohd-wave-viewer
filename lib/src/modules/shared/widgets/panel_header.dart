// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// panel_header.dart
// The header for the panels.
//
// 2024 April
// Author(s): Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
//            Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:material_ui/material_ui.dart';
import 'package:rohd_wave_viewer/src/const/app_theme.dart';

/// Standard header widget used across viewer panels.
class PanelHeader extends StatelessWidget {
  final String _headerText;

  /// Creates a panel header.
  const PanelHeader({required String headerText, super.key})
      : _headerText = headerText;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 38),
      decoration: BoxDecoration(
        color:
            isDark ? DarkThemeColors.panelHeader : LightThemeColors.panelHeader,
        border: Border(
          bottom: BorderSide(
            color: isDark ? DarkThemeColors.divider : LightThemeColors.divider,
          ),
        ),
      ),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Text(
        _headerText,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isDark ? DarkThemeColors.text : LightThemeColors.text,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }
}
