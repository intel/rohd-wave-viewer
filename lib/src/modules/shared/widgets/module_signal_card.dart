// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module_signal_card.dart
// The module signal card widget.
//
// 2024 April
// Author(s): Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
//            Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:material_ui/material_ui.dart';
import 'package:rohd_wave_viewer/src/const/colors.dart';
import 'package:rohd_wave_viewer/src/platform/devtools_shared_ui.dart';

/// Card container used for module-related signal panels.
class ModuleSignalCard extends StatelessWidget {
  final Widget _cardBody;
  final String _cardTitle;
  final List<Widget>? _headerAction;

  /// Creates a module signal card.
  const ModuleSignalCard({
    required String cardTitle,
    required Widget cardBody,
    super.key,
    List<Widget>? headerAction,
  })  : _cardTitle = cardTitle,
        _cardBody = cardBody,
        _headerAction = headerAction;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      elevation: 0, // Remove shadow
      color: isDark ? const Color(0xFF252526) : tertiaryColor,
      child: Column(
        children: <Widget>[
          AreaPaneHeader(title: Text(_cardTitle), actions: _headerAction ?? []),
          _cardBody,
        ],
      ),
    );
  }
}
