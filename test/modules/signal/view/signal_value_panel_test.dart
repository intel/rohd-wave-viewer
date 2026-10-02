// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_value_panel_test.dart
// Tests for the signal value panel.
//
// 2026 August
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:dart_wellen/dart_wellen.dart' hide SignalWaveform;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide MetaData;
import 'package:mocktail/mocktail.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart';
import 'package:rohd_wave_viewer/src/const/const.dart';
import 'package:rohd_wave_viewer/src/modules/rohd_module/bloc/rohd_module_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/shared/widgets/widgets.dart';
import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/signal/view/signal_value_panel.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/bloc/waveform_module_bloc.dart';
import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';

import '../../../helpers.dart';

/// Builds a monitor row whose decimal display value is [decimalValue].
SignalWaveform buildRow(String signalId, int decimalValue, {int? atTime}) =>
    SignalWaveform(
      signalId: signalId,
      data: [
        Data(time: 0, value: '0'),
        Data(time: atTime ?? 0, value: decimalValue.toRadixString(2)),
      ],
      valueFormat: MonitorValueFormat.unsignedDecimal,
    )..overrideWidth = 32;

/// A stubbed cursor BLoC pinned to [state].
MockWaveformModuleBloc buildCursorBloc(WaveformModuleState state) {
  final bloc = MockWaveformModuleBloc();
  when(() => bloc.state).thenReturn(state);
  when(() => bloc.stream).thenAnswer((_) => const Stream.empty());
  return bloc;
}

void main() {
  tearDown(SignalValueFormatRegistry.clear);

  testWidgets('renders fixture X/Z and binary bus values at the cursor', (
    tester,
  ) async {
    await WellenSignalWaveformApi.init();
    final api = WellenSignalWaveformApi();
    await api.loadFile('test/fixtures/xz_transitions.vcd');
    final structure = await api.getModuleStructureOnly();
    final waveformData = await api.getWaveformData(
      signalIds: structure.allSignalIds,
    );
    final scalarData = waveformData.firstWhere(
      (waveform) =>
          waveform.data.any((datum) => datum.value.toLowerCase() == 'x') &&
          waveform.data.any((datum) => datum.value.toLowerCase() == 'z'),
    );
    final busData = waveformData.firstWhere(
      (waveform) =>
          waveform.data.any(
            (datum) => datum.value.toLowerCase().contains('x'),
          ) &&
          waveform.data.any(
            (datum) => datum.value.toLowerCase().contains('z'),
          ) &&
          waveform.data.any((datum) => datum.value.length > 1),
    );
    final numericBusDatum = busData.data.firstWhere(
      (datum) =>
          datum.value.length > 1 &&
          datum.value.codeUnits.every(
            (codeUnit) => codeUnit == 0x30 || codeUnit == 0x31,
          ),
    );
    final scalar = SignalWaveform.fromWaveformData(scalarData)
      ..overrideWidth = 1;
    final bus = SignalWaveform.fromWaveformData(busData)
      ..overrideWidth = numericBusDatum.value.length;
    final repository = SignalWaveformRepository(signalWaveformApi: api);
    final cursorBloc = WaveformModuleBloc(signalWaveformRepository: repository);
    final signalBloc = MockSignalBloc();
    addTearDown(cursorBloc.close);

    when(() => signalBloc.state)
        .thenReturn(SignalLoaded(const [], [scalar, bus]));

    cursorBloc.add(const WaveformModuleOnTap(90));
    await cursorBloc.stream.firstWhere((state) => state.timePs == 90);
    await tester.pumpApp(
      signalBloc: signalBloc,
      waveformModuleBloc: cursorBloc,
      child: const SignalValuePanel(),
    );

    expect(find.text(scalar.getValueByTime(90)), findsOneWidget);
    expect(find.text(bus.getValueByTime(90)), findsOneWidget);

    final binaryValue = bus.getValueByTime(numericBusDatum.time);
    final expectedBusValue = LogicValue.ofBigInt(
      BigInt.parse(binaryValue, radix: 2),
      bus.width,
    ).toString();
    cursorBloc.add(WaveformModuleOnTap(numericBusDatum.time));
    await cursorBloc.stream.firstWhere(
      (state) => state.timePs == numericBusDatum.time,
    );
    await tester.pump();

    expect(find.text(expectedBusValue), findsOneWidget);

    bus.valueFormat = MonitorValueFormat.unsignedDecimal;
    await tester.pumpApp(
      signalBloc: signalBloc,
      waveformModuleBloc: cursorBloc,
      child: const SignalValuePanel(),
    );

    expect(
      find.text(BigInt.parse(binaryValue, radix: 2).toString()),
      findsOneWidget,
    );
  });

  testWidgets('renders a placeholder row initially and bug report on error', (
    tester,
  ) async {
    final signalBloc = MockSignalBloc();
    when(() => signalBloc.state).thenReturn(
      SignalLoaded(const [], [buildRow('top.a', 5)]),
    );

    await tester.pumpApp(
      signalBloc: signalBloc,
      waveformModuleBloc: buildCursorBloc(const InitialCursor()),
      child: const SignalValuePanel(),
    );

    expect(find.text(signalsValuePanelTitle), findsOneWidget);
    expect(find.byType(SignalTabContainer), findsOneWidget);
    expect(find.text('5'), findsNothing);

    await tester.pumpApp(
      signalBloc: signalBloc,
      waveformModuleBloc: buildCursorBloc(const UpdatedCursor(10)),
      child: const SignalValuePanel(),
    );

    expect(find.text('5'), findsOneWidget);

    await tester.pumpApp(
      signalBloc: signalBloc,
      waveformModuleBloc: buildCursorBloc(const WaveformModuleError()),
      child: const SignalValuePanel(),
    );

    expect(find.text(bugReport), findsOneWidget);
    expect(find.byType(SignalTabContainer), findsNothing);
  });

  testWidgets('scrolls rows with arrow keys, the wheel, and drag auto-scroll', (
    tester,
  ) async {
    final scrollController = ScrollController();
    final dragController = DragReorderController();
    addTearDown(scrollController.dispose);
    addTearDown(dragController.dispose);

    final rows = List.generate(20, (index) => buildRow('top.s$index', index));
    final signalBloc = MockSignalBloc();
    when(() => signalBloc.state).thenReturn(SignalLoaded(const [], rows));

    await tester.pumpApp(
      signalBloc: signalBloc,
      waveformModuleBloc: buildCursorBloc(const UpdatedCursor(10)),
      child: SignalValuePanel(
        scrollController: scrollController,
        dragController: dragController,
      ),
    );

    expect(scrollController.offset, 0);
    expect(scrollController.position.maxScrollExtent, greaterThan(0));

    final headerCenter = tester.getCenter(find.text(signalsValuePanelTitle));
    await tester.tapAt(headerCenter);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(scrollController.offset, baseSignalRowHeight);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(scrollController.offset, 2 * baseSignalRowHeight);

    // Unhandled keys must not move the panel.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pump();
    expect(scrollController.offset, 2 * baseSignalRowHeight);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(scrollController.offset, 0);

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(headerCenter));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 12)));
    await tester.pump();
    expect(scrollController.offset, baseSignalRowHeight);

    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -12)));
    await tester.pump();
    expect(scrollController.offset, 0);

    // Dragging a row toward the bottom edge auto-scrolls the panel.
    final firstRow = tester.getCenter(find.byType(SignalTabContainer).first);
    final panelBottom = tester.getRect(find.byType(SignalValuePanel)).bottom;
    final gesture = await tester.startGesture(firstRow);
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    await gesture.moveTo(Offset(firstRow.dx, panelBottom - 5));
    await tester.pump();

    expect(dragController.isDragging, isTrue);
    expect(scrollController.offset, greaterThan(0));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(dragController.isDragging, isFalse);
  });

  testWidgets('right-click focuses a row then formats the focused group', (
    tester,
  ) async {
    final scalar = buildRow('top.a', 1);
    final bus = buildRow('top.b', 10);
    final signalBloc = MockSignalBloc();
    when(() => signalBloc.state).thenReturn(
      SignalLoaded(const [], [scalar, bus]),
    );

    await tester.pumpApp(
      signalBloc: signalBloc,
      waveformModuleBloc: buildCursorBloc(const UpdatedCursor(10)),
      child: const SignalValuePanel(),
    );

    expect(find.text('1'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);

    await tester.tapAt(
      tester.getCenter(find.byType(SignalTabContainer).at(1)),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    verify(() => signalBloc.add(SignalFocusEvent(bus))).called(1);
    expect(find.text('Hexadecimal'), findsOneWidget);

    await tester.tap(find.text('Hexadecimal'));
    await tester.pumpAndSettle();

    verify(
      () => signalBloc.add(
        SignalSetOccurrenceValueFormatEvent(
          signalPaths: {bus.signalId},
          valueFormat: MonitorValueFormat.hexadecimal,
        ),
      ),
    ).called(1);

    // A right-click inside an existing focus selection keeps the selection and
    // formats every focused row.
    when(() => signalBloc.state).thenReturn(
      SignalLoaded(
        const [],
        [scalar, bus],
        focusedSignalIds: {scalar.monitorId, bus.monitorId},
      ),
    );
    await tester.pumpApp(
      signalBloc: signalBloc,
      waveformModuleBloc: buildCursorBloc(const UpdatedCursor(10)),
      child: const SignalValuePanel(),
    );

    await tester.tapAt(
      tester.getCenter(find.byType(SignalTabContainer).first),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Binary'));
    await tester.pumpAndSettle();

    verifyNever(() => signalBloc.add(SignalFocusEvent(scalar)));
    verify(
      () => signalBloc.add(
        SignalSetOccurrenceValueFormatEvent(
          signalPaths: {scalar.signalId, bus.signalId},
          valueFormat: MonitorValueFormat.binary,
        ),
      ),
    ).called(1);
  });

  testWidgets('drags a single row and a focused group to reorder values', (
    tester,
  ) async {
    final dragController = DragReorderController();
    addTearDown(dragController.dispose);

    final rows = [
      buildRow('top.a', 1),
      buildRow('top.b', 2),
      buildRow('top.c', 3),
    ];
    final signalBloc = MockSignalBloc();
    when(() => signalBloc.state).thenReturn(SignalLoaded(const [], rows));

    await tester.pumpApp(
      signalBloc: signalBloc,
      waveformModuleBloc: buildCursorBloc(const UpdatedCursor(10)),
      child: SignalValuePanel(dragController: dragController),
    );

    final rowFinder = find.byType(SignalTabContainer);
    expect(rowFinder, findsNWidgets(3));

    final gesture =
        await tester.startGesture(tester.getCenter(rowFinder.at(2)));
    await gesture.moveBy(const Offset(0, -25));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -45));
    await tester.pump();

    expect(dragController.isDragging, isTrue);
    expect(dragController.sourceIndex, 2);
    expect(dragController.targetIndex, 0);
    expect(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              (widget.decoration as BoxDecoration).color != null,
        ),
      ),
      findsOneWidget,
    );

    await gesture.up();
    await tester.pumpAndSettle();

    expect(dragController.isDragging, isFalse);
    verify(
      () => signalBloc.add(SignalReorderEvent(oldIndex: 2, newIndex: 0)),
    ).called(1);

    // Dragging a member of a multi-row focus moves the whole group.
    when(() => signalBloc.state).thenReturn(
      SignalLoaded(
        const [],
        rows,
        focusedSignalIds: {rows[0].monitorId, rows[1].monitorId},
      ),
    );
    await tester.pumpApp(
      signalBloc: signalBloc,
      waveformModuleBloc: buildCursorBloc(const UpdatedCursor(10)),
      child: SignalValuePanel(dragController: dragController),
    );

    final groupGesture = await tester.startGesture(
      tester.getCenter(rowFinder.first),
    );
    await groupGesture.moveBy(const Offset(0, 25));
    await tester.pump();
    expect(dragController.isGroupDrag, isTrue);
    expect(dragController.groupIndices, [0, 1]);

    await groupGesture.moveBy(const Offset(0, 60));
    await tester.pump();
    await groupGesture.up();
    await tester.pumpAndSettle();

    verify(
      () => signalBloc.add(
        SignalGroupReorderEvent(
          oldIndices: const [0, 1],
          anchorOldIndex: 0,
          anchorNewIndex: 1,
        ),
      ),
    ).called(1);
  });

  testWidgets('renders video-mode values and hides empty time ranges', (
    tester,
  ) async {
    final row = buildRow('top.a', 7, atTime: 40);
    final signalBloc = MockSignalBloc();
    when(() => signalBloc.state).thenReturn(SignalLoaded(const [], [row]));

    const structure = ModuleStructure(
      metadata: MetaData(
        source: 'test',
        timescale: '1ps',
        date: 'today',
        endTime: 100,
      ),
      modules: [],
    );
    final rohdModuleBloc = MockRohdModuleBloc();
    when(() => rohdModuleBloc.state)
        .thenReturn(WaveformUpdated(structure, 100, dataEndTime: 50));

    await tester.pumpApp(
      rohdModuleBloc: rohdModuleBloc,
      signalBloc: signalBloc,
      waveformModuleBloc: buildCursorBloc(const InitialCursor()),
      child: const SignalValuePanel(isVideoMode: true),
    );

    expect(find.text('7'), findsOneWidget);

    when(() => rohdModuleBloc.state).thenReturn(const Rendered(structure));
    await tester.pumpApp(
      rohdModuleBloc: rohdModuleBloc,
      signalBloc: signalBloc,
      waveformModuleBloc: buildCursorBloc(const InitialCursor()),
      child: const SignalValuePanel(isVideoMode: true),
    );

    expect(find.text('7'), findsOneWidget);

    when(() => rohdModuleBloc.state).thenReturn(
      Rendered(ModuleStructure.empty()),
    );
    await tester.pumpApp(
      rohdModuleBloc: rohdModuleBloc,
      signalBloc: signalBloc,
      waveformModuleBloc: buildCursorBloc(const InitialCursor()),
      child: const SignalValuePanel(isVideoMode: true),
    );

    expect(find.byType(SignalTabContainer), findsNothing);
    expect(find.text('7'), findsNothing);
  });
}
