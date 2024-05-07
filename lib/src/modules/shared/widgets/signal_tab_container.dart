// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_tab_container.dart
// The container for the signal tab.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter/material.dart';

class SignalTabContainer extends StatelessWidget {
  final Widget containerBody;
  final bool showBorder;
  final Color borderColor;

  const SignalTabContainer({
    super.key,
    required this.containerBody,
    this.showBorder = false,
    this.borderColor = Colors.transparent,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: showBorder
            ? BoxDecoration(border: Border.all(color: borderColor))
            : null,
        width: double.infinity,
        child: containerBody,
      ),
    );
  }
}
