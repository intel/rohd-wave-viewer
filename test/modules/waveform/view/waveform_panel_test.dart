// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// waveform_panel_test.dart
// Tests for the waveform panel.
//
// 2024 April
// Author(s): Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
//            Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:dart_wellen/dart_wellen.dart' hide SignalWaveform;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rohd_wave_viewer/src/const/layout.dart';
import 'package:rohd_wave_viewer/src/cubit/waveform_scale_cubit.dart';
import 'package:rohd_wave_viewer/src/modules/rohd_module/bloc/rohd_module_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/bloc/waveform_module_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/view/waveform_panel.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/view/widgets/timescale.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/view/widgets/waveform_background.dart';
import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';
import 'package:rohd_wave_viewer/testing.dart';

import '../../../helpers.dart';

void main() {
  late RohdModuleBloc rohdModuleBloc;
  late WaveformModuleBloc waveformModuleBloc;
  late SignalBloc signalBloc;

  late ModuleStructure mockModuleStructure;
  late HierarchyOccurrence selectedModule;
  late MockSignalWaveformApi signalWaveformApi;
  late SignalWaveformRepository signalWaveformRepository;
  late SignalDataService signalDataService;
  late List<SignalOccurrence> signals;

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
    waveformModuleBloc = WaveformModuleBloc(
      signalWaveformRepository: signalWaveformRepository,
    );
    // Create SignalDataService for WaveformPanel
    signalDataService = RepositorySignalDataService(signalWaveformRepository);
  });

  group('Waveform Panel', () {
    testWidgets(
      'Waveform Panel contains a waveform background.',
      (tester) async {
        when(
          () => rohdModuleBloc.state,
        ).thenReturn(Rendered(mockModuleStructure));

        when(
          () => signalBloc.state,
        ).thenReturn(SignalLoaded(signals, const []));

        await tester.pumpWidget(
          MaterialApp(
            home: MultiBlocProvider(
              providers: [
                BlocProvider<RohdModuleBloc>.value(value: rohdModuleBloc),
                BlocProvider<SignalBloc>.value(value: signalBloc),
                BlocProvider<WaveformModuleBloc>.value(
                  value: waveformModuleBloc,
                ),
                BlocProvider<WaveformScaleCubit>(
                  create: (_) => WaveformScaleCubit(),
                ),
                // Provide SignalDataService
                RepositoryProvider<SignalDataService>.value(
                  value: signalDataService,
                ),
              ],
              child: const WaveformPanel(),
            ),
          ),
        );

        expect(find.byType(WaveformBackground), findsAtLeastNWidgets(1));
      },
    );

    testWidgets('passes wheel zoom through a clipped-value hover tooltip', (
      tester,
    ) async {
      final clippedBus = SignalWaveform(
        signalId: 'test/clipped_bus',
        overrideWidth: 16,
        data: [
          Data(time: 0, value: '1111111111111111'),
          Data(time: 1, value: '0000000000000000'),
          Data(time: 20, value: '1111111111111111'),
        ],
      );
      final viewportNotifier = ValueNotifier(const WaveformViewport());
      addTearDown(viewportNotifier.dispose);

      when(() => rohdModuleBloc.state)
          .thenReturn(Rendered(mockModuleStructure));
      when(() => signalBloc.state).thenReturn(
        SignalLoaded(const [], [clippedBus]),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiBlocProvider(
              providers: [
                BlocProvider<RohdModuleBloc>.value(value: rohdModuleBloc),
                BlocProvider<SignalBloc>.value(value: signalBloc),
                BlocProvider<WaveformModuleBloc>.value(
                  value: waveformModuleBloc,
                ),
                BlocProvider<WaveformScaleCubit>(
                  create: (_) => WaveformScaleCubit(),
                ),
                RepositoryProvider<SignalDataService>.value(
                  value: signalDataService,
                ),
              ],
              child: WaveformPanel(viewportNotifier: viewportNotifier),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final waveform = find.byType(WaveformBackground);
      final hoverPosition = tester.getTopLeft(waveform) + const Offset(42, 12);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: hoverPosition);
      await mouse.moveTo(hoverPosition);
      await tester.pump(const Duration(milliseconds: 61));
      final hoverTooltip = find.byKey(
        const ValueKey('waveform-hover-tooltip'),
      );
      expect(hoverTooltip, findsOneWidget);
      final tooltipPosition = tester.getCenter(hoverTooltip);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tooltipPosition,
          scrollDelta: const Offset(0, -20),
        ),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(viewportNotifier.value.zoomLevel, greaterThan(1));
    });

    testWidgets('navigates a focused fixture waveform to its next transition',
        (tester) async {
      await WellenSignalWaveformApi.init();
      final api = WellenSignalWaveformApi();
      await api.loadFile('test/fixtures/xz_transitions.vcd');
      final structure = await api.getModuleStructureOnly();
      final fixtureWaveform = (await api.getWaveformData(
        signalIds: structure.allSignalIds,
      ))
          .firstWhere(
        (waveform) =>
            waveform.data.any(
              (datum) => datum.value.toLowerCase() == 'x',
            ) &&
            waveform.data.any(
              (datum) => datum.value.toLowerCase() == 'z',
            ),
      );
      final monitoredWaveform = SignalWaveform.fromWaveformData(
        fixtureWaveform,
      );
      final expectedTime = monitoredWaveform
          .data[monitoredWaveform.getNextDataPointIndex(-1)].time;
      final fixtureRepository = SignalWaveformRepository(
        signalWaveformApi: api,
      );
      final fixtureCursorBloc = WaveformModuleBloc(
        signalWaveformRepository: fixtureRepository,
      );
      addTearDown(fixtureCursorBloc.close);

      when(() => rohdModuleBloc.state).thenReturn(Rendered(structure));
      when(() => signalBloc.state).thenReturn(
        SignalLoaded(
          const [],
          [monitoredWaveform],
          focusedSignalIds: {monitoredWaveform.id},
        ),
      );

      final cursorUpdate = fixtureCursorBloc.stream.firstWhere(
        (state) => state is UpdatedCursor,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<RohdModuleBloc>.value(value: rohdModuleBloc),
              BlocProvider<SignalBloc>.value(value: signalBloc),
              BlocProvider<WaveformModuleBloc>.value(value: fixtureCursorBloc),
              BlocProvider<WaveformScaleCubit>(
                create: (_) => WaveformScaleCubit(),
              ),
              RepositoryProvider<SignalDataService>.value(
                value: RepositorySignalDataService(fixtureRepository),
              ),
            ],
            child: const WaveformPanel(),
          ),
        ),
      );
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);

      expect((await cursorUpdate).timePs, expectedTime);
    });

    testWidgets(
      'navigates from an existing marker after a signal is focused',
      (tester) async {
        await WellenSignalWaveformApi.init();
        final api = WellenSignalWaveformApi();
        await api.loadFile('test/fixtures/xz_transitions.vcd');
        final structure = await api.getModuleStructureOnly();
        final repository = SignalWaveformRepository(signalWaveformApi: api)
          ..buildSignalCacheFromHierarchy(structure.modules);
        final fixtureSignalBloc = SignalBloc(repository);
        final fixtureCursorBloc = WaveformModuleBloc(
          signalWaveformRepository: repository,
        );
        addTearDown(fixtureSignalBloc.close);
        addTearDown(fixtureCursorBloc.close);

        final fixtureModule = structure.firstModuleWithSignals!;
        final fixtureSignal = fixtureModule.signals.firstWhere(
          (signal) => signal.name == 'bin_xz',
        );
        fixtureSignalBloc
          ..add(SignalUpdateEvent(fixtureModule))
          ..add(SignalSelectedEvent(fixtureSignal));
        await fixtureSignalBloc.stream.firstWhere(
          (state) => state.monitorSignalsList.length == 1,
        );
        final monitoredWaveform =
            fixtureSignalBloc.state.monitorSignalsList.single;
        final markerTime = monitoredWaveform.data.first.time;
        final expectedTime = monitoredWaveform
            .data[monitoredWaveform.getNextDataPointIndex(markerTime)].time;

        when(() => rohdModuleBloc.state).thenReturn(Rendered(structure));
        await tester.pumpWidget(
          MaterialApp(
            home: MultiBlocProvider(
              providers: [
                BlocProvider<RohdModuleBloc>.value(value: rohdModuleBloc),
                BlocProvider<SignalBloc>.value(value: fixtureSignalBloc),
                BlocProvider<WaveformModuleBloc>.value(
                  value: fixtureCursorBloc,
                ),
                BlocProvider<WaveformScaleCubit>(
                  create: (_) => WaveformScaleCubit(),
                ),
                RepositoryProvider<SignalDataService>.value(
                  value: RepositorySignalDataService(repository),
                ),
              ],
              child: const WaveformPanel(),
            ),
          ),
        );
        await tester.pump();

        fixtureCursorBloc.add(WaveformModuleOnTap(markerTime));
        await fixtureCursorBloc.stream.firstWhere(
          (state) => state.timePs == markerTime,
        );
        fixtureSignalBloc.add(SignalFocusEvent(monitoredWaveform));
        await fixtureSignalBloc.stream.firstWhere(
          (state) => state.focusedSignalIds.isNotEmpty,
        );
        await tester.pump();

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();

        expect(fixtureCursorBloc.state.timePs, expectedTime);
      },
    );

    testWidgets(
      'inspects fixture transitions while managing viewport and markers',
      (tester) async {
        await WellenSignalWaveformApi.init();
        final api = WellenSignalWaveformApi();
        await api.loadFile('test/fixtures/xz_transitions.vcd');
        final structure = await api.getModuleStructureOnly();
        final fixtureWaveform = (await api.getWaveformData(
          signalIds: structure.allSignalIds,
        ))
            .firstWhere(
          (waveform) =>
              waveform.data.any(
                (datum) => datum.value.toLowerCase() == 'x',
              ) &&
              waveform.data.any(
                (datum) => datum.value.toLowerCase() == 'z',
              ),
        );
        final monitoredWaveform = SignalWaveform.fromWaveformData(
          fixtureWaveform,
        );
        final firstRisingIndex =
            monitoredWaveform.getNextMatchingDataPointIndex(
          -1,
          criterion: WaveformSearchCriterion.risingEdge,
        );
        final firstRisingTime = monitoredWaveform.data[firstRisingIndex].time;
        final nextTime = monitoredWaveform
            .data[monitoredWaveform.getNextDataPointIndex(firstRisingTime)]
            .time;
        final fixtureRepository = SignalWaveformRepository(
          signalWaveformApi: api,
        );
        final fixtureCursorBloc = WaveformModuleBloc(
          signalWaveformRepository: fixtureRepository,
        );
        final fitNotifier = ValueNotifier(0);
        final viewportNotifier = ValueNotifier(const WaveformViewport());
        final measurementMarkerNotifier = ValueNotifier<int?>(null);
        addTearDown(fixtureCursorBloc.close);
        addTearDown(fitNotifier.dispose);
        addTearDown(viewportNotifier.dispose);
        addTearDown(measurementMarkerNotifier.dispose);

        when(() => rohdModuleBloc.state).thenReturn(Rendered(structure));
        when(() => signalBloc.state).thenReturn(
          SignalLoaded(
            const [],
            [monitoredWaveform],
            focusedSignalIds: {monitoredWaveform.id},
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MultiBlocProvider(
                providers: [
                  BlocProvider<RohdModuleBloc>.value(value: rohdModuleBloc),
                  BlocProvider<SignalBloc>.value(value: signalBloc),
                  BlocProvider<WaveformModuleBloc>.value(
                    value: fixtureCursorBloc,
                  ),
                  BlocProvider<WaveformScaleCubit>(
                    create: (_) => WaveformScaleCubit(),
                  ),
                  RepositoryProvider<SignalDataService>.value(
                    value: RepositorySignalDataService(fixtureRepository),
                  ),
                ],
                child: WaveformPanel(
                  fitNotifier: fitNotifier,
                  viewportNotifier: viewportNotifier,
                  measurementMarkerNotifier: measurementMarkerNotifier,
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        await tester.tap(
          find.byTooltip('Find value or edge in focused signals'),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.arrow_forward));
        await tester.pump();
        expect(fixtureCursorBloc.state.timePs, firstRisingTime);

        await tester.tap(
          find.byTooltip('Set measurement marker at primary cursor'),
        );
        expect(measurementMarkerNotifier.value, firstRisingTime);
        await tester.pump();
        await tester.tap(find.byTooltip('Clear measurement marker'));
        expect(measurementMarkerNotifier.value, isNull);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(fixtureCursorBloc.state.timePs, nextTime);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(fixtureCursorBloc.state.timePs, firstRisingTime);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        await tester.pump();
        expect(viewportNotifier.value.zoomLevel, greaterThan(1));

        fitNotifier.value++;
        await tester.pump();
        expect(viewportNotifier.value.zoomLevel, 1);

        viewportNotifier.value = const WaveformViewport(
          zoomLevel: 8,
          scrollFraction: .5,
        );
        for (var frame = 0; frame < 12; frame++) {
          await tester.pump();
        }
        expect(viewportNotifier.value.zoomLevel, 8);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(fixtureCursorBloc.state.timePs, nextTime);

        final viewportWidth = tester.getSize(find.byType(WaveformPanel)).width;
        final zoomLevel = viewportNotifier.value.zoomLevel;
        final maxScrollExtent = viewportWidth * (zoomLevel - 1);
        final primaryScrollables = find.descendant(
          of: find.byKey(const ValueKey('waveform-horizontal-scroll-view')),
          matching: find.byType(Scrollable),
        );
        final scrollOffsets = tester
            .stateList<ScrollableState>(primaryScrollables)
            .map((state) => state.position.pixels)
            .toList();
        final actualScrollOffset = scrollOffsets.first;
        final drawingWidth = viewportWidth * zoomLevel - 2 * waveformLeftOffset;
        final cursorContentX = waveformLeftOffset +
            (nextTime / structure.metadata.endTime) * drawingWidth;
        final expectedScrollOffset =
            (cursorContentX - viewportWidth / 2).clamp(0.0, maxScrollExtent);
        expect(
          actualScrollOffset,
          closeTo(expectedScrollOffset, 1),
          reason: 'primary scroll offsets: $scrollOffsets',
        );

        double primaryScrollOffset() => tester
            .stateList<ScrollableState>(primaryScrollables)
            .first
            .position
            .pixels;

        for (var i = 0; i <= monitoredWaveform.data.length; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pump();
        }
        expect(fixtureCursorBloc.state.timePs, structure.metadata.endTime);
        expect(primaryScrollOffset(), closeTo(maxScrollExtent, 1));

        for (var i = 0; i <= monitoredWaveform.data.length; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          await tester.pump();
        }
        expect(
            fixtureCursorBloc.state.timePs, monitoredWaveform.data.first.time);
        expect(primaryScrollOffset(), closeTo(0, 1));

        final waveformCenter =
            tester.getCenter(find.byType(WaveformBackground));
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.dragFrom(
          waveformCenter - const Offset(120, 0),
          const Offset(240, 0),
        );
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        await tester.pump();
        expect(viewportNotifier.value.zoomLevel, greaterThan(8));

        await tester.tap(find.byType(TimescaleWidget));
        await tester.pump();
        final tappedCursorTime = fixtureCursorBloc.state.timePs;
        expect(
            tappedCursorTime, inInclusiveRange(0, structure.metadata.endTime));

        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.tapAt(
          tester.getCenter(find.byType(WaveformBackground)),
        );
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await tester.pump();
        expect(measurementMarkerNotifier.value, isNotNull);
        expect(
          measurementMarkerNotifier.value,
          inInclusiveRange(0, structure.metadata.endTime),
        );

        await tester.tap(
          find.byTooltip('Find value or edge in focused signals'),
        );
        await tester.pump();
        await tester.tap(
          find.byType(DropdownButtonFormField<WaveformSearchCriterion>).last,
        );
        await tester.pump();
        await tester.tap(find.text('Value').last);
        await tester.pump();
        await tester.enterText(find.byType(TextField), '__no_such_value__');
        await tester.tap(find.byIcon(Icons.arrow_forward).last);
        await tester.pump();
        expect(find.text('No matching transition found'), findsOneWidget);
      },
    );

    testWidgets('pans a zoomed waveform with an unmodified mouse wheel', (
      tester,
    ) async {
      final viewportNotifier = ValueNotifier(const WaveformViewport());
      addTearDown(viewportNotifier.dispose);

      when(
        () => rohdModuleBloc.state,
      ).thenReturn(Rendered(mockModuleStructure));
      when(() => signalBloc.state).thenReturn(const SignalLoaded([], []));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiBlocProvider(
              providers: [
                BlocProvider<RohdModuleBloc>.value(value: rohdModuleBloc),
                BlocProvider<SignalBloc>.value(value: signalBloc),
                BlocProvider<WaveformModuleBloc>.value(
                  value: waveformModuleBloc,
                ),
                BlocProvider<WaveformScaleCubit>(
                  create: (_) => WaveformScaleCubit(),
                ),
                RepositoryProvider<SignalDataService>.value(
                  value: signalDataService,
                ),
              ],
              child: WaveformPanel(viewportNotifier: viewportNotifier),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      viewportNotifier.value = const WaveformViewport(zoomLevel: 2);
      await tester.pumpAndSettle();

      final waveform = find.byType(WaveformBackground);
      final waveformCenter = tester.getCenter(waveform);
      final scrollable = find.descendant(
        of: find.byKey(const ValueKey('waveform-horizontal-scroll-view')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.right,
        ),
      );
      double offset() =>
          tester.state<ScrollableState>(scrollable).position.pixels;

      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: waveformCenter,
          scrollDelta: const Offset(0, 20),
        ),
      );
      await tester.pump();
      final pannedOffset = offset();
      expect(pannedOffset, greaterThan(0));

      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: waveformCenter,
          scrollDelta: const Offset(0, -20),
        ),
      );
      await tester.pump();
      expect(offset(), lessThan(pannedOffset));
    });

    testWidgets('video mode prevents cursor placement from waveform and scale',
        (
      tester,
    ) async {
      when(
        () => rohdModuleBloc.state,
      ).thenReturn(Rendered(mockModuleStructure));
      when(() => signalBloc.state).thenReturn(SignalLoaded(signals, const []));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiBlocProvider(
              providers: [
                BlocProvider<RohdModuleBloc>.value(value: rohdModuleBloc),
                BlocProvider<SignalBloc>.value(value: signalBloc),
                BlocProvider<WaveformModuleBloc>.value(
                  value: waveformModuleBloc,
                ),
                BlocProvider<WaveformScaleCubit>(
                  create: (_) => WaveformScaleCubit(),
                ),
                RepositoryProvider<SignalDataService>.value(
                  value: signalDataService,
                ),
              ],
              child: const WaveformPanel(isVideoMode: true),
            ),
          ),
        ),
      );
      await tester.pump();

      final initialTime = waveformModuleBloc.state.timePs;
      await tester.tapAt(tester.getCenter(find.byType(WaveformBackground)));
      await tester.tap(find.byType(TimescaleWidget));
      await tester.pump();

      expect(waveformModuleBloc.state.timePs, initialTime);
    });
  });
}
