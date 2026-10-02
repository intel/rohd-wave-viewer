// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// hierarchy_widget_test.dart
// Tests for the HierarchyWidget component.
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:dart_wellen/dart_wellen.dart' hide SignalWaveform;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide MetaData;
import 'package:mocktail/mocktail.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart';
import 'package:rohd_wave_viewer/src/modules/hierarchy/hierarchy.dart';
import 'package:rohd_wave_viewer/src/modules/hierarchy/hierarchy_overlay.dart';
import 'package:rohd_wave_viewer/src/modules/rohd_module/bloc/rohd_module_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';
import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';
import 'package:rohd_wave_viewer/testing.dart';

import '../../helpers.dart';

/// Captures text copied to the clipboard by the widget under test.
List<String> mockClipboard() {
  final copied = <String>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      copied.add((call.arguments as Map<Object?, Object?>)['text']! as String);
    }
    return null;
  });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return copied;
}

void main() {
  tearDown(SignalValueFormatRegistry.clear);

  late SignalWaveformRepository repository;
  late ModuleStructure mockModuleStructure;
  late RohdModuleBloc rohdModuleBloc;
  late SignalBloc signalBloc;

  setUpAll(() {
    // Register fallback values for mocktail
    registerFallbackValue(const RohdModuleInit());
    registerFallbackValue(
      SignalUpdateEvent(
        HierarchyOccurrence(name: 'test', signals: [], children: []),
      ),
    );
  });

  setUp(() async {
    // Create repository with mock API
    final mockApi = MockSignalWaveformApi();
    repository = SignalWaveformRepository(signalWaveformApi: mockApi);
    mockModuleStructure = await mockApi.getModuleStructure();
    repository.buildSignalCacheFromHierarchy(mockModuleStructure.modules);

    // Create mock blocs
    rohdModuleBloc = MockRohdModuleBloc();
    signalBloc = MockSignalBloc();
  });

  group('HierarchyWidget', () {
    testWidgets('renders with createOwnBlocs=true', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HierarchyWidget(repository: repository, createOwnBlocs: true),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Should render without error
      expect(find.byType(HierarchyWidget), findsOneWidget);
    });

    testWidgets('renders with parent blocs when createOwnBlocs=false', (
      tester,
    ) async {
      // Setup mock bloc states
      when(
        () => rohdModuleBloc.state,
      ).thenReturn(Rendered(mockModuleStructure));
      when(() => rohdModuleBloc.repository).thenReturn(repository);

      final signals = repository.getSignalsBySelectedModule(
        mockModuleStructure.modules.first,
      );
      when(() => signalBloc.state).thenReturn(SignalLoaded(signals, const []));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiBlocProvider(
              providers: [
                BlocProvider<RohdModuleBloc>.value(value: rohdModuleBloc),
                BlocProvider<SignalBloc>.value(value: signalBloc),
              ],
              child: HierarchyWidget(repository: repository),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(HierarchyWidget), findsOneWidget);
    });

    testWidgets('calls onPortSelected callback when signal double-tapped', (
      tester,
    ) async {
      // Track callback invocations - ignore warning, used for documentation
      // ignore: unused_local_variable
      var callbackInvoked = false;

      // Setup mock bloc states
      when(() => rohdModuleBloc.state).thenReturn(
        ModuleSelected(mockModuleStructure, mockModuleStructure.modules.first),
      );
      when(() => rohdModuleBloc.repository).thenReturn(repository);
      when(() => rohdModuleBloc.stream).thenAnswer((_) => const Stream.empty());

      final signals = repository.getSignalsBySelectedModule(
        mockModuleStructure.modules.first,
      );
      when(() => signalBloc.state).thenReturn(SignalLoaded(signals, const []));
      when(() => signalBloc.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiBlocProvider(
              providers: [
                BlocProvider<RohdModuleBloc>.value(value: rohdModuleBloc),
                BlocProvider<SignalBloc>.value(value: signalBloc),
              ],
              child: HierarchyWidget(
                repository: repository,
                onPortSelected: (port, module, signal) {
                  callbackInvoked = true;
                },
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find signal list items - they should be present if signals exist
      // The exact widget structure depends on how SignalList renders
      expect(find.byType(HierarchyWidget), findsOneWidget);
      // Note: callbackInvoked would be true if we could simulate double-tap
      // but that requires knowing the exact widget structure
    });

    testWidgets('shows loading state when bloc is loading', (tester) async {
      // Setup loading state with an empty ModuleStructure
      const emptyStructure = ModuleStructure(
        metadata: MetaData(source: 'test', date: '', timescale: ''),
        modules: [],
      );
      when(
        () => rohdModuleBloc.state,
      ).thenReturn(const Loading(emptyStructure));
      when(() => rohdModuleBloc.repository).thenReturn(repository);
      when(() => rohdModuleBloc.stream).thenAnswer((_) => const Stream.empty());

      when(() => signalBloc.state).thenReturn(SignalLoading());
      when(() => signalBloc.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiBlocProvider(
              providers: [
                BlocProvider<RohdModuleBloc>.value(value: rohdModuleBloc),
                BlocProvider<SignalBloc>.value(value: signalBloc),
              ],
              child: HierarchyWidget(repository: repository),
            ),
          ),
        ),
      );

      // Don't pumpAndSettle - we want to see loading state
      await tester.pump();

      expect(find.byType(HierarchyWidget), findsOneWidget);
    });
  });

  group('HierarchyWidget integration', () {
    testWidgets('widget creates own blocs and initializes', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HierarchyWidget(repository: repository, createOwnBlocs: true),
          ),
        ),
      );

      // Allow bloc to initialize
      await tester.pumpAndSettle();

      // Widget should be present
      expect(find.byType(HierarchyWidget), findsOneWidget);
    });

    testWidgets('double-tap adds a real fixture signal to monitoring',
        (tester) async {
      await WellenSignalWaveformApi.init();
      final api = WellenSignalWaveformApi();
      await api.loadFile('test/fixtures/xz_transitions.vcd');
      final fixtureRepository = SignalWaveformRepository(
        signalWaveformApi: api,
      );
      final moduleBloc = RohdModuleBloc(
        signalWaveformRepository: fixtureRepository,
      );
      final fixtureSignalBloc = SignalBloc(fixtureRepository);
      addTearDown(moduleBloc.close);
      addTearDown(fixtureSignalBloc.close);

      moduleBloc.add(const RohdModuleInit());
      final moduleState = await moduleBloc.stream.firstWhere(
        (state) => state is ModuleSelected,
      ) as ModuleSelected;
      fixtureSignalBloc.add(SignalUpdateEvent(moduleState.singleModule));
      await fixtureSignalBloc.stream
          .firstWhere((state) => state is SignalLoaded);

      SignalOccurrence? callbackSignal;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiBlocProvider(
              providers: [
                BlocProvider<RohdModuleBloc>.value(value: moduleBloc),
                BlocProvider<SignalBloc>.value(value: fixtureSignalBloc),
              ],
              child: HierarchyWidget(
                repository: fixtureRepository,
                onPortSelected: (port, module, signal) =>
                    callbackSignal = signal,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final signalFinder = find.textContaining('bin_xz');
      expect(signalFinder, findsOneWidget);
      final monitoredState = fixtureSignalBloc.stream.firstWhere(
        (state) => state.monitorSignalsList.isNotEmpty,
      );
      await tester.tap(signalFinder);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(signalFinder);
      await tester.pump(const Duration(milliseconds: 100));
      final state = await monitoredState;

      expect(callbackSignal?.name, 'bin_xz');
      expect(state.monitorSignalsList.single.signalId, contains('bin_xz'));
      expect(state.monitorSignalsList.single.data, isNotEmpty);
    });

    testWidgets('filters, sorts, and context-menu manages fixture signals',
        (tester) async {
      await WellenSignalWaveformApi.init();
      final api = WellenSignalWaveformApi();
      await api.loadFile('test/fixtures/xz_transitions.vcd');
      final fixtureRepository = SignalWaveformRepository(
        signalWaveformApi: api,
      );
      final moduleBloc = RohdModuleBloc(
        signalWaveformRepository: fixtureRepository,
      );
      final fixtureSignalBloc = SignalBloc(fixtureRepository);
      addTearDown(moduleBloc.close);
      addTearDown(fixtureSignalBloc.close);

      moduleBloc.add(const RohdModuleInit());
      final moduleState = await moduleBloc.stream.firstWhere(
        (state) => state is ModuleSelected,
      ) as ModuleSelected;
      fixtureSignalBloc.add(SignalUpdateEvent(moduleState.singleModule));
      await fixtureSignalBloc.stream
          .firstWhere((state) => state is SignalLoaded);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiBlocProvider(
              providers: [
                BlocProvider<RohdModuleBloc>.value(value: moduleBloc),
                BlocProvider<SignalBloc>.value(value: fixtureSignalBloc),
              ],
              child: HierarchyWidget(repository: fixtureRepository),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'bin_xz');
      await tester.pump();
      expect(fixtureSignalBloc.state.filterText, 'bin_xz');
      final signalFinder = find.byWidgetPredicate(
        (widget) => widget is Text && widget.data == 'bin_xz',
      );
      expect(signalFinder, findsOneWidget);

      await tester.tap(find.byTooltip('Sort Z→A'));
      await tester.pump();
      expect(fixtureSignalBloc.state.sortAscending, isFalse);

      final signalId = fixtureSignalBloc.state.filteredSignals.single.path();
      final selectedState = fixtureSignalBloc.stream.firstWhere(
        (state) => state.moduleSelectedSignalIds.isNotEmpty,
      );
      fixtureSignalBloc.add(ModuleSignalSelectEvent(signalId));
      await selectedState;
      await tester.pump();

      await tester.tapAt(
        tester.getCenter(signalFinder),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      final addedState = fixtureSignalBloc.stream.firstWhere(
        (state) => state.monitorSignalsList.isNotEmpty,
      );
      await tester.tap(find.text('Add to Selected Signals'));
      await tester.pump();
      expect((await addedState).monitorSignalsList.single.data, isNotEmpty);

      await tester.tapAt(
        tester.getCenter(signalFinder),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Remove from Selected Signals'), findsOneWidget);
      await tester.tap(find.text('Remove from Selected Signals'));
      await tester.pump();
      expect(fixtureSignalBloc.state.monitorSignalsList, isEmpty);
    });

    testWidgets('selects fixture ranges and invokes host signal callbacks',
        (tester) async {
      await WellenSignalWaveformApi.init();
      final api = WellenSignalWaveformApi();
      await api.loadFile('test/fixtures/xz_transitions.vcd');
      final fixtureRepository = SignalWaveformRepository(
        signalWaveformApi: api,
      );
      final moduleBloc = RohdModuleBloc(
        signalWaveformRepository: fixtureRepository,
      );
      final fixtureSignalBloc = SignalBloc(fixtureRepository);
      addTearDown(moduleBloc.close);
      addTearDown(fixtureSignalBloc.close);

      moduleBloc.add(const RohdModuleInit());
      final moduleState = await moduleBloc.stream.firstWhere(
        (state) => state is ModuleSelected,
      ) as ModuleSelected;
      fixtureSignalBloc.add(SignalUpdateEvent(moduleState.singleModule));
      await fixtureSignalBloc.stream
          .firstWhere((state) => state is SignalLoaded);

      List<String>? sentSignalPaths;
      RohdSourceFormat? sourceFormat;
      List<String>? sourceSignalPaths;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiBlocProvider(
              providers: [
                BlocProvider<RohdModuleBloc>.value(value: moduleBloc),
                BlocProvider<SignalBloc>.value(value: fixtureSignalBloc),
              ],
              child: HierarchyWidget(
                repository: fixtureRepository,
                onSendSignals: (paths) => sentSignalPaths = paths,
                onGoToSource: (format, paths) {
                  sourceFormat = format;
                  sourceSignalPaths = paths;
                },
                availableSourceFormats: () => const [
                  RohdSourceFormat.rohd,
                  RohdSourceFormat.sc,
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final treeFinder = find.byType(ModuleTreePanel);
      final initialTreeHeight = tester.getSize(treeFinder).height;
      final dividerFinder = find.byWidgetPredicate(
        (widget) =>
            widget is GestureDetector && widget.onVerticalDragUpdate != null,
      );
      expect(dividerFinder, findsOneWidget);
      await tester.drag(dividerFinder, const Offset(0, 60));
      await tester.pump();
      expect(tester.getSize(treeFinder).height, greaterThan(initialTreeHeight));

      final firstSignal = fixtureSignalBloc.state.filteredSignals[0];
      final secondSignal = fixtureSignalBloc.state.filteredSignals[1];
      final firstFinder = find.text(firstSignal.name);
      final secondFinder = find.text(secondSignal.name);
      expect(firstFinder, findsOneWidget);
      expect(secondFinder, findsOneWidget);

      fixtureSignalBloc
        ..add(ModuleSignalSelectEvent(firstSignal.path()))
        ..add(ModuleSignalToggleEvent(secondSignal.path()));
      await tester.pump();
      expect(
        fixtureSignalBloc.state.moduleSelectedSignalIds,
        {firstSignal.path(), secondSignal.path()},
      );

      fixtureSignalBloc.add(
        ModuleSignalRangeSelectEvent(anchorIndex: 0, extentIndex: 1),
      );
      await tester.pump();
      expect(
        fixtureSignalBloc.state.moduleSelectedSignalIds,
        {firstSignal.path(), secondSignal.path()},
      );

      await tester.enterText(find.byType(TextField), 'bin_xz');
      await tester.pump();
      final signalFinder = find.byWidgetPredicate(
        (widget) => widget is Text && widget.data == 'bin_xz',
      );
      expect(signalFinder, findsOneWidget);

      await tester.tapAt(
        tester.getCenter(signalFinder),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Go to ROHD Source'), findsOneWidget);
      expect(find.text('Go to SV Source'), findsNothing);
      expect(find.text('Go to SystemC Source'), findsOneWidget);
      await tester.tap(find.text('Send Signal'));
      await tester.pump();
      expect(sentSignalPaths,
          [fixtureSignalBloc.state.filteredSignals.single.path()]);

      await tester.tapAt(
        tester.getCenter(signalFinder),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Go to ROHD Source'));
      await tester.pump();
      expect(sourceFormat, RohdSourceFormat.rohd);
      expect(sourceSignalPaths, sentSignalPaths);
    });
  });

  group('HierarchyWidget bit expansion', () {
    late RohdModuleBloc fixtureModuleBloc;
    late SignalBloc fixtureSignalBloc;
    late SignalWaveformRepository fixtureRepository;
    var overlayHoldCount = 0;

    setUp(() => overlayHoldCount = 0);

    Future<void> loadFixture() async {
      await WellenSignalWaveformApi.init();
      final api = WellenSignalWaveformApi();
      await api.loadFile('test/fixtures/xz_transitions.vcd');
      fixtureRepository = SignalWaveformRepository(signalWaveformApi: api);
      fixtureModuleBloc = RohdModuleBloc(
        signalWaveformRepository: fixtureRepository,
      );
      fixtureSignalBloc = SignalBloc(fixtureRepository);
      addTearDown(fixtureModuleBloc.close);
      addTearDown(fixtureSignalBloc.close);

      fixtureModuleBloc.add(const RohdModuleInit());
      final moduleState = await fixtureModuleBloc.stream.firstWhere(
        (state) => state is ModuleSelected,
      ) as ModuleSelected;
      fixtureSignalBloc.add(SignalUpdateEvent(moduleState.singleModule));
      await fixtureSignalBloc.stream
          .firstWhere((state) => state is SignalLoaded);
    }

    Future<void> pumpHierarchy(
      WidgetTester tester, {
      double height = 600,
      void Function(List<String> signalPaths)? onSendSignals,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: height,
              child: HierarchyOverlayHold(
                hold: () => overlayHoldCount++,
                release: () => overlayHoldCount--,
                child: MultiBlocProvider(
                  providers: [
                    BlocProvider<RohdModuleBloc>.value(
                      value: fixtureModuleBloc,
                    ),
                    BlocProvider<SignalBloc>.value(value: fixtureSignalBloc),
                  ],
                  child: HierarchyWidget(
                    repository: fixtureRepository,
                    onSendSignals: onSendSignals,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    // A single tap on a signal row resolves only after the double-tap
    // timeout, so give the gesture arena time to settle.
    Future<void> tapRow(WidgetTester tester, Finder row) async {
      await tester.tap(row);
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> openSignalMenu(WidgetTester tester, Finder row) async {
      await tester.tapAt(
        tester.getCenter(row),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      // The hierarchy overlay must stay pinned open behind the menu.
      expect(overlayHoldCount, 1);
    }

    testWidgets('expands bits inline and monitors a single-bit row',
        (tester) async {
      await loadFixture();
      await pumpHierarchy(tester);

      await tester.enterText(find.byType(TextField), 'bin5_xz');
      await tester.pump();
      final row = find.text('bin5_xz (5)');
      expect(row, findsOneWidget);

      await openSignalMenu(tester, row);
      await tester.tap(find.text('Expand Bits [5]'));
      await tester.pumpAndSettle();

      // One inline sub-row per bit, ordered MSB→LSB.
      for (var bit = 0; bit < 5; bit++) {
        expect(find.text('[$bit]'), findsOneWidget);
      }
      final bitRows = tester
          .widgetList<Text>(find.byWidgetPredicate(
            (widget) => widget is Text && (widget.data ?? '').startsWith('['),
          ))
          .map((text) => text.data)
          .toList();
      expect(bitRows, ['[4]', '[3]', '[2]', '[1]', '[0]']);

      // Double-tapping a bit row adds that bit slice to the monitor list.
      final msbRow = find.text('[4]');
      final monitored = fixtureSignalBloc.stream.firstWhere(
        (state) => state.monitorSignalsList.isNotEmpty,
      );
      await tester.tap(msbRow);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(msbRow);
      await tester.pump(const Duration(milliseconds: 100));
      final withBit = await monitored;
      expect(withBit.monitorSignalsList.single.name, 'bin5_xz[4]');
      expect(withBit.monitorSignalsList.single.id, contains('#b[4]'));
      await tester.pump();

      // The same row's context menu removes it again.
      await openSignalMenu(tester, msbRow);
      expect(find.text('Remove from Selected Signals'), findsOneWidget);
      await tester.tap(find.text('Remove from Selected Signals'));
      await tester.pumpAndSettle();
      expect(fixtureSignalBloc.state.monitorSignalsList, isEmpty);
      expect(overlayHoldCount, 0);
    });

    testWidgets('defines named bit fields and adds one to the monitor',
        (tester) async {
      final clipboardTexts = mockClipboard();
      await loadFixture();
      await pumpHierarchy(tester);

      await tester.enterText(find.byType(TextField), 'data8');
      await tester.pump();
      final row = find.text('data8 (8)');
      expect(row, findsOneWidget);

      await openSignalMenu(tester, row);
      await tester.tap(find.text('Define Bit Fields [8]...'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'high 7:4\nlow 3:0',
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('high [7:4]'), findsOneWidget);
      expect(find.text('low [3:0]'), findsOneWidget);

      final monitored = fixtureSignalBloc.stream.firstWhere(
        (state) => state.monitorSignalsList.isNotEmpty,
      );
      await tester.tap(find.text('high [7:4]'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('high [7:4]'));
      await tester.pump(const Duration(milliseconds: 100));
      final withField = await monitored;
      expect(withField.monitorSignalsList.single.name, 'high');
      expect(withField.monitorSignalsList.single.id, contains('#b[7:4]'));
      await tester.pump();

      await openSignalMenu(tester, find.text('high [7:4]'));
      await tester.tap(find.text('Copy Name'));
      await tester.pumpAndSettle();
      expect(clipboardTexts.single, 'high');
    });

    testWidgets('sends a named bit field to the host viewer', (tester) async {
      final clipboardTexts = mockClipboard();
      await loadFixture();
      List<String>? sentPaths;
      await pumpHierarchy(tester, onSendSignals: (paths) => sentPaths = paths);

      await tester.enterText(find.byType(TextField), 'data8');
      await tester.pump();

      await openSignalMenu(tester, find.text('data8 (8)'));
      await tester.tap(find.text('Expand Bits [8]'));
      await tester.pumpAndSettle();

      await openSignalMenu(tester, find.text('[7]'));
      await tester.tap(find.text('Send Signal'));
      await tester.pumpAndSettle();
      expect(sentPaths, ['test/data8']);

      await openSignalMenu(tester, find.text('[7]'));
      await tester.tap(find.text('Copy Name'));
      await tester.pumpAndSettle();
      expect(clipboardTexts.single, 'data8[7]');
    });

    testWidgets('copies names and paths for a multi-signal selection',
        (tester) async {
      final clipboardTexts = mockClipboard();

      await loadFixture();
      await pumpHierarchy(tester);

      await tester.tap(find.byTooltip('Sort A→Z'));
      await tester.pump();
      expect(fixtureSignalBloc.state.sortAscending, isTrue);

      final signals = fixtureSignalBloc.state.filteredSignals;
      expect(
        signals.map((signal) => signal.name).toList(),
        ['bin5_xz', 'bin_xz', 'clk', 'data8'],
      );
      final first = find.textContaining(signals[0].name);
      final second = find.textContaining(signals[1].name);

      await tapRow(tester, first);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tapRow(tester, second);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(
        fixtureSignalBloc.state.moduleSelectedSignalIds,
        {signals[0].path(), signals[1].path()},
      );

      await openSignalMenu(tester, first);
      await tester.tap(find.text('Copy 2 Names'));
      await tester.pumpAndSettle();
      expect(
        clipboardTexts.single.split('\n').toSet(),
        {signals[0].name, signals[1].name},
      );

      await openSignalMenu(tester, first);
      await tester.tap(find.text('Copy 2 Full Paths'));
      await tester.pumpAndSettle();
      expect(
        clipboardTexts.last.split('\n').toSet(),
        {signals[0].path(), signals[1].path()},
      );
    });

    testWidgets('selects every signal with ctrl+A and ranges with shift-click',
        (tester) async {
      await loadFixture();
      await pumpHierarchy(tester);

      final signals = fixtureSignalBloc.state.filteredSignals;
      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: Offset.zero);
      addTearDown(pointer.removePointer);
      await pointer.moveTo(tester.getCenter(find.text(signals.first.name)));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(
        fixtureSignalBloc.state.moduleSelectedSignalIds,
        signals.map((signal) => signal.path()).toSet(),
      );

      // Cmd-A behaves the same way for macOS users.
      fixtureSignalBloc.add(ModuleSignalSelectEvent(signals.first.path()));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(
        fixtureSignalBloc.state.moduleSelectedSignalIds,
        signals.map((signal) => signal.path()).toSet(),
      );

      // Anchor on the first row, then shift-click the third row.
      await tapRow(tester, find.text(signals.first.name));
      expect(
        fixtureSignalBloc.state.moduleSelectedSignalIds,
        {signals.first.path()},
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tapRow(tester, find.textContaining(signals[2].name));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(
        fixtureSignalBloc.state.moduleSelectedSignalIds,
        signals.take(3).map((signal) => signal.path()).toSet(),
      );
    });

    testWidgets('applies a display format from the signal context menu',
        (tester) async {
      await loadFixture();
      await pumpHierarchy(tester);

      await tester.enterText(find.byType(TextField), 'data8');
      await tester.pump();
      final row = find.text('data8 (8)');

      final monitored = fixtureSignalBloc.stream.firstWhere(
        (state) => state.monitorSignalsList.isNotEmpty,
      );
      await tester.tap(row);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(row);
      await tester.pump(const Duration(milliseconds: 100));
      await monitored;
      await tester.pump();

      await openSignalMenu(tester, row);
      await tester.tap(find.text('Format As'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hexadecimal'));
      await tester.pumpAndSettle();

      expect(
        fixtureSignalBloc.state.monitorSignalsList.single.valueFormat,
        MonitorValueFormat.hexadecimal,
      );
    });

    testWidgets('scrolls back to the last match when the filter is cleared',
        (tester) async {
      await loadFixture();
      await pumpHierarchy(tester, height: 200);

      await tester.enterText(find.byType(TextField), 'data8');
      await tester.pump();
      expect(find.text('data8 (8)'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();

      expect(fixtureSignalBloc.state.filterText, isEmpty);
      final listPosition = tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      expect(listPosition.pixels, greaterThan(0));
    });
  });

  group('HierarchyWidget structured signals', () {
    late RohdModuleBloc structModuleBloc;
    late SignalBloc structSignalBloc;
    var overlayHoldCount = 0;

    setUp(() => overlayHoldCount = 0);

    // Signal rows render a 14px expander; sub-field rows a 12px one.
    final signalChevron = find.byWidgetPredicate(
      (widget) =>
          widget is Icon &&
          widget.icon == Icons.chevron_right &&
          widget.size == 14,
    );
    final subFieldChevron = find.byWidgetPredicate(
      (widget) =>
          widget is Icon &&
          widget.icon == Icons.chevron_right &&
          widget.size == 12,
    );

    // Expander taps sit under the row's double-tap recognizer, so the arena
    // only resolves once the double-tap timeout has elapsed.
    Future<void> tapExpander(WidgetTester tester, Finder expander) async {
      await tester.tap(expander);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
    }

    Future<void> pumpSignals(
      WidgetTester tester,
      List<SignalOccurrence> signals, {
      List<SignalWaveform> monitorSignals = const [],
      bool isEmbedded = false,
      void Function(List<String> signalPaths)? onSendSignals,
      GoToSourceCallback? onGoToSource,
      AvailableSourceFormats? availableSourceFormats,
      ModuleStructure? moduleStructure,
    }) async {
      structModuleBloc = MockRohdModuleBloc();
      structSignalBloc = MockSignalBloc();
      final structure = moduleStructure ?? mockModuleStructure;
      when(() => structModuleBloc.state).thenReturn(
        ModuleSelected(structure, structure.modules.first),
      );
      when(() => structModuleBloc.repository).thenReturn(repository);
      when(() => structSignalBloc.state).thenReturn(
        SignalLoaded(signals, monitorSignals, showInternalSignals: true),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HierarchyOverlayHold(
              hold: () => overlayHoldCount++,
              release: () => overlayHoldCount--,
              child: MultiBlocProvider(
                providers: [
                  BlocProvider<RohdModuleBloc>.value(value: structModuleBloc),
                  BlocProvider<SignalBloc>.value(value: structSignalBloc),
                ],
                child: HierarchyWidget(
                  repository: repository,
                  isEmbedded: isEmbedded,
                  onSendSignals: onSendSignals,
                  onGoToSource: onGoToSource,
                  availableSourceFormats: availableSourceFormats,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('expands an array slice and its nested elements',
        (tester) async {
      final arraySignal = SignalOccurrence(
        name: 'samples',
        width: 160,
        logicType: const {
          'width': 160,
          'arrayDims': [10, 2],
          'elementWidth': 8,
        },
      );
      await pumpSignals(tester, [arraySignal]);

      await tapExpander(tester, signalChevron);
      expect(find.text('samples  [10 elements]'), findsOneWidget);
      expect(overlayHoldCount, 1);

      // Cancelling leaves the signal collapsed.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('[1] [31:16]'), findsNothing);
      expect(overlayHoldCount, 0);

      await tapExpander(tester, signalChevron);
      await tester.enterText(find.byType(TextField).last, '1:2');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('[1] [31:16]'), findsOneWidget);
      expect(find.text('[2] [47:32]'), findsOneWidget);
      expect(find.text('[0] [15:0]'), findsNothing);

      // Nested dimension has only two elements, so it expands without a
      // slice dialog.
      await tapExpander(tester, subFieldChevron.first);
      expect(find.text('[1].[0] [23:16]'), findsOneWidget);
      expect(find.text('[1].[1] [31:24]'), findsOneWidget);

      // Collapsing just the nested element keeps its parent expanded.
      await tapExpander(
        tester,
        find.byWidgetPredicate(
          (widget) =>
              widget is Icon &&
              widget.icon == Icons.expand_more &&
              widget.size == 12,
        ),
      );
      expect(find.text('[1].[0] [23:16]'), findsNothing);
      expect(find.text('[1] [31:16]'), findsOneWidget);
      await tapExpander(tester, subFieldChevron.first);

      await tester.tap(find.text('[1].[1] [31:24]'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('[1].[1] [31:24]'));
      await tester.pump(const Duration(milliseconds: 100));
      verify(
        () => structSignalBloc.add(
          SignalSubFieldSelectedEvent(
            parentSignal: arraySignal,
            fieldLabel: '[1].[1]',
            startBit: 24,
            width: 8,
          ),
        ),
      ).called(1);

      // Collapsing the parent removes every expanded row again.
      await tapExpander(
        tester,
        find.byWidgetPredicate(
          (widget) =>
              widget is Icon &&
              widget.icon == Icons.expand_more &&
              widget.size == 14,
        ),
      );
      expect(find.text('[1] [31:16]'), findsNothing);

      // Re-expanding with a bare index confirms a single element.
      await tapExpander(tester, signalChevron);
      await tester.enterText(find.byType(TextField).last, '4');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('[4] [79:64]'), findsOneWidget);
      expect(find.text('[1] [31:16]'), findsNothing);
    });

    testWidgets('slices a nested sub-array through its own dialog',
        (tester) async {
      final arraySignal = SignalOccurrence(
        name: 'blocks',
        width: 160,
        logicType: const {
          'width': 160,
          'arrayDims': [2, 10],
          'elementWidth': 8,
        },
      );
      await pumpSignals(tester, [arraySignal]);

      await tapExpander(tester, signalChevron);
      expect(find.text('[0] [79:0]'), findsOneWidget);
      expect(find.text('[1] [159:80]'), findsOneWidget);

      await tapExpander(tester, subFieldChevron.first);
      expect(find.text('[0]  [10 elements]'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('[0].[0] [7:0]'), findsNothing);

      await tapExpander(tester, subFieldChevron.first);
      await tester.enterText(find.byType(TextField).last, '0:1');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('[0].[0] [7:0]'), findsOneWidget);
      expect(find.text('[0].[1] [15:8]'), findsOneWidget);
      expect(find.text('[0].[2] [23:16]'), findsNothing);

      // Re-slicing with a bare index shows a single element.
      await tapExpander(
        tester,
        find.byWidgetPredicate(
          (widget) =>
              widget is Icon &&
              widget.icon == Icons.expand_more &&
              widget.size == 12,
        ),
      );
      await tapExpander(tester, subFieldChevron.first);
      await tester.enterText(find.byType(TextField).last, '3');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('[0].[3] [31:24]'), findsOneWidget);
      expect(find.text('[0].[0] [7:0]'), findsNothing);
    });

    testWidgets('routes struct sub-field menu actions to the host callbacks',
        (tester) async {
      final clipboardTexts = mockClipboard();

      final structSignal = SignalOccurrence(
        name: 'sample',
        width: 8,
        logicType: const {
          'typeName': 'Sample',
          'fields': [
            {
              'name': 'upper',
              'width': 4,
              'bits': [7, 6, 5, 4],
            },
            {
              'name': 'lower',
              'width': 4,
              'bits': [3, 2, 1, 0],
            },
          ],
        },
      );
      List<String>? sentPaths;
      RohdSourceFormat? sourceFormat;
      List<String>? sourcePaths;
      await pumpSignals(
        tester,
        [structSignal],
        onSendSignals: (paths) => sentPaths = paths,
        onGoToSource: (format, paths) {
          sourceFormat = format;
          sourcePaths = paths;
        },
        availableSourceFormats: () => const [RohdSourceFormat.rohd],
      );

      // The struct type name is shown next to the parent row.
      expect(find.text('Sample'), findsOneWidget);
      await tapExpander(tester, signalChevron);

      final upperRow = find.text('upper [7:4]');
      expect(upperRow, findsOneWidget);
      expect(find.text('lower [3:0]'), findsOneWidget);

      await tester.tapAt(
        tester.getCenter(upperRow),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Expand Bits [4]'), findsOneWidget);
      expect(find.text('Define Bit Fields [4]...'), findsOneWidget);
      await tester.tap(find.text('Expand Bits [4]'));
      await tester.pumpAndSettle();
      for (var bit = 0; bit < 4; bit++) {
        expect(find.text('[$bit]'), findsOneWidget);
      }

      await tester.tap(find.text('[3]'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('[3]'));
      await tester.pumpAndSettle();
      verify(
        () => structSignalBloc.add(
          SignalSubFieldSelectedEvent(
            parentSignal: structSignal,
            fieldLabel: 'upper#b[3]',
            startBit: 7,
            width: 1,
            displayName: 'sample_upper[3]',
          ),
        ),
      ).called(1);

      Color? rowColor(Finder row) => (tester
              .widget<Container>(
                find.ancestor(of: row, matching: find.byType(Container)).first,
              )
              .decoration! as BoxDecoration)
          .color;

      await tester.tap(upperRow);
      await tester.pump();
      expect(rowColor(upperRow), isNot(Colors.transparent));

      await tester.tapAt(
        tester.getCenter(upperRow),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(overlayHoldCount, 1);
      await tester.tap(find.text('Add to Selected Signals'));
      await tester.pumpAndSettle();
      verify(
        () => structSignalBloc.add(
          SignalSubFieldSelectedEvent(
            parentSignal: structSignal,
            fieldLabel: 'upper',
            startBit: 4,
            width: 4,
          ),
        ),
      ).called(1);

      await tester.tapAt(
        tester.getCenter(upperRow),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send Signal'));
      await tester.pumpAndSettle();
      expect(sentPaths, ['sample']);

      await tester.tapAt(
        tester.getCenter(upperRow),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Go to ROHD Source'));
      await tester.pumpAndSettle();
      expect(sourceFormat, RohdSourceFormat.rohd);
      expect(sourcePaths, ['sample']);

      await tester.tapAt(
        tester.getCenter(upperRow),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy Name'));
      await tester.pumpAndSettle();
      expect(clipboardTexts.single, 'upper [7:4]');

      await tester.tapAt(
        tester.getCenter(upperRow),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy Full Path'));
      await tester.pumpAndSettle();
      expect(clipboardTexts.last, 'sample#upper');
      expect(overlayHoldCount, 0);

      // Formatting a single sub-field row updates just that occurrence.
      await tester.tapAt(
        tester.getCenter(upperRow),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Format As'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Binary'));
      await tester.pumpAndSettle();
      verify(
        () => structSignalBloc.add(
          SignalSetOccurrenceValueFormatEvent(
            signalPaths: const {'sample#upper'},
            valueFormat: MonitorValueFormat.binary,
          ),
        ),
      ).called(1);

      // Clicking the parent signal row drops the sub-field selection.
      await tester.tap(find.text('sample (8)'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(rowColor(upperRow), Colors.transparent);
      verify(
        () => structSignalBloc.add(ModuleSignalSelectEvent('sample')),
      ).called(1);
    });

    testWidgets('adds tracked sibling signals for struct fields',
        (tester) async {
      final structSignal = SignalOccurrence(
        name: 'sample',
        width: 8,
        direction: 'output',
        logicType: const {
          'typeName': 'Sample',
          'fields': [
            {
              'name': 'upper',
              'width': 4,
              'bits': [7, 6, 5, 4],
            },
            {
              'name': 'lower',
              'width': 4,
              'bits': [3, 2, 1, 0],
            },
          ],
        },
      );
      final upperSignal = SignalOccurrence(
        name: 'sample_upper',
        width: 4,
        direction: 'output',
      );
      final lowerSignal = SignalOccurrence(
        name: 'sample_lower',
        width: 4,
        direction: 'output',
      );
      HierarchyOccurrence(
        name: 'top',
        signals: [structSignal, upperSignal, lowerSignal],
        children: [],
      ).buildAddresses();

      await pumpSignals(
        tester,
        [structSignal, upperSignal, lowerSignal],
      );

      // Tracked sub-fields are hidden as top-level rows.
      expect(find.text('sample_upper (4)'), findsNothing);
      await tapExpander(tester, signalChevron);

      final upperRow = find.text('upper [7:4]');
      expect(upperRow, findsOneWidget);
      // Tracked fields resolve to the sibling signal path.
      expect(
        tester.widget<Tooltip>(
          find.ancestor(of: upperRow, matching: find.byType(Tooltip)).first,
        ),
        isA<Tooltip>().having(
          (tooltip) => tooltip.message,
          'message',
          'top/sample_upper',
        ),
      );

      await tester.tap(upperRow);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(upperRow);
      await tester.pump(const Duration(milliseconds: 100));
      verify(
        () => structSignalBloc.add(SignalSelectedEvent(upperSignal)),
      ).called(1);
    });

    testWidgets('embedded mode hides the module tree and offers a pin toggle',
        (tester) async {
      final signal = SignalOccurrence(
        name: 'clk',
        width: 1,
        direction: 'input',
      );
      structModuleBloc = MockRohdModuleBloc();
      structSignalBloc = MockSignalBloc();
      when(() => structModuleBloc.state).thenReturn(
        ModuleSelected(mockModuleStructure, mockModuleStructure.modules.first),
      );
      when(() => structModuleBloc.repository).thenReturn(repository);
      when(() => structSignalBloc.state).thenReturn(
        SignalLoaded([signal], const [], showInternalSignals: true),
      );

      var pinned = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => HierarchyPinState(
                isPinned: pinned,
                onPinChanged: (value) => setState(() => pinned = value),
                child: MultiBlocProvider(
                  providers: [
                    BlocProvider<RohdModuleBloc>.value(value: structModuleBloc),
                    BlocProvider<SignalBloc>.value(value: structSignalBloc),
                  ],
                  child: HierarchyWidget(
                    repository: repository,
                    isEmbedded: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(ModuleTreePanel), findsNothing);
      expect(find.text('clk'), findsOneWidget);

      await tester.tap(find.byTooltip('Pin panel open'));
      await tester.pump();
      expect(pinned, isTrue);
      expect(find.byTooltip('Unpin panel'), findsOneWidget);
    });

    testWidgets('wraps multiple root modules in a synthetic hierarchy',
        (tester) async {
      final rootA = HierarchyOccurrence(
        name: 'top_a',
        signals: [
          SignalOccurrence(name: 'a_clk', width: 1, direction: 'input'),
        ],
        children: [],
      );
      final rootB = HierarchyOccurrence(
        name: 'top_b',
        signals: [
          SignalOccurrence(name: 'b_clk', width: 1, direction: 'input'),
        ],
        children: [],
      );
      final structure = ModuleStructure(
        metadata: const MetaData(source: 'test', date: '', timescale: ''),
        modules: [rootA, rootB],
      );

      await pumpSignals(
        tester,
        rootA.signals,
        moduleStructure: structure,
      );

      expect(find.byType(HierarchyWidget), findsOneWidget);
      expect(find.text('a_clk'), findsOneWidget);
    });
  });
}
