// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// embedded_wave_viewer_test.dart
// Stable embedded viewer lifecycle tests.
//
// 2026 September 29
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:dart_wellen/dart_wellen.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_wave_viewer/rohd_wave_viewer.dart';
import 'package:rohd_wave_viewer/src/modules/home/view/home.dart';
import 'package:rohd_wave_viewer/src/modules/rohd_module/bloc/rohd_module_bloc.dart';
import 'package:rohd_wave_viewer/src/ui/wave_viewer_app.dart';
import 'package:rohd_wave_viewer/testing.dart';

import '../example/main.dart' as embedding_example;

void main() {
  void useDesktopViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  testWidgets('shows an explicit empty state without a waveform API', (
    tester,
  ) async {
    useDesktopViewport(tester);
    await tester.pumpWidget(
      const EmbeddedWaveViewer(waveformApi: null),
    );

    expect(find.text('No waveform data available'), findsOneWidget);
  });

  testWidgets('creates the viewer when an API becomes available', (
    tester,
  ) async {
    useDesktopViewport(tester);
    await tester.pumpWidget(
      const MaterialApp(
        home: EmbeddedWaveViewer(waveformApi: null),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: EmbeddedWaveViewer(
          waveformApi: MockSignalWaveformApi(),
          isExtensionMode: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('No waveform data available'), findsNothing);
    expect(find.byType(EmbeddedWaveViewer), findsOneWidget);
  });

  testWidgets('embedding example populates its mock hierarchy', (
    tester,
  ) async {
    useDesktopViewport(tester);

    await embedding_example.main();
    await tester.pumpAndSettle();

    final moduleBloc = BlocProvider.of<RohdModuleBloc>(
      tester.element(find.byType(WaveFormViewerPage)),
    );
    expect(moduleBloc.state, isA<ModuleSelected>());
    expect(moduleBloc.state.moduleStructure.modules.single.name, 'Counter');
    expect(moduleBloc.state.moduleStructure.allSignalIds, isNotEmpty);
  });

  testWidgets('extension mode loads API hierarchy without an external source', (
    tester,
  ) async {
    useDesktopViewport(tester);
    await WellenSignalWaveformApi.init();
    final api = WellenSignalWaveformApi();
    await api.loadFile('test/fixtures/mock_counter.vcd');

    await tester.pumpWidget(
      EmbeddedWaveViewer(
        waveformApi: api,
        isExtensionMode: true,
      ),
    );
    await tester.pumpAndSettle();

    final moduleBloc = BlocProvider.of<RohdModuleBloc>(
      tester.element(find.byType(WaveFormViewerPage)),
    );
    expect(moduleBloc.state, isA<ModuleSelected>());
    expect(moduleBloc.state.moduleStructure.modules.single.name, 'Counter');
  });

  testWidgets('applies the host initial selected module', (
    tester,
  ) async {
    useDesktopViewport(tester);
    final api = MockSignalWaveformApi();
    final structure = await api.getModuleStructure();
    final selectedModule = structure.modules.single.children.single;

    await tester.pumpWidget(
      EmbeddedWaveViewer(
        waveformApi: api,
        externalHierarchy: BaseHierarchyAdapter.fromTree(
          structure.modules.single,
        ),
        selectedModule: selectedModule,
        isExtensionMode: true,
      ),
    );
    await tester.pumpAndSettle();

    final moduleBloc = BlocProvider.of<RohdModuleBloc>(
      tester.element(find.byType(WaveFormViewerPage)),
    );
    final state = moduleBloc.state;
    expect(state, isA<ModuleSelected>());
    expect(
        (state as ModuleSelected).singleModule.path(), selectedModule.path());
  });

  testWidgets('retains host selection when the waveform API recreates App', (
    tester,
  ) async {
    useDesktopViewport(tester);
    final structure = await MockSignalWaveformApi().getModuleStructure();
    final selectedModule = structure.modules.single.children.single;
    final hierarchy = BaseHierarchyAdapter.fromTree(structure.modules.single);

    await tester.pumpWidget(
      EmbeddedWaveViewer(
        waveformApi: MockSignalWaveformApi(),
        externalHierarchy: hierarchy,
        selectedModule: selectedModule,
        isExtensionMode: true,
      ),
    );
    await tester.pumpAndSettle();
    final firstKey = tester.widget<App>(find.byType(App)).key;
    final firstModuleBloc = BlocProvider.of<RohdModuleBloc>(
      tester.element(find.byType(WaveFormViewerPage)),
    );
    expect(
      (firstModuleBloc.state as ModuleSelected).singleModule.path(),
      selectedModule.path(),
    );

    await tester.pumpWidget(
      EmbeddedWaveViewer(
        waveformApi: MockSignalWaveformApi(),
        externalHierarchy: hierarchy,
        selectedModule: selectedModule,
        isExtensionMode: true,
      ),
    );
    await tester.pumpAndSettle();
    final secondKey = tester.widget<App>(find.byType(App)).key;
    final secondModuleBloc = BlocProvider.of<RohdModuleBloc>(
      tester.element(find.byType(WaveFormViewerPage)),
    );

    expect(secondKey, isNot(firstKey));
    final secondState = secondModuleBloc.state;
    expect(secondState, isA<ModuleSelected>());
    expect(
      (secondState as ModuleSelected).singleModule.path(),
      selectedModule.path(),
    );
  });
}
