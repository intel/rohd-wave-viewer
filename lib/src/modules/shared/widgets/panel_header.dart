// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// panel_header.dart
// The header for the panels.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter/material.dart';

class PanelHeader extends StatelessWidget {
  final String headerText;
  const PanelHeader({
    super.key,
    required this.headerText,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Text(
          headerText,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    );
  }
}
