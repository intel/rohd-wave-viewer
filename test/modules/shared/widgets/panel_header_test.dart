// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// panel_header_test.dart
// Tests for the panel header widget.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:devtools_app_shared/utils.dart';
import 'package:rohd_wave_viewer/src/modules/shared/widgets/panel_header.dart';

void main() {
  group('Panel Header', () {
    testWidgets('Panel Header text test.', (tester) async {
      setGlobal(IdeTheme, getIdeTheme());
      await tester.pumpWidget(
        const MaterialApp(
          home: PanelHeader(
            headerText: 'MyHeader',
          ),
        ),
      );

      expect(find.text('MyHeader'), findsAtLeastNWidgets(1));
    });
  });
}
