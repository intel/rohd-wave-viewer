// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// waveform_background_test.dart
// Tests for the waveform background widget.
//
// 2024 April
// Author(s): Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
//            Yao Jing Quek <yao.jing.quek@intel.com>

import 'dart:ui' as ui;

import 'package:dart_wellen/dart_wellen.dart' hide SignalWaveform;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rohd_wave_viewer/src/const/const.dart';
import 'package:rohd_wave_viewer/src/cubit/waveform_scale_cubit.dart';
import 'package:rohd_wave_viewer/src/modules/rohd_module/bloc/rohd_module_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/bloc/waveform_module_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/view/widgets/painters/waveform.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/view/widgets/painters/waveform_binary.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/view/widgets/painters/waveform_hexavalue.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/view/widgets/waveform_background.dart';
import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';
import 'package:rohd_wave_viewer/testing.dart';

import '../../../../helpers.dart';

void main() {
  late RohdModuleBloc rohdModuleBloc;
  late WaveformModuleBloc waveformModuleBloc;
  late SignalBloc signalBloc;

  late ModuleStructure mockModuleStructure;
  late HierarchyOccurrence selectedModule;
  late MockSignalWaveformApi signalWaveformApi;
  late SignalWaveformRepository signalWaveformRepository;
  late List<SignalOccurrence> signals;
  late List<SignalWaveform> monitoredSignals;

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
    final waveforms = signalWaveformRepository.getWaveformsBySelectedModule(
      selectedModule,
    );
    monitoredSignals = waveforms.take(3).toList();
    waveformModuleBloc = WaveformModuleBloc(
      signalWaveformRepository: signalWaveformRepository,
    );
  });

  group('Waveform Background', () {
    test('caches waveform labels separately for each value font', () {
      addTearDown(Waveform.clearCaches);

      final robotoMonoLabel = Waveform.getCachedLabel(
        "8'h5a",
        18,
        Colors.white,
      );
      final sourceCodeProLabel = Waveform.getCachedLabel(
        "8'h5a",
        18,
        Colors.white,
        valueFont: ValueFont.sourceCodePro,
      );
      final robotoMonoSpan = robotoMonoLabel.text! as TextSpan;
      final sourceCodeProSpan = sourceCodeProLabel.text! as TextSpan;

      expect(
        robotoMonoSpan.style?.fontFamily,
        'packages/devtools_app_shared/RobotoMono',
      );
      expect(sourceCodeProSpan.style?.fontFamily, 'SourceCodePro');
      expect(sourceCodeProLabel, isNot(same(robotoMonoLabel)));
    });

    test('formats waveform labels using the selected row format', () {
      const sourceValue = "8'hff";

      expect(
        Waveform.formatValueForDisplay(
          sourceValue,
          MonitorValueFormat.waveform,
          8,
        ),
        "8'hff",
      );
      expect(
        Waveform.formatValueForDisplay(
          sourceValue,
          MonitorValueFormat.hexadecimal,
          8,
        ),
        "8'hff",
      );
      expect(
        Waveform.formatValueForDisplay(
          '0x0',
          MonitorValueFormat.unsignedDecimal,
          4,
        ),
        '0',
      );

      expect(
        Waveform.formatValueForDisplay(
          sourceValue,
          MonitorValueFormat.binary,
          8,
        ),
        '11111111',
      );
      expect(
        Waveform.formatValueForDisplay(
          sourceValue,
          MonitorValueFormat.signedDecimal,
          8,
        ),
        '-1',
      );
      expect(
        Waveform.formatValueForDisplay(
          sourceValue,
          MonitorValueFormat.octal,
          8,
        ),
        '0o377',
      );
      expect(
        Waveform.formatValueForDisplay(
          "8'h41",
          MonitorValueFormat.ascii,
          8,
        ),
        'A',
      );
    });

    testWidgets(
        'Waveform Background expect to see CustomPaint when there are '
        'monitored signals.', (tester) async {
      when(
        () => rohdModuleBloc.state,
      ).thenReturn(Rendered(mockModuleStructure));

      when(
        () => signalBloc.state,
      ).thenReturn(SignalLoaded(signals, monitoredSignals));

      await tester.pumpApp(
        rohdModuleBloc: rohdModuleBloc,
        signalBloc: signalBloc,
        waveformModuleBloc: waveformModuleBloc,
        child: WaveformBackground(
          timescale: 20,
          zoomLevel: 1,
          horizontalScrollController: ScrollController(),
          screenWidth: 800,
        ),
      );

      // WaveformBackground renders waveforms using CustomPaint widgets. When
      // there are monitored signals, we expect to see CustomPaint widgets.
      expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
    });

    testWidgets(
      'renders and reuses real fixture waveforms across scroll and resize',
      (tester) async {
        await WellenSignalWaveformApi.init();
        final api = WellenSignalWaveformApi();
        await api.loadFile('test/fixtures/xz_transitions.vcd');
        final structure = await api.getModuleStructureOnly();
        final fixtureRepository = SignalWaveformRepository(
          signalWaveformApi: api,
        );
        final fixtureWaveforms = (await api.getWaveformData(
          signalIds: structure.allSignalIds,
        ))
            .map(SignalWaveform.fromWaveformData)
            .toList();
        final fixtureCursorBloc = WaveformModuleBloc(
          signalWaveformRepository: fixtureRepository,
        );
        final horizontalScrollController = ScrollController();
        final verticalScrollController = ScrollController();
        addTearDown(fixtureCursorBloc.close);
        addTearDown(horizontalScrollController.dispose);
        addTearDown(verticalScrollController.dispose);

        when(() => rohdModuleBloc.state).thenReturn(Rendered(structure));
        when(() => signalBloc.state).thenReturn(
          SignalLoaded(const [], fixtureWaveforms),
        );

        Widget buildBackground({
          required double zoomLevel,
          required double screenWidth,
        }) =>
            WaveformBackground(
              timescale: structure.metadata.endTime,
              zoomLevel: zoomLevel,
              horizontalScrollController: horizontalScrollController,
              verticalScrollController: verticalScrollController,
              screenWidth: screenWidth,
            );

        await tester.pumpApp(
          rohdModuleBloc: rohdModuleBloc,
          signalBloc: signalBloc,
          waveformModuleBloc: fixtureCursorBloc,
          child: buildBackground(zoomLevel: 1, screenWidth: 800),
        );
        await tester.pump();
        expect(find.byType(CustomPaint), findsAtLeastNWidgets(2));

        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox(
              height: 120,
              child: MultiBlocProvider(
                providers: [
                  BlocProvider<RohdModuleBloc>.value(value: rohdModuleBloc),
                  BlocProvider<SignalBloc>.value(value: signalBloc),
                  BlocProvider<WaveformModuleBloc>.value(
                    value: fixtureCursorBloc,
                  ),
                  BlocProvider<WaveformScaleCubit>(
                    create: (_) => WaveformScaleCubit(),
                  ),
                ],
                child: buildBackground(zoomLevel: 4, screenWidth: 800),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(CustomPaint), findsAtLeastNWidgets(2));

        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox(
              height: 120,
              child: MultiBlocProvider(
                providers: [
                  BlocProvider<RohdModuleBloc>.value(value: rohdModuleBloc),
                  BlocProvider<SignalBloc>.value(value: signalBloc),
                  BlocProvider<WaveformModuleBloc>.value(
                    value: fixtureCursorBloc,
                  ),
                  BlocProvider<WaveformScaleCubit>(
                    create: (_) => WaveformScaleCubit(),
                  ),
                ],
                child: buildBackground(zoomLevel: 4, screenWidth: 700),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byType(CustomPaint), findsAtLeastNWidgets(2));
      },
    );

    test('paints parsed scalar and bus X/Z transitions', () async {
      await WellenSignalWaveformApi.init();
      final api = WellenSignalWaveformApi();
      await api.loadFile('test/fixtures/xz_transitions.vcd');
      final structure = await api.getModuleStructureOnly();
      final waveforms = await api.getWaveformData(
        signalIds: structure.allSignalIds,
      );
      final endTime = structure.metadata.endTime;

      final scalar = waveforms.firstWhere(
        (waveform) =>
            waveform.data.any(
              (datum) => datum.value.toLowerCase() == 'x',
            ) &&
            waveform.data.any(
              (datum) => datum.value.toLowerCase() == 'z',
            ),
      );
      final bus = waveforms.firstWhere(
        (waveform) =>
            waveform.data.any(
              (datum) => datum.value.toLowerCase().contains('x'),
            ) &&
            waveform.data.any(
              (datum) => datum.value.toLowerCase().contains('z'),
            ) &&
            waveform.data.any((datum) => datum.value.length > 1),
      );

      final binaryPainter = WaveformBinary(
        scalar.data,
        endTime,
        0,
        signalWidth: 1,
        timescale: endTime,
      );
      final busPainter = WaveformHexaValue(
        bus.data,
        endTime,
        0,
        signalWidth: 8,
        timescale: endTime,
      );

      for (final painter in [binaryPainter, busPainter]) {
        await expectPaintedOutput(painter);
        await expectPaintedOutput(painter);
      }

      final denseBinaryPainter = WaveformBinary(
        scalar.data,
        endTime,
        0,
        signalWidth: 1,
        timescale: endTime,
      );
      final detailedBusPainter = WaveformHexaValue(
        bus.data,
        endTime,
        0,
        signalWidth: 8,
        timescale: endTime,
      );
      final pausedBusPainter = WaveformHexaValue(
        bus.data,
        endTime,
        0,
        signalWidth: 8,
        timescale: endTime,
        dataEndTime: endTime ~/ 2,
      );

      await expectPaintedOutput(
        denseBinaryPainter,
        const Size(32, 24),
      );
      await expectPaintedOutput(
        detailedBusPainter,
        const Size(1600, 24),
      );
      await expectPaintedOutput(
        pausedBusPainter,
      );
    });

    test('paints scalar radix encodings, unknowns, and dense transitions',
        () async {
      final scalarValues = [
        '0',
        '1',
        '0x0',
        '0x1',
        '0b0',
        '0b1',
        "1'b0",
        "1'b1",
        "1'h0",
        "1'h1",
        'x',
        'z',
      ];
      final scalarData = [
        for (final (index, value) in scalarValues.indexed)
          Data(time: index * 10, value: value),
      ];
      final scalarPainter = WaveformBinary(
        scalarData,
        120,
        0,
        timescale: 120,
        useBezierCrossings: true,
      );

      expect(
          scalarPainter.gapExtensionYPositions('0', const Size(100, 24)), [24]);
      expect(
          scalarPainter.gapExtensionYPositions('1', const Size(100, 24)), [0]);
      expect(scalarPainter.gapExtensionYPositions('x', const Size(100, 24)),
          [0, 24]);
      await expectPaintedOutput(scalarPainter, const Size(1200, 24));
      await expectPaintedOutput(scalarPainter, const Size(1200, 24));

      final denseData = [
        for (var index = 0; index < 200; index++)
          Data(time: index, value: index.isEven ? '0' : '1'),
      ];
      await expectPaintedOutput(
        WaveformBinary(
          denseData,
          200,
          0,
          timescale: 200,
          viewportWidth: 24,
          scrollOffset: 80,
        ),
        const Size(48, 24),
      );
    });

    test('paints inferred bus encodings in scrolled and paused viewports',
        () async {
      final busValues = [
        '00',
        '11',
        'b0011',
        '0b1010',
        '0x0f',
        "8'b1010_0101",
        "8'hfe",
        'xx',
        'zz',
        '15',
      ];
      final busData = [
        for (final (index, value) in busValues.indexed)
          Data(time: index * 20, value: value),
      ];

      for (final painter in [
        WaveformBinary(
          busData,
          200,
          0,
          timescale: 200,
          valueFormat: MonitorValueFormat.binary,
        ),
        WaveformBinary(
          busData,
          200,
          0,
          timescale: 200,
          valueFormat: MonitorValueFormat.unsignedDecimal,
          viewportWidth: 120,
          scrollOffset: 40,
          dataEndTime: 150,
          useBezierCrossings: true,
        ),
      ]) {
        painter.collectLabelsForViewport(800, 24);
        await expectPaintedOutput(painter);
        await expectPaintedOutput(painter);
      }
    });
  });
}

Future<void> expectPaintedOutput(
  CustomPainter painter, [
  Size size = const Size(800, 24),
]) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  painter.paint(canvas, size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  final bytes = await image.toByteData();

  expect(bytes, isNotNull);
  expect(bytes!.buffer.asUint8List().any((byte) => byte != 0), isTrue);

  image.dispose();
  picture.dispose();
}
