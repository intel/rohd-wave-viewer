// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module_signal_card.dart
// The module signal card widget.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';

import '../../../const/colors.dart';

class ModuleSignalCard extends StatelessWidget {
  final Widget cardBody;
  final String cardTitle;
  final List<Widget>? headerAction;

  const ModuleSignalCard({
    super.key,
    required this.cardTitle,
    required this.cardBody,
    this.headerAction,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: tertiaryColor,
      child: Column(
        children: <Widget>[
          AreaPaneHeader(
            title: Text(cardTitle),
            actions: headerAction ?? [],
          ),
          cardBody,
        ],
      ),
    );
  }
}
