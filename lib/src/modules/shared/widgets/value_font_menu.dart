// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// value_font_menu.dart
// Wave viewer settings menu for selecting the displayed value font.
//
// 2026 October
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_wave_viewer/src/const/value_font.dart';

/// Settings menu containing the value-font selection submenu.
class ValueFontMenu extends StatelessWidget {
  static const _fontItemStyle = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size(0, 28)),
    padding: WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 12),
    ),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity(vertical: -4),
  );

  static const _sectionLabelStyle = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size(0, 22)),
    padding: WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 12),
    ),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity(vertical: -4),
  );

  /// Currently selected value font.
  final ValueFont selectedFont;

  /// Called when the user selects a different value font.
  final ValueChanged<ValueFont> onSelected;

  /// Creates the wave viewer settings menu.
  const ValueFontMenu({
    required this.selectedFont,
    required this.onSelected,
    super.key,
  });

  @override
  Widget build(BuildContext context) => MenuAnchor(
        menuChildren: [
          SubmenuButton(
            menuChildren: [
              _sectionLabel(context, 'Monospace'),
              for (final font in ValueFont.values.where(
                (font) => font.isMonospace,
              ))
                _fontItem(context, font),
              const Divider(height: 1),
              _sectionLabel(context, 'Proportional'),
              for (final font in ValueFont.values.where(
                (font) => !font.isMonospace,
              ))
                _fontItem(context, font),
            ],
            child: const Text('Value Font'),
          ),
        ],
        builder: (context, controller, child) => IconButton(
          tooltip: 'Wave viewer settings',
          icon: const Icon(Icons.settings, size: 18),
          onPressed: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
        ),
      );

  Widget _fontItem(BuildContext context, ValueFont font) => MenuItemButton(
        key: ValueKey('value-font-${font.name}'),
        style: _fontItemStyle,
        leadingIcon: selectedFont == font
            ? const Icon(Icons.check, size: 16)
            : const SizedBox(width: 16),
        onPressed: () => onSelected(font),
        child: Text(
          font.label,
          style: font.textStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      );

  Widget _sectionLabel(BuildContext context, String label) => MenuItemButton(
        style: _sectionLabelStyle,
        child: Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(EnumProperty<ValueFont>('selectedFont', selectedFont))
      ..add(
        ObjectFlagProperty<ValueChanged<ValueFont>>.has(
          'onSelected',
          onSelected,
        ),
      );
  }
}
