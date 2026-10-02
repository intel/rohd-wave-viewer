// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module_signal_card_test.dart
// Tests for the module signal card.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:devtools_app_shared/ui.dart' as devtools;
import 'package:devtools_app_shared/utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_wave_viewer/src/modules/shared/widgets/module_signal_card.dart';
import 'package:rohd_wave_viewer/src/platform/devtools_shared_ui.dart';

void main() {
  group('Module Signal Card', () {
    testWidgets('Title and Body test.', (tester) async {
      setGlobal(devtools.IdeTheme, devtools.getIdeTheme());
      await tester.pumpWidget(
        const MaterialApp(
          home: ModuleSignalCard(
            cardTitle: 'MyTitle',
            cardBody: Text('MyBody'),
          ),
        ),
      );

      expect(find.text('MyTitle'), findsAtLeastNWidgets(1));
      expect(find.text('MyBody'), findsAtLeastNWidgets(1));
      expect(find.byType(AreaPaneHeader), findsAny);
    });
  });
}
