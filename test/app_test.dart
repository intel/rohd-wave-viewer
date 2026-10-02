// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// app_test.dart
// Tests for the main App widget.
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:dart_wellen/dart_wellen.dart' hide SignalWaveform;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_wave_viewer/src/cubit/wave_viewer_theme_cubit.dart';
import 'package:rohd_wave_viewer/src/cubit/waveform_scale_cubit.dart';
import 'package:rohd_wave_viewer/src/modules/home/view/home.dart';
import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';
import 'package:rohd_wave_viewer/src/ui/wave_viewer_app.dart';
import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';
import 'package:rohd_wave_viewer/testing.dart';

import 'helpers.dart';

// Fake class for registering fallback values with mocktail
class FakeHierarchyOccurrence extends Fake implements HierarchyOccurrence {}

void useDesktopViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  // Register fallback values for mocktail's any() matcher
  setUpAll(() {
    registerFallbackValue(FakeHierarchyOccurrence());
  });

  group('App Widget Tests', () {
    late MockSignalWaveformRepository mockModuleRepository;
    late MockSignalWaveformApi mockApi;
    late ModuleStructure mockModuleStructure;

    setUp(() async {
      mockModuleRepository = MockSignalWaveformRepository();
      mockApi = MockSignalWaveformApi();

      // Get mock module structure from MockSignalWaveformApi.
      // Hierarchy comes from rohd_hierarchy, not the repository.
      mockModuleStructure = await mockApi.getModuleStructure();

      // Stub the api getter to return MockSignalWaveformApi
      when(() => mockModuleRepository.api).thenReturn(mockApi);

      // Stub cachedSignalIds to return signal IDs from the mock structure
      when(
        () => mockModuleRepository.cachedSignalIds,
      ).thenReturn(mockModuleStructure.allSignalIds);

      // Stub loadAndAppendWaveformData to return empty list
      when(
        () => mockModuleRepository.loadAndAppendWaveformData(
          signalIds: any(named: 'signalIds'),
        ),
      ).thenAnswer((_) async => <WaveformData>[]);

      // Stub selectedModule setter
      when(() => mockModuleRepository.selectedModule = any()).thenReturn(null);

      // Stub getWaveformsBySelectedModule to return empty list
      when(
        () => mockModuleRepository.getWaveformsBySelectedModule(any()),
      ).thenReturn([]);

      // Stub getSignalsBySelectedModule to return empty list
      when(
        () => mockModuleRepository.getSignalsBySelectedModule(any()),
      ).thenReturn([]);
    });

    testWidgets('App renders and builds MaterialApp', (tester) async {
      useDesktopViewport(tester);
      await tester.pumpWidget(
        App(signalWaveformRepository: mockModuleRepository),
      );

      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('App initializes with all required BlocProviders', (
      tester,
    ) async {
      useDesktopViewport(tester);
      await tester.pumpWidget(
        App(signalWaveformRepository: mockModuleRepository),
      );

      // Verify that MultiBlocProvider exists
      expect(find.byType(MultiBlocProvider), findsAtLeastNWidgets(1));

      // Verify that BlocProviders for our blocs are created
      // by checking that the app structure contains the home page
      await tester.pumpAndSettle();
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('App has correct title and theme configuration', (
      tester,
    ) async {
      useDesktopViewport(tester);
      await tester.pumpWidget(
        App(signalWaveformRepository: mockModuleRepository),
      );

      final app =
          find.byType(MaterialApp).evaluate().first.widget as MaterialApp;
      expect(app.title, 'ROHD Wave Viewer');
      expect(app.theme, isNotNull);
    });

    testWidgets('App has correct initial route', (tester) async {
      useDesktopViewport(tester);
      await tester.pumpWidget(
        App(signalWaveformRepository: mockModuleRepository),
      );

      final app =
          find.byType(MaterialApp).evaluate().first.widget as MaterialApp;
      expect(app.initialRoute, '/');
      expect(app.routes, isNotEmpty);
      expect(app.routes?.containsKey('/'), true);
    });

    testWidgets(
      'restores fixture signals and appends incoming cross-probed signals',
      (tester) async {
        useDesktopViewport(tester);
        await WellenSignalWaveformApi.init();
        final api = WellenSignalWaveformApi();
        await api.loadFile('test/fixtures/xz_transitions.vcd');
        final structure = await api.getModuleStructureOnly();
        final root = structure.modules.single;
        final signalIds = structure.allSignalIds;
        final initialSignalId = signalIds.firstWhere(
          (signalId) => signalId.endsWith('bin_xz'),
        );
        final incomingSignalId = signalIds.firstWhere(
          (signalId) => signalId != initialSignalId,
        );
        final repository = SignalWaveformRepository(signalWaveformApi: api);
        final incomingSignalPaths = ValueNotifier<List<String>?>(null);
        final persistedMonitorPaths = <List<String>>[];
        addTearDown(incomingSignalPaths.dispose);

        await tester.pumpWidget(
          App(
            signalWaveformRepository: repository,
            externalHierarchy: BaseHierarchyAdapter.fromTree(root),
            initialMonitoredSignalPaths: [initialSignalId],
            incomingSignalPaths: incomingSignalPaths,
            onMonitoredSignalsChanged: persistedMonitorPaths.add,
          ),
        );
        await tester.pumpAndSettle();

        final signalBloc = BlocProvider.of<SignalBloc>(
          tester.element(find.byType(WaveFormViewerPage)),
        );
        expect(signalBloc.state, isA<SignalLoaded>());
        expect(signalBloc.state.monitorSignalsList, hasLength(1));
        expect(
          signalBloc.state.monitorSignalsList.single.signalId,
          initialSignalId,
        );
        expect(signalBloc.state.monitorSignalsList.single.data, isNotEmpty);
        expect(persistedMonitorPaths.last, [initialSignalId]);

        incomingSignalPaths.value = [incomingSignalId];
        await tester.pumpAndSettle();

        expect(signalBloc.state.monitorSignalsList, hasLength(2));
        expect(
          signalBloc.state.monitorSignalsList
              .map((waveform) => waveform.signalId),
          [initialSignalId, incomingSignalId],
        );
        expect(
          signalBloc.state.monitorSignalsList.every(
            (waveform) => waveform.data.isNotEmpty,
          ),
          isTrue,
        );
        expect(persistedMonitorPaths.last, [initialSignalId, incomingSignalId]);

        final pageContext = tester.element(find.byType(WaveFormViewerPage));
        final scaleCubit = BlocProvider.of<WaveformScaleCubit>(pageContext);
        final themeCubit = BlocProvider.of<WaveViewerThemeCubit>(pageContext);

        await tester.tap(find.byTooltip('Show internal signals'));
        await tester.pump();
        expect(signalBloc.state.showInternalSignals, isTrue);

        await tester.tap(find.byTooltip('Increase row height (100%)'));
        await tester.pump();
        expect(scaleCubit.state, 1.1);

        await tester.tap(find.byTooltip('Switch to light theme'));
        await tester.pump();
        expect(themeCubit.state, WaveViewerThemeMode.light);

        signalBloc.add(
          SignalRemoveEvent(signalBloc.state.monitorSignalsList.first),
        );
        await tester.pump();
        expect(
          signalBloc.state.monitorSignalsList
              .map((waveform) => waveform.signalId),
          [incomingSignalId],
        );

        await tester.tap(find.byTooltip('Undo monitor list edit'));
        await tester.pump();
        expect(
          signalBloc.state.monitorSignalsList
              .map((waveform) => waveform.signalId),
          [initialSignalId, incomingSignalId],
        );

        await tester.tap(find.byTooltip('Redo monitor list edit'));
        await tester.pump();
        expect(
          signalBloc.state.monitorSignalsList
              .map((waveform) => waveform.signalId),
          [incomingSignalId],
        );
      },
    );

    testWidgets(
      'appends a cross-probed child output from FilterBank FST',
      (tester) async {
        useDesktopViewport(tester);
        await WellenSignalWaveformApi.init();
        final api = WellenSignalWaveformApi();
        await api.loadFile(
          'packages/dart_wellen/test/fixtures/filter_bank.fst',
        );
        final structure = await api.getModuleStructureOnly();
        const signalPath = 'FilterBank/ch0/dataOut';
        expect(structure.allSignalIds, contains(signalPath));

        final repository = SignalWaveformRepository(signalWaveformApi: api);
        final incomingSignalPaths = ValueNotifier<List<String>?>(null);
        addTearDown(incomingSignalPaths.dispose);

        await tester.pumpWidget(
          App(
            signalWaveformRepository: repository,
            externalHierarchy: BaseHierarchyAdapter.fromTree(
              structure.modules.single,
            ),
            incomingSignalPaths: incomingSignalPaths,
          ),
        );
        await tester.pumpAndSettle();

        incomingSignalPaths.value = const [
          'FilterBank/internalSignalWithoutWaveform',
          signalPath,
        ];
        await tester.pumpAndSettle();

        final signalBloc = BlocProvider.of<SignalBloc>(
          tester.element(find.byType(WaveFormViewerPage)),
        );
        expect(signalBloc.state.monitorSignalsList, hasLength(1));
        final waveform = signalBloc.state.monitorSignalsList.single;
        expect(waveform.signalId, signalPath);
        expect(waveform.data, isNotEmpty);

        incomingSignalPaths.value = const ['waveformTop.ch0.dataOut'];
        await tester.pumpAndSettle();

        expect(signalBloc.state.monitorSignalsList, hasLength(2));
        expect(signalBloc.state.monitorSignalsList.last.signalId, signalPath);
        expect(signalBloc.state.monitorSignalsList.last.data, isNotEmpty);
      },
    );
  });
}
