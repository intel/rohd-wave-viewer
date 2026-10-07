// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_tab_container_test.dart
// Tests for the signal tab container widget.
//
// 2024 April
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:devtools_app_shared/ui.dart';
import 'package:devtools_app_shared/utils.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_wave_viewer/src/cubit/waveform_scale_cubit.dart';
import 'package:rohd_wave_viewer/src/modules/shared/widgets/signal_tab_container.dart';

void main() {
  group('Signal Tab Container', () {
    testWidgets('Should be a container that have a widget inside..', (
      tester,
    ) async {
      setGlobal(IdeTheme, getIdeTheme());
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider(
            create: (_) => WaveformScaleCubit(),
            child: const SignalTabContainer(
              containerBody: Text('MySignaltabContainer'),
            ),
          ),
        ),
      );

      expect(find.text('MySignaltabContainer'), findsAtLeastNWidgets(1));
    });
  });
}
