// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_format_menu_test.dart
// Tests for the shared signal display-format menu.
//
// 2026 August
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart'
    show SignalValueFormatRegistry;
import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/signal/view/signal_format_menu.dart';
import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';

import '../../../helpers.dart';

void main() {
  tearDown(SignalValueFormatRegistry.clear);

  testWidgets('builds a singular or plural display-format command', (
    tester,
  ) async {
    final singular = buildSignalFormatMenuItem(count: 1);
    final plural = buildSignalFormatMenuItem(count: 3);

    expect(singular.value, signalFormatMenuValue);
    expect(plural.value, signalFormatMenuValue);

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Column(children: [singular.child!, plural.child!]),
        ),
      ),
    );

    expect(find.text('Format As'), findsOneWidget);
    expect(find.text('Format 3 Signals As'), findsOneWidget);
  });

  testWidgets('shows formats and returns the selected format to the callback', (
    tester,
  ) async {
    late BuildContext context;
    MonitorValueFormat? selectedFormat;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (buildContext) {
            context = buildContext;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final menu = showSignalFormatMenu(
      context,
      globalPosition: const Offset(20, 20),
      signalPaths: {'top.data'},
      onFormatSelected: (format) => selectedFormat = format,
    );
    await tester.pumpAndSettle();

    expect(find.text('Waveform Default'), findsOneWidget);
    expect(find.text('Hexadecimal'), findsOneWidget);
    expect(find.text('ASCII'), findsOneWidget);

    await tester.tap(find.text('Hexadecimal'));
    await tester.pumpAndSettle();
    await menu;

    expect(selectedFormat, MonitorValueFormat.hexadecimal);
  });

  testWidgets('does not open a menu without selected signal paths', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (buildContext) {
            context = buildContext;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    await showSignalFormatMenu(
      context,
      globalPosition: const Offset(20, 20),
      signalPaths: const {},
    );

    expect(find.byType(PopupMenuItem<MonitorValueFormat>), findsNothing);
  });

  testWidgets('dispatches the selected format to the signal bloc', (
    tester,
  ) async {
    final signalBloc = MockSignalBloc();
    late BuildContext context;
    when(() => signalBloc.state).thenReturn(SignalLoading());
    when(() => signalBloc.stream).thenAnswer((_) => const Stream.empty());
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<SignalBloc>.value(
          value: signalBloc,
          child: Builder(
            builder: (buildContext) {
              context = buildContext;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    final menu = showSignalFormatMenu(
      context,
      globalPosition: const Offset(20, 20),
      signalPaths: {'top.data'},
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Binary'));
    await tester.pumpAndSettle();
    await menu;

    verify(
      () => signalBloc.add(
        SignalSetOccurrenceValueFormatEvent(
          signalPaths: const {'top.data'},
          valueFormat: MonitorValueFormat.binary,
        ),
      ),
    ).called(1);
  });
}
