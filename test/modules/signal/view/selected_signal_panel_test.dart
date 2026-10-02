// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// selected_signal_panel_test.dart
// Tests for the selected signal panel.
//
// 2024 April
// Author(s): Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
//            Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:dart_wellen/dart_wellen.dart' hide SignalWaveform;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart';
import 'package:rohd_wave_viewer/src/const/const.dart';
import 'package:rohd_wave_viewer/src/modules/rohd_module/bloc/rohd_module_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/shared/widgets/drag_reorder_controller.dart';
import 'package:rohd_wave_viewer/src/modules/shared/widgets/signal_tab_container.dart';
import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/signal/view/selected_signal_panel.dart';
import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';
import 'package:rohd_wave_viewer/testing.dart';

import '../../../helpers.dart';

void main() {
  late RohdModuleBloc rohdModuleBloc;
  late SignalBloc signalBloc;

  late ModuleStructure mockModuleStructure;
  late HierarchyOccurrence selectedModule;
  late MockSignalWaveformApi signalWaveformApi;
  late SignalWaveformRepository signalWaveformRepository;
  late List<SignalOccurrence> signals;
  late List<SignalWaveform> monitorSignals;

  setUpAll(() {
    registerFallbackValue(SignalUnfocusEvent());
  });

  setUp(() async {
    rohdModuleBloc = MockRohdModuleBloc();
    signalBloc = MockSignalBloc();
    signalWaveformApi = MockSignalWaveformApi();
    signalWaveformRepository = SignalWaveformRepository(
      signalWaveformApi: signalWaveformApi,
    );
    mockModuleStructure = await signalWaveformApi.getModuleStructure();
    signalWaveformRepository.buildSignalCacheFromHierarchy(
      mockModuleStructure.modules,
    );
    selectedModule = mockModuleStructure.modules.first;
    signals = signalWaveformRepository.getSignalsBySelectedModule(
      selectedModule,
    );

    // Register signal lookup so SignalWaveform metadata accessors work
    SignalWaveform.signalLookup =
        (id) => signals.where((s) => s.name == id).firstOrNull;

    // Build monitor waveforms from the signal metadata
    monitorSignals =
        signals.map((s) => SignalWaveform(signalId: s.name)).toList();
  });

  tearDown(SignalWaveform.clearSignalLookup);

  group('Selected SignalOccurrence Panel', () {
    testWidgets(
      'Selected Signals show signals when there are send to be monitored.',
      (tester) async {
        when(
          () => rohdModuleBloc.state,
        ).thenReturn(Rendered(mockModuleStructure));

        when(
          () => signalBloc.state,
        ).thenReturn(SignalLoaded(signals, monitorSignals));

        await tester.pumpApp(
          rohdModuleBloc: rohdModuleBloc,
          signalBloc: signalBloc,
          child: const SelectedSignalsPanel(),
        );

        expect(find.byType(SignalTabContainer), findsAtLeastNWidgets(1));
      },
    );

    testWidgets('removes a focused signal loaded from a VCD fixture',
        (tester) async {
      await WellenSignalWaveformApi.init();
      final api = WellenSignalWaveformApi();
      await api.loadFile('test/fixtures/xz_transitions.vcd');
      final structure = await api.getModuleStructureOnly();
      final fixtureRepository = SignalWaveformRepository(
        signalWaveformApi: api,
      )..buildSignalCacheFromHierarchy(structure.modules);
      final fixtureModule = structure.modules.first;
      final fixtureSignals = fixtureRepository.getSignalsBySelectedModule(
        fixtureModule,
      );
      final fixtureSignal = fixtureSignals.firstWhere(
        (signal) => signal.name == 'bin_xz',
      );
      final fixtureSignalBloc = SignalBloc(fixtureRepository);
      addTearDown(fixtureSignalBloc.close);

      fixtureSignalBloc.add(SignalUpdateEvent(fixtureModule));
      await fixtureSignalBloc.stream
          .firstWhere((state) => state is SignalLoaded);
      fixtureSignalBloc.add(SignalSelectedEvent(fixtureSignal));
      await fixtureSignalBloc.stream.firstWhere(
        (state) => state.monitorSignalsList.isNotEmpty,
      );

      await tester.pumpApp(
        signalBloc: fixtureSignalBloc,
        child: const SelectedSignalsPanel(),
      );
      await tester.pump();

      await tester.tap(find.byType(SignalTabContainer));
      await tester.pump();
      expect(fixtureSignalBloc.state.hasFocusedSignals, isTrue);
      expect(
        Focus.of(
          tester.element(find.byType(SignalTabContainer)),
        ).hasFocus,
        isTrue,
      );

      await tester.tapAt(
        tester.getCenter(find.byType(SignalTabContainer)),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove Signal'));
      await tester.pump();
      expect(fixtureSignalBloc.state.monitorSignalsList, isEmpty);
    });

    testWidgets('Delete removes the focused duplicate monitor row', (
      tester,
    ) async {
      final fixtureSignalBloc = SignalBloc(signalWaveformRepository);
      addTearDown(fixtureSignalBloc.close);
      final signal = signals.first;

      fixtureSignalBloc
        ..add(SignalUpdateEvent(selectedModule))
        ..add(SignalSelectedEvent(signal))
        ..add(SignalSelectedEvent(signal));
      await fixtureSignalBloc.stream.firstWhere(
        (state) => state.monitorSignalsList.length == 2,
      );

      await tester.pumpApp(
        signalBloc: fixtureSignalBloc,
        child: const SelectedSignalsPanel(),
      );
      await tester.pump();

      final rows = find.byType(SignalTabContainer);
      await tester.tap(rows.at(1));
      await tester.pump();
      final focusedMonitorId = fixtureSignalBloc.state.focusedSignalIds.single;

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();

      expect(fixtureSignalBloc.state.monitorSignalsList, hasLength(1));
      expect(
        fixtureSignalBloc.state.monitorSignalsList.single.monitorId,
        isNot(focusedMonitorId),
      );
    });

    testWidgets(
      'expands a fixture bus into bits, chunks, and named fields',
      (tester) async {
        await WellenSignalWaveformApi.init();
        final api = WellenSignalWaveformApi();
        await api.loadFile('test/fixtures/xz_transitions.vcd');
        final structure = await api.getModuleStructureOnly();
        final fixtureRepository = SignalWaveformRepository(
          signalWaveformApi: api,
        )..buildSignalCacheFromHierarchy(structure.modules);
        final fixtureModule = structure.modules.first;
        final fixtureBus = fixtureRepository
            .getSignalsBySelectedModule(fixtureModule)
            .firstWhere((signal) => signal.width > 1);
        final fixtureSignalBloc = SignalBloc(fixtureRepository);
        addTearDown(fixtureSignalBloc.close);

        fixtureSignalBloc
          ..add(SignalUpdateEvent(fixtureModule))
          ..add(SignalRestoreMonitoredEvent([fixtureBus.path()]));
        await fixtureSignalBloc.stream.firstWhere(
          (state) => state.monitorSignalsList.length == 1,
        );

        List<String>? sentPaths;
        RohdSourceFormat? sourceFormat;
        List<String>? sourcePaths;
        await tester.pumpApp(
          signalBloc: fixtureSignalBloc,
          child: SelectedSignalsPanel(
            onSendSignals: (paths) => sentPaths = paths,
            onGoToSource: (format, paths) {
              sourceFormat = format;
              sourcePaths = paths;
            },
            availableSourceFormats: () => const [
              RohdSourceFormat.rohd,
              RohdSourceFormat.sc,
            ],
          ),
        );
        await tester.pump();

        final parentRow = find.byType(SignalTabContainer);
        expect(parentRow, findsOneWidget);
        await tester.tapAt(
          tester.getCenter(parentRow),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        expect(find.text('Go to ROHD Source'), findsOneWidget);
        expect(find.text('Go to SV Source'), findsNothing);
        expect(find.text('Go to SystemC Source'), findsOneWidget);
        await tester.tap(find.text('Send Signal'));
        await tester.pump();
        expect(sentPaths, [fixtureBus.path()]);

        await tester.tapAt(
          tester.getCenter(parentRow),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Go to ROHD Source'));
        await tester.pump();
        expect(sourceFormat, RohdSourceFormat.rohd);
        expect(sourcePaths, sentPaths);

        var parent = fixtureSignalBloc.state.monitorSignalsList.single;
        fixtureSignalBloc
          ..add(
            SignalSetValueFormatEvent(
              monitorIds: {parent.monitorId},
              valueFormat: MonitorValueFormat.hexadecimal,
            ),
          )
          ..add(
            SignalSetMonitorGroupEvent(
              monitorIds: {parent.monitorId},
              groupName: 'fixture-bus',
            ),
          );
        await tester.pump();
        parent = fixtureSignalBloc.state.monitorSignalsList.single;
        expect(parent.valueFormat, MonitorValueFormat.hexadecimal);
        expect(parent.monitorGroup, 'fixture-bus');

        final expanded = fixtureSignalBloc.stream.firstWhere(
          (state) => state.monitorSignalsList.length == 4,
        );
        fixtureSignalBloc.add(
          SignalBitExpandEvent(
            waveform: parent,
            index: 0,
            bitStart: 0,
            bitEnd: 2,
          ),
        );
        await expanded;
        expect(
            fixtureSignalBloc.state.monitorSignalsList.first.name, parent.name);
        expect(
          fixtureSignalBloc.state.monitorSignalsList
              .skip(1)
              .map((waveform) => waveform.overrideName),
          ['${parent.name}[2]', '${parent.name}[1]', '${parent.name}[0]'],
        );

        final chunked = fixtureSignalBloc.stream.firstWhere(
          (state) => state.monitorSignalsList.length == 7,
        );
        fixtureSignalBloc.add(
          SignalBitChunkEvent(
            waveform: parent,
            index: 0,
            bitOffset: 0,
            chunkWidth: 2,
          ),
        );
        await chunked;
        final chunkRows = fixtureSignalBloc.state.monitorSignalsList.skip(4);
        expect(
          chunkRows.map((waveform) => waveform.overrideName),
          ['${parent.name}[4]', '${parent.name}[3:2]', '${parent.name}[1:0]'],
        );
        expect(
          chunkRows.map((waveform) => waveform.monitorGroup),
          everyElement('fixture-bus'),
        );

        final fielded = fixtureSignalBloc.stream.firstWhere(
          (state) => state.monitorSignalsList.length == 9,
        );
        fixtureSignalBloc.add(
          SignalBitFieldsEvent(
            waveform: parent,
            index: 0,
            fields: const [
              BitFieldDef(name: 'upper', high: 4, low: 3),
              BitFieldDef(name: 'lower', high: 2, low: 0),
            ],
          ),
        );
        await fielded;
        expect(
          fixtureSignalBloc.state.monitorSignalsList
              .skip(7)
              .map((waveform) => waveform.overrideName),
          ['${parent.name}.upper', '${parent.name}.lower'],
        );
        expect(find.byType(SignalTabContainer), findsOneWidget);
      },
    );

    testWidgets(
      'reorders, removes, undoes, and redoes fixture signal selections',
      (tester) async {
        await WellenSignalWaveformApi.init();
        final api = WellenSignalWaveformApi();
        await api.loadFile('test/fixtures/xz_transitions.vcd');
        final structure = await api.getModuleStructureOnly();
        final fixtureRepository = SignalWaveformRepository(
          signalWaveformApi: api,
        )..buildSignalCacheFromHierarchy(structure.modules);
        final fixtureModule = structure.modules.first;
        final fixtureSignals = fixtureRepository
            .getSignalsBySelectedModule(fixtureModule)
            .take(3)
            .toList();
        final fixtureSignalIds =
            fixtureSignals.map((signal) => signal.path()).toList();
        final fixtureSignalBloc = SignalBloc(fixtureRepository);
        final dragController = DragReorderController();
        addTearDown(fixtureSignalBloc.close);
        addTearDown(dragController.dispose);

        expect(fixtureSignals, hasLength(3));
        fixtureSignalBloc
          ..add(SignalUpdateEvent(fixtureModule))
          ..add(SignalRestoreMonitoredEvent(fixtureSignalIds));
        await fixtureSignalBloc.stream.firstWhere(
          (state) => state.monitorSignalsList.length == 3,
        );

        await tester.pumpApp(
          signalBloc: fixtureSignalBloc,
          child: SelectedSignalsPanel(dragController: dragController),
        );
        await tester.pump();

        final signalRows = find.byType(SignalTabContainer);
        expect(signalRows, findsNWidgets(3));
        await tester.tap(signalRows.at(0));
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.tap(signalRows.at(1));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        expect(fixtureSignalBloc.state.focusedSignalIds, hasLength(2));
        final focusedWaveforms = fixtureSignalBloc.state.focusedSignals;
        expect(focusedWaveforms, hasLength(2));

        await tester.drag(signalRows.at(2), const Offset(0, -80));
        await tester.pumpAndSettle();
        expect(
          fixtureSignalBloc.state.monitorSignalsList
              .map((waveform) => waveform.signalId),
          [fixtureSignalIds[2], fixtureSignalIds[0], fixtureSignalIds[1]],
        );

        for (final waveform in focusedWaveforms) {
          fixtureSignalBloc.add(SignalRemoveEvent(waveform));
        }
        await tester.pump();
        expect(
          fixtureSignalBloc.state.monitorSignalsList
              .map((waveform) => waveform.signalId),
          [fixtureSignalIds[2]],
        );

        fixtureSignalBloc.add(SignalUndoMonitorEvent());
        await tester.pump();
        expect(
          fixtureSignalBloc.state.monitorSignalsList
              .map((waveform) => waveform.signalId),
          [fixtureSignalIds[2], fixtureSignalIds[1]],
        );

        fixtureSignalBloc.add(SignalUndoMonitorEvent());
        await tester.pump();
        expect(
          fixtureSignalBloc.state.monitorSignalsList
              .map((waveform) => waveform.signalId),
          [fixtureSignalIds[2], fixtureSignalIds[0], fixtureSignalIds[1]],
        );

        fixtureSignalBloc.add(SignalUndoMonitorEvent());
        await tester.pump();
        expect(
          fixtureSignalBloc.state.monitorSignalsList
              .map((waveform) => waveform.signalId),
          fixtureSignalIds,
        );

        fixtureSignalBloc.add(SignalRedoMonitorEvent());
        await tester.pump();
        expect(
          fixtureSignalBloc.state.monitorSignalsList
              .map((waveform) => waveform.signalId),
          [fixtureSignalIds[2], fixtureSignalIds[0], fixtureSignalIds[1]],
        );

        fixtureSignalBloc.add(SignalRedoMonitorEvent());
        await tester.pump();
        expect(
          fixtureSignalBloc.state.monitorSignalsList
              .map((waveform) => waveform.signalId),
          [fixtureSignalIds[2], fixtureSignalIds[1]],
        );

        fixtureSignalBloc.add(SignalRedoMonitorEvent());
        await tester.pump();
        expect(
          fixtureSignalBloc.state.monitorSignalsList
              .map((waveform) => waveform.signalId),
          [fixtureSignalIds[2]],
        );
      },
    );
  });

  group('Selected Signals Panel viewport interactions', () {
    /// Builds [count] monitor rows so the list overflows the panel viewport.
    List<SignalWaveform> buildOverflowRows(int count) => List.generate(
          count,
          (index) => SignalWaveform(
            signalId: signals[index % signals.length].name,
            monitorId: 'row$index',
          ),
        );

    /// Moves a synthetic mouse over the panel so it takes keyboard focus.
    Future<void> hoverPanel(WidgetTester tester) async {
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(
        tester.getCenter(find.byType(SelectedSignalsPanel)),
      );
      await tester.pump();
    }

    testWidgets('arrow keys and the mouse wheel scroll the monitor list', (
      tester,
    ) async {
      when(() => signalBloc.state).thenReturn(
        SignalLoaded(signals, buildOverflowRows(30)),
      );
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpApp(
        signalBloc: signalBloc,
        child: SelectedSignalsPanel(scrollController: scrollController),
      );
      await tester.pump();
      await hoverPanel(tester);

      expect(scrollController.position.maxScrollExtent, greaterThan(0));

      // Arrow-up at the top of the list is clamped away.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(scrollController.offset, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(scrollController.offset, baseSignalRowHeight);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(scrollController.offset, 2 * baseSignalRowHeight);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(scrollController.offset, baseSignalRowHeight);

      // An unhandled key leaves the viewport untouched.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
      await tester.pump();
      expect(scrollController.offset, baseSignalRowHeight);

      final beforeWheel = scrollController.offset;
      final pointer = TestPointer(4, PointerDeviceKind.mouse);
      final wheelPosition = tester.getCenter(
        find.byType(SignalTabContainer).first,
      );
      await tester.sendEventToBinding(pointer.hover(wheelPosition));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 20)));
      await tester.pump();
      expect(
        scrollController.offset,
        greaterThanOrEqualTo(beforeWheel + baseSignalRowHeight),
      );

      final beforeWheelUp = scrollController.offset;
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -20)));
      await tester.pump();
      expect(scrollController.offset, lessThan(beforeWheelUp));
    });

    testWidgets('Ctrl+A focuses every monitored signal', (tester) async {
      when(() => signalBloc.state).thenReturn(
        SignalLoaded(signals, buildOverflowRows(30)),
      );
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpApp(
        signalBloc: signalBloc,
        child: SelectedSignalsPanel(scrollController: scrollController),
      );
      await tester.pump();
      await hoverPanel(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      verify(() => signalBloc.add(SignalFocusAllEvent())).called(1);

      // The meta key is the macOS-style equivalent.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();

      verify(() => signalBloc.add(SignalFocusAllEvent())).called(1);
    });

    testWidgets('Delete without a focused row leaves the monitor list alone', (
      tester,
    ) async {
      final rows = buildOverflowRows(3);
      when(() => signalBloc.state).thenReturn(SignalLoaded(signals, rows));

      await tester.pumpApp(
        signalBloc: signalBloc,
        child: const SelectedSignalsPanel(),
      );
      await tester.pump();
      await hoverPanel(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();

      verifyNever(() => signalBloc.add(SignalRemoveEvent(rows.first)));
    });

    testWidgets('group drag auto-scrolls the viewport and commits a reorder', (
      tester,
    ) async {
      when(() => signalBloc.state).thenReturn(
        SignalLoaded(
          signals,
          buildOverflowRows(30),
          focusedSignalIds: const {'row0', 'row1'},
        ),
      );
      final scrollController = ScrollController();
      final dragController = DragReorderController();
      addTearDown(scrollController.dispose);
      addTearDown(dragController.dispose);

      await tester.pumpApp(
        signalBloc: signalBloc,
        child: SelectedSignalsPanel(
          scrollController: scrollController,
          dragController: dragController,
        ),
      );
      await tester.pump();

      final listRect = tester.getRect(find.byType(ListView));
      final start = tester.getCenter(find.byType(SignalTabContainer).first);
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();

      expect(dragController.isDragging, isTrue);
      expect(dragController.isGroupDrag, isTrue);
      expect(dragController.groupIndices, [0, 1]);

      // Hold the pointer inside the bottom auto-scroll band.
      await gesture.moveTo(Offset(start.dx, listRect.bottom - 6));
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await gesture.moveBy(const Offset(0, 1));
        await tester.pump();
        await gesture.moveBy(const Offset(0, -1));
        await tester.pump();
      }
      final afterBottomBand = scrollController.offset;
      expect(afterBottomBand, greaterThan(0));

      // Then drag back into the top band so the viewport scrolls back up
      // and finally clamps at the start of the list.
      await gesture.moveTo(Offset(start.dx, listRect.top + 6));
      await tester.pump();
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(0, 1));
        await tester.pump();
        await gesture.moveBy(const Offset(0, -1));
        await tester.pump();
      }
      expect(scrollController.offset, lessThan(afterBottomBand));
      expect(scrollController.offset, 0);

      // Settle back into the middle of the list so the drop lands on a new
      // index rather than back on the source row.
      await gesture.moveBy(const Offset(0, 120));
      await tester.pump();
      expect(dragController.targetIndex, greaterThan(0));

      await gesture.up();
      await tester.pump();

      verify(
        () => signalBloc.add(any(that: isA<SignalGroupReorderEvent>())),
      ).called(1);
      expect(dragController.isDragging, isFalse);
    });
  });

  group('Selected Signals Panel selection and context menu', () {
    /// Creates a bloc whose monitor list holds every signal of the module.
    Future<SignalBloc> pumpMonitoredPanel(
      WidgetTester tester, {
      List<SignalOccurrence>? monitored,
    }) async {
      final selected = monitored ?? signals;
      final bloc = SignalBloc(signalWaveformRepository);
      addTearDown(bloc.close);
      bloc.add(SignalUpdateEvent(selectedModule));
      await bloc.stream.firstWhere((state) => state is SignalLoaded);
      for (final signal in selected) {
        bloc.add(SignalSelectedEvent(signal));
      }
      await bloc.stream.firstWhere(
        (state) => state.monitorSignalsList.length == selected.length,
      );

      await tester.pumpApp(
        signalBloc: bloc,
        child: const SelectedSignalsPanel(),
      );
      await tester.pump();
      return bloc;
    }

    testWidgets('tap, shift-click, and re-tap cycle the selection', (
      tester,
    ) async {
      final bloc = await pumpMonitoredPanel(tester);
      final rows = find.byType(SignalTabContainer);
      expect(rows, findsNWidgets(signals.length));

      await tester.tap(rows.at(0));
      await tester.pump();
      expect(bloc.state.focusedSignalIds, hasLength(1));

      // Shift-click extends from the anchor set by the previous tap.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tap(rows.at(2));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(bloc.state.focusedSignalIds, hasLength(3));

      // The anchor is preserved, so a second shift-click grows the range.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tap(rows.at(3));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(bloc.state.focusedSignalIds, hasLength(4));

      // A plain tap on a focused row clears the whole selection.
      await tester.tap(rows.at(0));
      await tester.pump();
      expect(bloc.state.focusedSignalIds, isEmpty);

      // Ctrl-click on an unfocused row adds it to the selection.
      await tester.tap(rows.at(0));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(rows.at(3));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(bloc.state.focusedSignalIds, hasLength(2));
    });

    testWidgets('ctrl-click on a focused row unfocuses just that row', (
      tester,
    ) async {
      final rows = [
        SignalWaveform(signalId: signals[0].name),
        SignalWaveform(signalId: signals[1].name),
      ];
      when(() => signalBloc.state).thenReturn(
        SignalLoaded(
          signals,
          rows,
          focusedSignalIds: {rows[0].monitorId, rows[1].monitorId},
        ),
      );

      await tester.pumpApp(
        signalBloc: signalBloc,
        child: const SelectedSignalsPanel(),
      );
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(find.byType(SignalTabContainer).at(1));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      verify(
        () => signalBloc.add(SignalUnfocusOneEvent(rows[1].id)),
      ).called(1);
    });

    testWidgets('context menu copies names and paths for a multi-selection', (
      tester,
    ) async {
      SignalWaveform.signalLookup = (id) =>
          signals.where((s) => s.name == id || s.path() == id).firstOrNull;
      final clipboardTexts = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardTexts.add(
              (call.arguments as Map<Object?, Object?>)['text']! as String,
            );
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      final bloc = await pumpMonitoredPanel(tester);
      final rows = find.byType(SignalTabContainer);

      await tester.tap(rows.at(0));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(rows.at(1));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(bloc.state.focusedSignalIds, hasLength(2));

      await tester.tapAt(
        tester.getCenter(rows.at(0)),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy 2 Names'));
      await tester.pumpAndSettle();
      expect(clipboardTexts, hasLength(1));
      expect(
        clipboardTexts.single.split('\n'),
        [signals[0].name, signals[1].name],
      );

      await tester.tapAt(
        tester.getCenter(rows.at(0)),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy 2 Full Paths'));
      await tester.pumpAndSettle();
      expect(clipboardTexts, hasLength(2));
      expect(
        clipboardTexts.last.split('\n'),
        [signals[0].path(), signals[1].path()],
      );
    });

    testWidgets('context menu applies a display format to the selection', (
      tester,
    ) async {
      SignalWaveform.signalLookup = (id) =>
          signals.where((s) => s.name == id || s.path() == id).firstOrNull;
      addTearDown(SignalValueFormatRegistry.clear);

      final bloc = await pumpMonitoredPanel(tester);
      final rows = find.byType(SignalTabContainer);

      await tester.tap(rows.at(0));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(rows.at(1));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      await tester.tapAt(
        tester.getCenter(rows.at(0)),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Format 2 Signals As'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hexadecimal'));
      await tester.pumpAndSettle();

      final formatted = bloc.state.monitorSignalsList.take(2);
      expect(
        formatted.map((waveform) => waveform.valueFormat),
        everyElement(MonitorValueFormat.hexadecimal),
      );
      expect(
        bloc.state.monitorSignalsList.last.valueFormat,
        MonitorValueFormat.waveform,
      );
    });

    testWidgets('context menu expands bits and defines named bit fields', (
      tester,
    ) async {
      SignalWaveform.signalLookup = (id) =>
          signals.where((s) => s.name == id || s.path() == id).firstOrNull;
      final wideSignal = signals.firstWhere((signal) => signal.width > 1);
      final bloc = await pumpMonitoredPanel(tester, monitored: [wideSignal]);
      final rows = find.byType(SignalTabContainer);

      await tester.tapAt(
        tester.getCenter(rows.first),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Expand Bits [${wideSignal.width}]'));
      await tester.pumpAndSettle();

      expect(
        bloc.state.monitorSignalsList,
        hasLength(1 + wideSignal.width),
      );
      expect(
        bloc.state.monitorSignalsList[1].overrideName,
        '${wideSignal.name}[${wideSignal.width - 1}]',
      );

      await tester.tapAt(
        tester.getCenter(rows.first),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Define Bit Fields [${wideSignal.width}]...'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(
        bloc.state.monitorSignalsList.map((waveform) => waveform.overrideName),
        contains('${wideSignal.name}.field0'),
      );
    });

    testWidgets(
      'FST structure field has waveform data, width, and bit expansion menu',
      (tester) async {
        await WellenSignalWaveformApi.init();
        final api = WellenSignalWaveformApi();
        await api.loadFile(
          'packages/dart_wellen/test/fixtures/filter_bank.fst',
        );
        final structure = await api.getModuleStructureOnly();
        final filterBank = structure.modules.firstWhere(
          (module) => module.name == 'FilterBank',
        );
        final sample = filterBank.signals.firstWhere(
          (signal) => signal.name == 'sample1',
        );
        final repository = SignalWaveformRepository(signalWaveformApi: api)
          ..buildSignalCacheFromHierarchy(structure.modules);
        final bloc = SignalBloc(repository);
        addTearDown(bloc.close);

        bloc.add(SignalUpdateEvent(filterBank));
        await bloc.stream.firstWhere((state) => state is SignalLoaded);
        bloc.add(SignalSelectedEvent(sample));
        await bloc.stream.firstWhere(
          (state) => state.monitorSignalsList.length == 1,
        );
        final parent = bloc.state.monitorSignalsList.single;
        bloc.add(SignalExpandMonitorEvent(waveform: parent, index: 0));
        await bloc.stream.firstWhere(
          (state) => state.monitorSignalsList.length == 3,
        );

        final dataField = bloc.state.monitorSignalsList.firstWhere(
          (waveform) => waveform.signalId.endsWith('#data'),
        );
        expect(dataField.width, 16);
        expect(dataField.data, isNotEmpty);
        expect(dataField.isComputed, isTrue);

        await tester.pumpApp(
          signalBloc: bloc,
          child: const SelectedSignalsPanel(),
        );
        await tester.pump();

        final dataRow = find.byType(SignalTabContainer).at(1);
        await tester.tapAt(
          tester.getCenter(dataRow),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();

        expect(find.text('Expand Bits [16]'), findsOneWidget);
        expect(find.text('Define Bit Fields [16]...'), findsOneWidget);
      },
    );
  });

  group('Selected Signals Panel struct and array expansion', () {
    /// Pumps the panel with a single monitored [occurrence] row.
    Future<SignalWaveform> pumpExpandablePanel(
      WidgetTester tester,
      SignalOccurrence occurrence, {
      Set<String> expandedMonitorSignals = const {},
    }) async {
      tester.platformDispatcher.textScaleFactorTestValue = 0.7;
      addTearDown(
        tester.platformDispatcher.clearTextScaleFactorTestValue,
      );
      SignalWaveform.signalLookup =
          (id) => id == occurrence.name ? occurrence : null;
      final waveform = SignalWaveform(signalId: occurrence.name);
      when(() => signalBloc.state).thenReturn(
        SignalLoaded(
          [occurrence],
          [waveform],
          expandedMonitorSignals: expandedMonitorSignals,
        ),
      );
      await tester.pumpApp(
        signalBloc: signalBloc,
        child: const SelectedSignalsPanel(),
      );
      await tester.pump();
      return waveform;
    }

    SignalOccurrence buildStruct(int fieldCount) => SignalOccurrence(
          name: 'sample',
          width: fieldCount,
          logicType: {
            'typeName': 'Sample',
            'fields': List.generate(
              fieldCount,
              (i) => {
                'name': 'f$i',
                'width': 1,
                'bits': [i],
              },
            ),
          },
        );

    SignalOccurrence buildArray(int elements) => SignalOccurrence(
          name: 'samples',
          width: elements * 16,
          logicType: {
            'width': elements * 16,
            'arrayDims': [elements],
            'elementWidth': 16,
          },
        );

    testWidgets('chevron expands a small struct without prompting', (
      tester,
    ) async {
      final waveform = await pumpExpandablePanel(tester, buildStruct(3));

      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();

      verify(
        () => signalBloc.add(
          SignalExpandMonitorEvent(waveform: waveform, index: 0),
        ),
      ).called(1);
    });

    testWidgets('chevron collapses an already expanded struct', (tester) async {
      final waveform = await pumpExpandablePanel(
        tester,
        buildStruct(3),
        expandedMonitorSignals: const {'sample'},
      );

      expect(find.byIcon(Icons.expand_more), findsOneWidget);
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pumpAndSettle();

      verify(
        () => signalBloc.add(SignalCollapseMonitorEvent(waveform: waveform)),
      ).called(1);
    });

    testWidgets('chevron on a struct without sub-fields does nothing', (
      tester,
    ) async {
      final emptyStruct = SignalOccurrence(
        name: 'sample',
        width: 4,
        logicType: const {'typeName': 'Sample', 'fields': <dynamic>[]},
      );
      final waveform = await pumpExpandablePanel(tester, emptyStruct);

      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();

      expect(find.byType(PopupMenuItem<String>), findsNothing);
      verifyNever(
        () => signalBloc.add(
          SignalExpandMonitorEvent(waveform: waveform, index: 0),
        ),
      );
    });

    testWidgets('field picker expands all elements or a single element', (
      tester,
    ) async {
      final waveform = await pumpExpandablePanel(tester, buildArray(12));

      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      expect(find.text('Expand All (12 elements)'), findsOneWidget);
      expect(find.text('Select Range (0:11)...'), findsOneWidget);
      await tester.tap(find.text('Expand All (12 elements)'));
      await tester.pumpAndSettle();
      verify(
        () => signalBloc.add(
          SignalExpandMonitorEvent(waveform: waveform, index: 0),
        ),
      ).called(1);

      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      await tester.tap(find.text('[3]  [16b]'));
      await tester.pumpAndSettle();
      verify(
        () => signalBloc.add(
          SignalExpandMonitorEvent(
            waveform: waveform,
            index: 0,
            fieldIndices: const [3],
          ),
        ),
      ).called(1);
    });

    testWidgets('field picker range dialog parses ranges and single indices', (
      tester,
    ) async {
      final waveform = await pumpExpandablePanel(tester, buildArray(12));

      Future<void> openRangeDialog() async {
        await tester.tap(find.byIcon(Icons.chevron_right));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Select Range (0:11)...'));
        await tester.pumpAndSettle();
        expect(find.text('samples  [12 elements]'), findsOneWidget);
      }

      await openRangeDialog();
      await tester.enterText(find.byType(TextField), '4:2');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      verify(
        () => signalBloc.add(
          SignalExpandMonitorEvent(
            waveform: waveform,
            index: 0,
            fieldIndices: const [2, 3, 4],
          ),
        ),
      ).called(1);

      // Submitting the text field commits the same way the OK button does.
      await openRangeDialog();
      await tester.enterText(find.byType(TextField), '7');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      verify(
        () => signalBloc.add(
          SignalExpandMonitorEvent(
            waveform: waveform,
            index: 0,
            fieldIndices: const [7],
          ),
        ),
      ).called(1);

      // Cancelling and malformed input are both ignored.
      await openRangeDialog();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      for (final invalidInput in ['', '1:2:3', 'foo:bar', 'abc']) {
        await openRangeDialog();
        await tester.enterText(find.byType(TextField), invalidInput);
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
      }

      verifyNever(
        () => signalBloc.add(
          SignalExpandMonitorEvent(
            waveform: waveform,
            index: 0,
            fieldIndices: const [0],
          ),
        ),
      );
    });

    testWidgets('field picker lists struct fields without a range option', (
      tester,
    ) async {
      final waveform = await pumpExpandablePanel(tester, buildStruct(10));

      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      expect(find.text('Expand All (10 fields)'), findsOneWidget);
      expect(find.textContaining('Select Range'), findsNothing);

      await tester.tap(find.text('f5  [1b]'));
      await tester.pumpAndSettle();
      verify(
        () => signalBloc.add(
          SignalExpandMonitorEvent(
            waveform: waveform,
            index: 0,
            fieldIndices: const [5],
          ),
        ),
      ).called(1);
    });

    testWidgets('field picker truncates very large arrays', (tester) async {
      final waveform = await pumpExpandablePanel(tester, buildArray(24));

      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      expect(find.text('Expand All (24 elements)'), findsOneWidget);
      expect(find.text('[19]  [16b]'), findsOneWidget);
      expect(find.text('[20]  [16b]'), findsNothing);
      expect(find.text('... 4 more (use Range)'), findsOneWidget);

      // Dismiss the menu without picking anything.
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      verifyNever(
        () => signalBloc.add(
          SignalExpandMonitorEvent(waveform: waveform, index: 0),
        ),
      );
    });
  });
}
