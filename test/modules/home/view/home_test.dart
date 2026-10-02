// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// home_test.dart
// Usage-based widget tests for the wave viewer home page.
//
// 2026 August
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_wellen/dart_wellen.dart' hide SignalWaveform;
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryMouseButton;
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_wave_viewer/src/cubit/wave_viewer_theme_cubit.dart';
import 'package:rohd_wave_viewer/src/cubit/waveform_scale_cubit.dart';
import 'package:rohd_wave_viewer/src/modules/hierarchy/hierarchy_overlay.dart';
import 'package:rohd_wave_viewer/src/modules/home/view/home.dart';
import 'package:rohd_wave_viewer/src/modules/rohd_module/bloc/rohd_module_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/shared/widgets/widgets.dart';
import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/bloc/waveform_module_bloc.dart';
import 'package:rohd_wave_viewer/src/ui/wave_viewer_app.dart';
import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';
import 'package:rohd_wave_viewer/testing.dart';

/// Mock handler for the `file_selector` platform channel so open/save dialogs
/// can be driven from tests without touching the host UI.
class _FakeFileDialogs {
  static const _channel = MethodChannel('plugins.flutter.io/file_selector');

  /// Path returned by the next `openFile` dialog (`null` cancels).
  String? openPath;

  /// Path returned by the next `getSavePath` dialog (`null` cancels).
  String? savePath;

  /// When true, the open dialog fails instead of returning a path.
  bool failOpen = false;

  /// Number of open dialogs shown.
  int openCount = 0;

  void install(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (
      call,
    ) async {
      switch (call.method) {
        case 'openFile':
          openCount++;
          if (failOpen) {
            throw PlatformException(code: 'dialog-failed');
          }
          return openPath == null ? null : <String>[openPath!];
        case 'getSavePath':
          return savePath;
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null),
    );
  }
}

/// Scriptable [RohdExtensionClient] used to exercise the extension handshake.
class _FakeExtensionClient implements RohdExtensionClient {
  @override
  final isAvailable = ValueNotifier<bool>(true);

  @override
  final currentModuleInfo = ValueNotifier<RohdModuleInfo?>(null);

  int pingCount = 0;
  final queriedModules = <String>[];
  final queriedInstancePaths = <List<String>?>[];
  bool disposed = false;

  /// Info published on every [queryModule] call.
  RohdModuleInfo response = const RohdModuleInfo(extensionAvailable: true);

  @override
  Future<bool> ping() async {
    pingCount++;
    return true;
  }

  @override
  Future<RohdModuleInfo> queryModule(
    String module, {
    List<String>? instancePath,
  }) async {
    queriedModules.add(module);
    queriedInstancePaths.add(instancePath);
    currentModuleInfo.value = response;
    return response;
  }

  @override
  Future<List<Map<String, dynamic>>> lookupSignalFrames({
    required List<Map<String, String>> signals,
    String? format,
  }) async =>
      const [];

  @override
  void openSourceLocation({
    required String file,
    required int line,
    int col = 0,
  }) {}

  @override
  void dispose() {
    disposed = true;
    isAvailable.dispose();
    currentModuleInfo.dispose();
  }
}

/// A loaded fixture waveform plus the repository wired to it.
class _Fixture {
  _Fixture({
    required this.repository,
    required this.hierarchy,
    required this.signalIds,
  });

  final SignalWaveformRepository repository;
  final HierarchyService hierarchy;
  final List<String> signalIds;
}

Future<_Fixture> _loadFixture(String path) async {
  await WellenSignalWaveformApi.init();
  final api = WellenSignalWaveformApi();
  await api.loadFile(path);
  final structure = await api.getModuleStructureOnly();
  return _Fixture(
    repository: SignalWaveformRepository(signalWaveformApi: api),
    hierarchy: BaseHierarchyAdapter.fromTree(structure.modules.single),
    signalIds: structure.allSignalIds,
  );
}

/// An empty (no waveform loaded) repository backed by a real Wellen API.
Future<SignalWaveformRepository> _emptyRepository() async {
  await WellenSignalWaveformApi.init();
  return SignalWaveformRepository(signalWaveformApi: WellenSignalWaveformApi());
}

void _useDesktopViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

SignalBloc _signalBloc(WidgetTester tester) => BlocProvider.of<SignalBloc>(
      tester.element(find.byType(WaveFormViewerPage)),
    );

/// Pumps frames while also letting real (non-faked) file and waveform I/O
/// complete, which the viewer performs while loading and saving files.
Future<void> _settleWithFileIo(
  WidgetTester tester, {
  bool Function()? until,
}) async {
  final iterations = until == null ? 12 : 500;
  for (var i = 0; i < iterations; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (until?.call() ?? false) {
      break;
    }
  }
  if (until != null && !until()) {
    throw TestFailure('File operation did not complete within 10 seconds.');
  }
  await tester.pumpAndSettle();
}

/// Moves a mouse pointer to [location] so hover-triggered overlays appear.
Future<void> _hoverAt(WidgetTester tester, Offset location) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await mouse.moveTo(location);
  await tester.pumpAndSettle();
}

/// Directory for files written by these tests (kept inside the project).
final Directory _scratchDir = Directory('build/home_test_scratch');

String _scratchPath(String name) => '${_scratchDir.path}/$name';

/// PNG exports currently sitting in the working directory, where the native
/// snapshot helper writes them.
Set<String> _pngExports() => Directory.current
    .listSync()
    .whereType<File>()
    .map((f) => f.path)
    .where((p) => RegExp(r'waveform_\d+\.png$').hasMatch(p))
    .toSet();

void main() {
  setUpAll(() {
    if (!_scratchDir.existsSync()) {
      _scratchDir.createSync(recursive: true);
    }
  });

  tearDownAll(() {
    if (_scratchDir.existsSync()) {
      _scratchDir.deleteSync(recursive: true);
    }
  });

  group('standalone file workflows', () {
    testWidgets('loads a waveform from the file picker and reloads it', (
      tester,
    ) async {
      _useDesktopViewport(tester);
      final dialogs = _FakeFileDialogs()..install(tester);
      final repository = await _emptyRepository();

      await tester.pumpWidget(App(signalWaveformRepository: repository));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byTooltip('Load waveform file'),
          matching: find.byType(WaveformFileOpenIcon),
        ),
        findsOneWidget,
      );

      // No file loaded yet: reload is disabled and no file name is shown.
      expect(find.textContaining('- mock_counter.vcd'), findsNothing);
      final reloadButton = tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip('Reload waveform'),
          matching: find.byType(IconButton),
        ),
      );
      expect(reloadButton.onPressed, isNull);

      dialogs.openPath = 'test/fixtures/mock_counter.vcd';
      await tester.tap(find.byTooltip('Load waveform file'));
      await _settleWithFileIo(
        tester,
        until: () => find.text('- mock_counter.vcd').evaluate().isNotEmpty,
      );

      expect(dialogs.openCount, 1);
      expect(find.text('- mock_counter.vcd'), findsOneWidget);

      final moduleBloc = BlocProvider.of<RohdModuleBloc>(
        tester.element(find.byType(WaveFormViewerPage)),
      );
      expect(moduleBloc.state.moduleStructure.modules, isNotEmpty);
      expect(_signalBloc(tester).state.signals, isNotEmpty);

      // The file is now reloadable from its on-disk path.
      await tester.tap(find.byTooltip('Reload waveform'));
      await _settleWithFileIo(tester);

      expect(find.textContaining('Error refreshing file'), findsNothing);
      expect(find.text('- mock_counter.vcd'), findsOneWidget);
      expect(moduleBloc.state.moduleStructure.modules, isNotEmpty);
    });

    testWidgets('rejects a malformed replacement without losing the session', (
      tester,
    ) async {
      _useDesktopViewport(tester);
      final dialogs = _FakeFileDialogs()..install(tester);
      final repository = await _emptyRepository();
      final malformedPath = _scratchPath('malformed.vcd');
      File(malformedPath).writeAsStringSync('not a waveform');

      await tester.pumpWidget(App(signalWaveformRepository: repository));
      await tester.pumpAndSettle();

      dialogs.openPath = 'test/fixtures/mock_counter.vcd';
      await tester.tap(find.byTooltip('Load waveform file'));
      await _settleWithFileIo(
        tester,
        until: () => find.text('- mock_counter.vcd').evaluate().isNotEmpty,
      );

      final pageContext = tester.element(find.byType(WaveFormViewerPage));
      final moduleBloc = BlocProvider.of<RohdModuleBloc>(pageContext);
      final signalBloc = BlocProvider.of<SignalBloc>(pageContext);
      final previousApi = repository.api;
      final previousStructure = moduleBloc.state.moduleStructure;
      final monitoredPath = previousStructure.allSignalIds.first;
      signalBloc.add(SignalRestoreMonitoredEvent([monitoredPath]));
      await _settleWithFileIo(
        tester,
        until: () => signalBloc.state.monitorSignalsList.isNotEmpty,
      );

      dialogs.openPath = malformedPath;
      await tester.tap(find.byTooltip('Load waveform file'));
      await _settleWithFileIo(
        tester,
        until: () =>
            find.textContaining('Error loading file').evaluate().isNotEmpty,
      );

      expect(find.text('- mock_counter.vcd'), findsOneWidget);
      expect(find.text('- malformed.vcd'), findsNothing);
      expect(repository.api, same(previousApi));
      expect(moduleBloc.state.moduleStructure, same(previousStructure));
      expect(
        signalBloc.state.monitorSignalsList.map((waveform) => waveform.id),
        [monitoredPath],
      );
    });

    testWidgets('reloads a changed hierarchy and removes missing monitors', (
      tester,
    ) async {
      _useDesktopViewport(tester);
      final dialogs = _FakeFileDialogs()..install(tester);
      final repository = await _emptyRepository();
      final reloadPath = _scratchPath('changing.vcd');
      File('test/fixtures/mock_counter.vcd').copySync(reloadPath);

      await tester.pumpWidget(App(signalWaveformRepository: repository));
      await tester.pumpAndSettle();

      dialogs.openPath = reloadPath;
      await tester.tap(find.byTooltip('Load waveform file'));
      await _settleWithFileIo(
        tester,
        until: () => find.text('- changing.vcd').evaluate().isNotEmpty,
      );

      final pageContext = tester.element(find.byType(WaveFormViewerPage));
      final moduleBloc = BlocProvider.of<RohdModuleBloc>(pageContext);
      final signalBloc = BlocProvider.of<SignalBloc>(pageContext);
      expect(moduleBloc.state.moduleStructure.modules.single.name, 'Counter');

      final monitoredPath = moduleBloc.state.moduleStructure.allSignalIds.first;
      signalBloc.add(SignalRestoreMonitoredEvent([monitoredPath]));
      await _settleWithFileIo(
        tester,
        until: () => signalBloc.state.monitorSignalsList.isNotEmpty,
      );

      File('test/fixtures/xz_transitions.vcd').copySync(reloadPath);
      await tester.tap(find.byTooltip('Reload waveform'));
      await _settleWithFileIo(
        tester,
        until: () =>
            moduleBloc.state.moduleStructure.modules.single.name == 'test',
      );

      expect(find.text('- changing.vcd'), findsOneWidget);
      expect(moduleBloc.state.moduleStructure.modules.single.name, 'test');
      expect(signalBloc.state.signals, isNotEmpty);
      expect(
        signalBloc.state.signals.map((signal) => signal.path()).toSet(),
        moduleBloc.state.moduleStructure.allSignalIds.toSet(),
      );
      expect(signalBloc.state.monitorSignalsList, isEmpty);
    });

    testWidgets('shows an error when the waveform file cannot be picked', (
      tester,
    ) async {
      _useDesktopViewport(tester);
      _FakeFileDialogs()
        ..failOpen = true
        ..install(tester);
      final repository = await _emptyRepository();

      await tester.pumpWidget(App(signalWaveformRepository: repository));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Load waveform file'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('Error loading file'), findsOneWidget);
    });

    testWidgets('keeps the app unchanged when the picker is cancelled', (
      tester,
    ) async {
      _useDesktopViewport(tester);
      final dialogs = _FakeFileDialogs()..install(tester);
      final repository = await _emptyRepository();

      await tester.pumpWidget(App(signalWaveformRepository: repository));
      await tester.pumpAndSettle();

      dialogs.openPath = null;
      await tester.tap(find.byTooltip('Load waveform file'));
      await _settleWithFileIo(tester);

      expect(dialogs.openCount, 1);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('loads a waveform when the repository uses another API', (
      tester,
    ) async {
      _useDesktopViewport(tester);
      final dialogs = _FakeFileDialogs()..install(tester);
      final repository = SignalWaveformRepository(
        signalWaveformApi: MockSignalWaveformApi(),
      );
      await WellenSignalWaveformApi.init();

      await tester.pumpWidget(App(signalWaveformRepository: repository));
      await tester.pumpAndSettle();

      dialogs.openPath = 'test/fixtures/mock_counter.vcd';
      await tester.tap(find.byTooltip('Load waveform file'));
      await _settleWithFileIo(tester);

      expect(find.text('- mock_counter.vcd'), findsOneWidget);
      expect(repository.api, isA<WellenSignalWaveformApi>());
      expect(
        BlocProvider.of<RohdModuleBloc>(
          tester.element(find.byType(WaveFormViewerPage)),
        ).state.moduleStructure.modules,
        isNotEmpty,
      );
    });

    testWidgets('reports an error when the reloaded file is gone', (
      tester,
    ) async {
      _useDesktopViewport(tester);
      final dialogs = _FakeFileDialogs()..install(tester);
      final repository = await _emptyRepository();
      final copyPath = _scratchPath('transient.vcd');
      File('test/fixtures/mock_counter.vcd').copySync(copyPath);

      await tester.pumpWidget(App(signalWaveformRepository: repository));
      await tester.pumpAndSettle();

      dialogs.openPath = copyPath;
      await tester.tap(find.byTooltip('Load waveform file'));
      await _settleWithFileIo(
        tester,
        until: () => find.text('- transient.vcd').evaluate().isNotEmpty,
      );
      expect(find.text('- transient.vcd'), findsOneWidget);

      File(copyPath).deleteSync();
      await tester.tap(find.byTooltip('Reload waveform'));
      await _settleWithFileIo(
        tester,
        until: () =>
            find.textContaining('Error refreshing file').evaluate().isNotEmpty,
      );

      expect(find.textContaining('Error refreshing file'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('exports the waveform panes as a PNG', (tester) async {
      _useDesktopViewport(tester);
      final fixture = await _loadFixture('test/fixtures/xz_transitions.vcd');

      await tester.pumpWidget(
        App(
          signalWaveformRepository: fixture.repository,
          externalHierarchy: fixture.hierarchy,
          initialMonitoredSignalPaths: [fixture.signalIds.first],
        ),
      );
      await tester.pumpAndSettle();

      final before = _pngExports();
      await tester.tap(find.byTooltip('Export waveform as PNG'));
      addTearDown(() {
        for (final path in _pngExports().difference(before)) {
          final file = File(path);
          if (file.existsSync()) {
            file.deleteSync();
          }
        }
      });
      await _settleWithFileIo(tester);

      final created = _pngExports().difference(before);
      expect(created, hasLength(1));
      expect(File(created.single).lengthSync(), greaterThan(0));
      // The export button is restored after the capture completes.
      expect(find.byTooltip('Export waveform as PNG'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('host reload streams', () {
    testWidgets('refreshes the mounted viewer after a successful host reload', (
      tester,
    ) async {
      _useDesktopViewport(tester);
      final fixture = await _loadFixture('test/fixtures/mock_counter.vcd');
      final reloads = StreamController<void>();
      addTearDown(reloads.close);

      await tester.pumpWidget(
        App(
          signalWaveformRepository: fixture.repository,
          externalHierarchy: fixture.hierarchy,
          apiReloads: reloads.stream,
        ),
      );
      await tester.pumpAndSettle();

      final moduleBloc = BlocProvider.of<RohdModuleBloc>(
        tester.element(find.byType(WaveFormViewerPage)),
      );
      expect(moduleBloc.state.moduleStructure.modules.single.name, 'Counter');

      await tester.runAsync(
        () => (fixture.repository.api as WellenSignalWaveformApi)
            .loadFile('test/fixtures/xz_transitions.vcd'),
      );
      reloads.add(null);
      await _settleWithFileIo(
        tester,
        until: () =>
            moduleBloc.state.moduleStructure.modules.single.name == 'test',
      );

      expect(moduleBloc.state.moduleStructure.modules.single.name, 'test');
      expect(find.textContaining('Error reloading waveform'), findsNothing);
    });

    testWidgets('shows host reload failures', (tester) async {
      _useDesktopViewport(tester);
      final fixture = await _loadFixture('test/fixtures/mock_counter.vcd');
      final reloadErrors = StreamController<String>();
      addTearDown(reloadErrors.close);

      await tester.pumpWidget(
        App(
          signalWaveformRepository: fixture.repository,
          externalHierarchy: fixture.hierarchy,
          apiReloadErrors: reloadErrors.stream,
        ),
      );
      await tester.pumpAndSettle();

      reloadErrors.add('invalid replacement');
      await tester.pumpAndSettle();

      expect(
        find.text('Error reloading waveform: invalid replacement'),
        findsOneWidget,
      );
    });
  });

  group('signal list save and restore', () {
    testWidgets('saves the monitored list and viewer session to JSON', (
      tester,
    ) async {
      _useDesktopViewport(tester);
      final dialogs = _FakeFileDialogs()..install(tester);
      final fixture = await _loadFixture('test/fixtures/xz_transitions.vcd');
      final savePath = _scratchPath('saved_signals.json');
      dialogs.savePath = savePath;

      await tester.pumpWidget(
        App(
          signalWaveformRepository: fixture.repository,
          externalHierarchy: fixture.hierarchy,
          initialMonitoredSignalPaths: [fixture.signalIds.first],
        ),
      );
      await tester.pumpAndSettle();

      // Change a couple of session settings so the save captures them.
      await tester.tap(find.byTooltip('Show internal signals'));
      await tester.pump();
      await tester.tap(find.byTooltip('Increase row height (100%)'));
      await tester.pump();
      await tester.tap(find.byTooltip('Switch to light theme'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Save signal list'));
      final saved = File(savePath);
      await _settleWithFileIo(tester, until: saved.existsSync);

      expect(saved.existsSync(), isTrue);
      final decoded = jsonDecode(saved.readAsStringSync()) as Map;
      final signals = decoded['signals'] as List;
      expect(signals, hasLength(1));
      final session = decoded['session'] as Map;
      expect(session['showInternalSignals'], isTrue);
      expect(session['rowScale'], closeTo(1.1, 1e-9));
      expect(session['themeMode'], 'light');
      expect(session['hierarchyPinned'], isTrue);
      expect(session['appBarPinned'], isTrue);
    });

    testWidgets('warns when there are no signals to save', (tester) async {
      _useDesktopViewport(tester);
      _FakeFileDialogs().install(tester);
      final repository = await _emptyRepository();

      await tester.pumpWidget(App(signalWaveformRepository: repository));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Save signal list'));
      await tester.pump();

      expect(find.text('No signals to save'), findsOneWidget);
    });

    testWidgets('restores signals and session state from a signal list file', (
      tester,
    ) async {
      _useDesktopViewport(tester);
      final dialogs = _FakeFileDialogs()..install(tester);
      final fixture = await _loadFixture('test/fixtures/xz_transitions.vcd');
      final restored = fixture.signalIds.take(2).toList();

      final listPath = _scratchPath('restore_signals.json');
      File(listPath).writeAsStringSync(
        jsonEncode({
          'version': 3,
          'signals': [
            for (final id in restored) {'id': id},
          ],
          'session': {
            'showInternalSignals': true,
            'filterText': 'bin',
            'cursorTimePs': 20,
            'measurementMarkerTimePs': 30,
            'rowScale': 1.3,
            'themeMode': 'light',
            'hierarchyPinned': false,
            'appBarPinned': false,
            'pinnedPanelWidth': 320.0,
            'viewport': {'zoomLevel': 2.0, 'scrollFraction': 0.25},
          },
        }),
      );
      dialogs.openPath = listPath;

      await tester.pumpWidget(
        App(
          signalWaveformRepository: fixture.repository,
          externalHierarchy: fixture.hierarchy,
        ),
      );
      await tester.pumpAndSettle();

      expect(_signalBloc(tester).state.monitorSignalsList, isEmpty);

      await tester.tap(find.byTooltip('Load signal list'));
      await _settleWithFileIo(tester);

      final pageContext = tester.element(find.byType(WaveFormViewerPage));
      final signalBloc = _signalBloc(tester);
      expect(
        signalBloc.state.monitorSignalsList.map((w) => w.signalId),
        restored,
      );
      expect(signalBloc.state.showInternalSignals, isTrue);
      expect(signalBloc.state.filterText, 'bin');
      expect(
        BlocProvider.of<WaveformScaleCubit>(pageContext).state,
        closeTo(1.3, 1e-9),
      );
      expect(
        BlocProvider.of<WaveViewerThemeCubit>(pageContext).state,
        WaveViewerThemeMode.light,
      );
      expect(
        BlocProvider.of<WaveformModuleBloc>(pageContext).state.timePs,
        20,
      );
      expect(find.text('Appended 2 signals'), findsOneWidget);
    });

    testWidgets('reports when a signal list matches no current signals', (
      tester,
    ) async {
      _useDesktopViewport(tester);
      final dialogs = _FakeFileDialogs()..install(tester);
      final fixture = await _loadFixture('test/fixtures/xz_transitions.vcd');

      final listPath = _scratchPath('unmatched_signals.json');
      File(listPath).writeAsStringSync(
        jsonEncode({
          'version': 3,
          'signals': [
            {'id': 'nonexistent.module.signal'},
          ],
        }),
      );
      dialogs.openPath = listPath;

      await tester.pumpWidget(
        App(
          signalWaveformRepository: fixture.repository,
          externalHierarchy: fixture.hierarchy,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Load signal list'));
      await _settleWithFileIo(
        tester,
        until: () => find
            .text('No matching signals found in current hierarchy')
            .evaluate()
            .isNotEmpty,
      );

      expect(
        find.text('No matching signals found in current hierarchy'),
        findsOneWidget,
      );
      expect(_signalBloc(tester).state.monitorSignalsList, isEmpty);
    });

    testWidgets('reports an error for an unreadable signal list', (
      tester,
    ) async {
      _useDesktopViewport(tester);
      final dialogs = _FakeFileDialogs()..install(tester);
      final fixture = await _loadFixture('test/fixtures/xz_transitions.vcd');

      final listPath = _scratchPath('broken_signals.json');
      File(listPath).writeAsStringSync('{not json');
      dialogs.openPath = listPath;

      await tester.pumpWidget(
        App(
          signalWaveformRepository: fixture.repository,
          externalHierarchy: fixture.hierarchy,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Load signal list'));
      await _settleWithFileIo(
        tester,
        until: () => find
            .textContaining('Error loading signal list')
            .evaluate()
            .isNotEmpty,
      );

      expect(find.textContaining('Error loading signal list'), findsOneWidget);
    });

    testWidgets('reports how many listed signals were not found', (
      tester,
    ) async {
      _useDesktopViewport(tester);
      final dialogs = _FakeFileDialogs()..install(tester);
      final fixture = await _loadFixture('test/fixtures/xz_transitions.vcd');

      final listPath = _scratchPath('partial_signals.json');
      File(listPath).writeAsStringSync(
        jsonEncode({
          'version': 3,
          'signals': [
            {'id': fixture.signalIds.first},
            {'id': 'nonexistent.module.signal'},
          ],
          'session': {'appBarPinned': false},
        }),
      );
      dialogs.openPath = listPath;

      await tester.pumpWidget(
        App(
          signalWaveformRepository: fixture.repository,
          externalHierarchy: fixture.hierarchy,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Load signal list'));
      await _settleWithFileIo(tester);

      expect(find.text('Appended 1 signals (1 not found)'), findsOneWidget);
      expect(_signalBloc(tester).state.monitorSignalsList, hasLength(1));
      // The restored session unpinned the top bar, which now auto-hides.
      expect(tester.getTopLeft(find.byType(AppBar)).dy, lessThan(0));
    });

    testWidgets('reports an error when the save location is not writable', (
      tester,
    ) async {
      _useDesktopViewport(tester);
      final dialogs = _FakeFileDialogs()..install(tester);
      final fixture = await _loadFixture('test/fixtures/xz_transitions.vcd');
      dialogs.savePath = _scratchPath('missing-dir/signals.json');

      await tester.pumpWidget(
        App(
          signalWaveformRepository: fixture.repository,
          externalHierarchy: fixture.hierarchy,
          initialMonitoredSignalPaths: [fixture.signalIds.first],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Save signal list'));
      await _settleWithFileIo(tester);

      expect(find.textContaining('Error saving signal list'), findsOneWidget);
    });
  });

  group('keyboard shortcuts', () {
    testWidgets('deletes focused signals and undoes/redoes the edit', (
      tester,
    ) async {
      _useDesktopViewport(tester);
      final fixture = await _loadFixture('test/fixtures/xz_transitions.vcd');
      final monitored = fixture.signalIds.take(2).toList();

      await tester.pumpWidget(
        App(
          signalWaveformRepository: fixture.repository,
          externalHierarchy: fixture.hierarchy,
          initialMonitoredSignalPaths: monitored,
        ),
      );
      await tester.pumpAndSettle();

      final signalBloc = _signalBloc(tester);
      expect(signalBloc.state.monitorSignalsList, hasLength(2));

      // Focusing a row puts keyboard focus inside the page's shortcut handler.
      await tester.tap(find.byType(SignalTabContainer).first);
      await tester.pumpAndSettle();
      expect(signalBloc.state.hasFocusedSignals, isTrue);

      // `f` fits the waveform to the viewport; it must not disturb the list.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pumpAndSettle();
      expect(signalBloc.state.monitorSignalsList, hasLength(2));

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(
        signalBloc.state.monitorSignalsList.map((w) => w.signalId),
        [monitored.last],
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(
        signalBloc.state.monitorSignalsList.map((w) => w.signalId),
        monitored,
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(
        signalBloc.state.monitorSignalsList.map((w) => w.signalId),
        [monitored.last],
      );
    });

    testWidgets('ignores shortcuts while typing in a text field', (
      tester,
    ) async {
      _useDesktopViewport(tester);
      final fixture = await _loadFixture('test/fixtures/xz_transitions.vcd');
      final monitored = fixture.signalIds.take(2).toList();

      await tester.pumpWidget(
        App(
          signalWaveformRepository: fixture.repository,
          externalHierarchy: fixture.hierarchy,
          initialMonitoredSignalPaths: monitored,
        ),
      );
      await tester.pumpAndSettle();

      final signalBloc = _signalBloc(tester);
      await tester.tap(find.byType(SignalTabContainer).first);
      await tester.pumpAndSettle();
      expect(signalBloc.state.hasFocusedSignals, isTrue);

      await tester.tap(find.byType(TextField).first);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();

      expect(signalBloc.state.monitorSignalsList, hasLength(2));
    });
  });

  group('layout controls', () {
    testWidgets('pins and unpins the hierarchy panel and resizes it', (
      tester,
    ) async {
      _useDesktopViewport(tester);
      final fixture = await _loadFixture('test/fixtures/xz_transitions.vcd');

      await tester.pumpWidget(
        App(
          signalWaveformRepository: fixture.repository,
          externalHierarchy: fixture.hierarchy,
          initialMonitoredSignalPaths: [fixture.signalIds.first],
        ),
      );
      await tester.pumpAndSettle();

      final startWidth = tester.getSize(find.byType(HierarchyOverlay)).width;

      // Drag the pinned divider to widen the hierarchy pane.
      final divider = find.byWidgetPredicate(
        (widget) =>
            widget is MouseRegion &&
            widget.cursor == SystemMouseCursors.resizeColumn,
      );
      await tester.drag(divider.first, const Offset(60, 0));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(HierarchyOverlay)).width,
        greaterThan(startWidth),
      );

      // Unpin, then re-pin (which recomputes the pane width from the signals).
      await tester.tap(find.byTooltip('Unpin panel'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Pin panel open'), findsOneWidget);

      // Unpinned, the hierarchy slides away; hovering the left edge reveals it.
      await _hoverAt(tester, const Offset(4, 500));
      await tester.tap(find.byTooltip('Pin panel open'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Unpin panel'), findsOneWidget);
      expect(
        tester.getSize(find.byType(HierarchyOverlay)).width,
        greaterThanOrEqualTo(140),
      );
    });

    testWidgets('toggles the top bar pin and auto-hides it', (tester) async {
      _useDesktopViewport(tester);
      final fixture = await _loadFixture('test/fixtures/xz_transitions.vcd');

      await tester.pumpWidget(
        App(
          signalWaveformRepository: fixture.repository,
          externalHierarchy: fixture.hierarchy,
          initialMonitoredSignalPaths: [fixture.signalIds.first],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Unpin top bar'), findsOneWidget);
      expect(tester.getTopLeft(find.byType(AppBar)).dy, 0);

      await tester.tap(find.byTooltip('Unpin top bar'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Pin top bar'), findsOneWidget);
      // The unpinned bar slides off the top of the viewport.
      expect(tester.getTopLeft(find.byType(AppBar)).dy, lessThan(0));

      // Hovering the top trigger strip slides it back into view.
      await _hoverAt(tester, const Offset(800, 4));
      expect(tester.getTopLeft(find.byType(AppBar)).dy, 0);

      await tester.tap(find.byTooltip('Pin top bar'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Unpin top bar'), findsOneWidget);
    });

    testWidgets('shrinks and grows the waveform row height', (tester) async {
      _useDesktopViewport(tester);
      final fixture = await _loadFixture('test/fixtures/xz_transitions.vcd');

      await tester.pumpWidget(
        App(
          signalWaveformRepository: fixture.repository,
          externalHierarchy: fixture.hierarchy,
          initialMonitoredSignalPaths: [fixture.signalIds.first],
        ),
      );
      await tester.pumpAndSettle();

      final scaleCubit = BlocProvider.of<WaveformScaleCubit>(
        tester.element(find.byType(WaveFormViewerPage)),
      );
      expect(scaleCubit.state, 1.0);

      await tester.tap(find.byTooltip('Decrease row height (100%)'));
      await tester.pumpAndSettle();
      expect(scaleCubit.state, lessThan(1.0));

      final shrunk = scaleCubit.state;
      await tester.tap(
        find.byTooltip('Increase row height (${(shrunk * 100).round()}%)'),
      );
      await tester.pumpAndSettle();
      expect(scaleCubit.state, greaterThan(shrunk));
    });
  });

  group('cross-probing', () {
    testWidgets('receives peer signals and follows the active toggle', (
      tester,
    ) async {
      _useDesktopViewport(tester);
      final fixture = await _loadFixture('test/fixtures/xz_transitions.vcd');
      final channel = LocalCrossProbeChannel();
      final waveService = LocalCrossProbeService(channel, source: 'wave');
      final peerService = LocalCrossProbeService(channel, source: 'schematic');
      addTearDown(waveService.dispose);
      addTearDown(peerService.dispose);

      await tester.pumpWidget(
        App(
          signalWaveformRepository: fixture.repository,
          externalHierarchy: fixture.hierarchy,
          crossProbeService: waveService,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CrossProbeButton), findsOneWidget);

      peerService.send([fixture.signalIds.first], source: 'schematic');
      await tester.pumpAndSettle();
      expect(
        _signalBloc(tester).state.monitorSignalsList.map((w) => w.signalId),
        [fixture.signalIds.first],
      );

      // Disabling cross-probing rebuilds the page and stops deliveries.
      await tester.tap(find.byType(CrossProbeButton));
      await tester.pumpAndSettle();
      expect(waveService.isActive.value, isFalse);

      peerService.send([fixture.signalIds.last], source: 'schematic');
      await tester.pumpAndSettle();
      expect(_signalBloc(tester).state.monitorSignalsList, hasLength(1));
    });

    testWidgets('sends a monitored signal to peers from the row menu', (
      tester,
    ) async {
      _useDesktopViewport(tester);
      final fixture = await _loadFixture('test/fixtures/xz_transitions.vcd');
      final channel = LocalCrossProbeChannel();
      final waveService = LocalCrossProbeService(channel, source: 'wave');
      final peerService = LocalCrossProbeService(channel, source: 'schematic');
      addTearDown(waveService.dispose);
      addTearDown(peerService.dispose);
      await tester.pumpWidget(
        App(
          signalWaveformRepository: fixture.repository,
          externalHierarchy: fixture.hierarchy,
          crossProbeService: waveService,
          initialMonitoredSignalPaths: [fixture.signalIds.first],
        ),
      );
      await tester.pumpAndSettle();

      final row = find.byType(SignalTabContainer).first;
      await tester.tap(row, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      expect(find.text('Send Signal'), findsOneWidget);

      await tester.tap(find.text('Send Signal'));
      await tester.pumpAndSettle();
      expect(peerService.incomingSignals.value, [fixture.signalIds.first]);
    });
  });

  group('extension handshake', () {
    testWidgets('pings and queries module info, retrying after an error', (
      tester,
    ) async {
      _useDesktopViewport(tester);
      final fixture = await _loadFixture('test/fixtures/xz_transitions.vcd');
      final client = _FakeExtensionClient()
        ..response = const RohdModuleInfo(
          extensionAvailable: true,
          error: 'not ready',
        );

      await tester.pumpWidget(
        App(
          signalWaveformRepository: fixture.repository,
          externalHierarchy: fixture.hierarchy,
          extensionClient: client,
        ),
      );
      await tester.pumpAndSettle();

      expect(client.pingCount, greaterThanOrEqualTo(1));
      expect(client.queriedModules, isNotEmpty);

      final queriesBeforeRetry = client.queriedModules.length;
      client.response = const RohdModuleInfo(extensionAvailable: true);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(client.queriedModules.length, greaterThan(queriesBeforeRetry));
      expect(client.disposed, isFalse);
    });
  });

  group('embedded snapshot controls', () {
    testWidgets('snapshots at the marker and toggles video mode', (
      tester,
    ) async {
      _useDesktopViewport(tester);
      final fixture = await _loadFixture('test/fixtures/xz_transitions.vcd');
      final canSnapshot = ValueNotifier<bool>(true);
      addTearDown(canSnapshot.dispose);
      final snapshots = <int>[];
      var videoToggles = 0;

      await tester.pumpWidget(
        App(
          signalWaveformRepository: fixture.repository,
          externalHierarchy: fixture.hierarchy,
          initialMonitoredSignalPaths: [fixture.signalIds.first],
          isExtensionMode: true,
          canSnapshotNotifier: canSnapshot,
          lastSnapshotTimePs: 5,
          onSnapshotRequested: snapshots.add,
          onVideoModeToggled: () => videoToggles++,
        ),
      );
      await tester.pumpAndSettle();

      // Extension mode hides the standalone file picker.
      expect(find.byTooltip('Load waveform file'), findsNothing);
      expect(
        find.byTooltip(
          'Place marker first to take snapshot\nLast snapshot: 5 ps',
        ),
        findsOneWidget,
      );

      final pageContext = tester.element(find.byType(WaveFormViewerPage));
      BlocProvider.of<WaveformModuleBloc>(pageContext)
          .add(const WaveformModuleOnTap(40));
      await tester.pumpAndSettle();

      final snapshotTooltip = find.byTooltip(
        'Snapshot all signals at marker (40 ps)\nLast snapshot: 5 ps',
      );
      expect(snapshotTooltip, findsOneWidget);
      await tester.tap(snapshotTooltip);
      await tester.pump();
      expect(snapshots, [40]);

      await tester.tap(
        find.byTooltip(
          'Manual mode — snapshots at marker.\n'
          'Click to enable live tracking.',
        ),
      );
      await tester.pump();
      expect(videoToggles, 1);

      // Losing the VM disables both controls.
      canSnapshot.value = false;
      await tester.pumpAndSettle();
      expect(
        find.byTooltip('Snapshot unavailable (VM ended)\nLast snapshot: 5 ps'),
        findsOneWidget,
      );
    });

    testWidgets('shows live-tracking state without a snapshot history', (
      tester,
    ) async {
      _useDesktopViewport(tester);
      final fixture = await _loadFixture('test/fixtures/xz_transitions.vcd');
      final snapshots = <int>[];
      var videoToggles = 0;

      await tester.pumpWidget(
        App(
          signalWaveformRepository: fixture.repository,
          externalHierarchy: fixture.hierarchy,
          initialMonitoredSignalPaths: [fixture.signalIds.first],
          isExtensionMode: true,
          isVideoMode: true,
          onSnapshotRequested: snapshots.add,
          onVideoModeToggled: () => videoToggles++,
        ),
      );
      await tester.pumpAndSettle();

      // Without a marker or a previous snapshot the button explains itself.
      expect(
        find.byTooltip('Place marker first to take snapshot'),
        findsOneWidget,
      );

      BlocProvider.of<WaveformModuleBloc>(
        tester.element(find.byType(WaveFormViewerPage)),
      ).add(const WaveformModuleOnTap(20));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byTooltip(
          'Live tracking ON — auto-snapshots at latest time.\n'
          'Click to switch to manual marker mode.',
        ),
      );
      await tester.pump();
      expect(videoToggles, 1);

      // The parent rebuilds with manual mode after handling the toggle.
      await tester.pumpWidget(
        App(
          signalWaveformRepository: fixture.repository,
          externalHierarchy: fixture.hierarchy,
          initialMonitoredSignalPaths: [fixture.signalIds.first],
          isExtensionMode: true,
          onSnapshotRequested: snapshots.add,
          onVideoModeToggled: () => videoToggles++,
        ),
      );
      await tester.pumpAndSettle();
      BlocProvider.of<WaveformModuleBloc>(
        tester.element(find.byType(WaveFormViewerPage)),
      ).add(const WaveformModuleOnTap(20));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byTooltip('Snapshot all signals at marker (20 ps)'),
      );
      await tester.pump();
      expect(snapshots, [20]);
    });
  });

  group('live simulation updates', () {
    testWidgets('refreshes monitored signals as new data streams in', (
      tester,
    ) async {
      _useDesktopViewport(tester);
      final fixture = await _loadFixture('test/fixtures/xz_transitions.vcd');
      final liveUpdates = StreamController<WaveformUpdateEvent>.broadcast();
      addTearDown(liveUpdates.close);

      await tester.pumpWidget(
        App(
          signalWaveformRepository: fixture.repository,
          externalHierarchy: fixture.hierarchy,
          initialMonitoredSignalPaths: [fixture.signalIds.first],
          liveUpdates: liveUpdates.stream,
        ),
      );
      await tester.pumpAndSettle();

      liveUpdates.add(
        WaveformUpdateEvent(
          incrementalData: const [],
          reason: WaveformUpdateReason.periodic,
          upToTime: 120,
        ),
      );
      await tester.pumpAndSettle();

      // The viewer stays on the same signal and keeps rendering the waves.
      expect(_signalBloc(tester).state.monitorSignalsList, hasLength(1));
      expect(find.byType(SignalTabContainer), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}
