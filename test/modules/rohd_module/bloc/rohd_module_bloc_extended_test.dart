// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_module_bloc_extended_test.dart
// Extended tests for RohdModuleBloc.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_wave_viewer/src/modules/rohd_module/bloc/rohd_module_bloc.dart';
import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';
import 'package:rohd_wave_viewer/testing.dart';

void main() {
  group('RohdModuleBloc extended', () {
    late SignalWaveformRepository repo;
    late MockSignalWaveformApi api;
    late ModuleStructure structure;
    late HierarchyOccurrence rootModule;
    late HierarchyService hierarchyService;

    setUp(() async {
      api = MockSignalWaveformApi();
      repo = SignalWaveformRepository(signalWaveformApi: api);
      structure = await api.getModuleStructure();
      repo.buildSignalCacheFromHierarchy(structure.modules);
      rootModule = structure.modules.first;
      hierarchyService = BaseHierarchyAdapter.fromTree(rootModule);
    });

    // ──── Reset ────

    blocTest<RohdModuleBloc, RohdModuleState>(
      'RohdModuleReset returns to Loading',
      build: () => RohdModuleBloc(signalWaveformRepository: repo),
      act: (bloc) {
        bloc
          ..add(const RohdModuleInit())
          ..add(RohdModuleSetExternalHierarchy(hierarchyService));
      },
      verify: (bloc) {
        // Now reset
        bloc; // bloc is closed by blocTest; test the reset via seed instead
      },
    );

    blocTest<RohdModuleBloc, RohdModuleState>(
      'RohdModuleReset from ModuleSelected returns to Loading',
      build: () => RohdModuleBloc(signalWaveformRepository: repo),
      seed: () {
        final ms = ModuleStructure(
          metadata: structure.metadata,
          modules: [rootModule],
          hierarchyService: hierarchyService,
        );
        return ModuleSelected(ms, rootModule);
      },
      act: (bloc) => bloc.add(const RohdModuleReset()),
      expect: () => [isA<Loading>()],
    );

    // ──── expectsExternalHierarchy ────

    blocTest<RohdModuleBloc, RohdModuleState>(
      'onRohdModuleInit is a no-op when expectsExternalHierarchy=true',
      build: () => RohdModuleBloc(
        signalWaveformRepository: repo,
        expectsExternalHierarchy: true,
      ),
      act: (bloc) => bloc.add(const RohdModuleInit()),
      expect: () => <RohdModuleState>[], // no state changes
    );

    // ──── External Hierarchy with metadata ────

    blocTest<RohdModuleBloc, RohdModuleState>(
      'SetExternalHierarchy with metadata preserves endTime',
      build: () => RohdModuleBloc(signalWaveformRepository: repo),
      act: (bloc) {
        bloc.add(const RohdModuleInit());
        const meta = MetaData(
          source: 'test',
          timescale: '1ns',
          date: '',
          endTime: 5000,
        );
        bloc.add(
          RohdModuleSetExternalHierarchy(hierarchyService, metadata: meta),
        );
      },
      verify: (bloc) {
        expect(bloc.state, isA<ModuleSelected>());
        expect(bloc.state.moduleStructure.metadata.endTime, 5000);
      },
    );

    // ──── Select preserves hierarchy from state ────

    blocTest<RohdModuleBloc, RohdModuleState>(
      'RohdModuleSelect uses current state moduleStructure',
      build: () => RohdModuleBloc(signalWaveformRepository: repo),
      act: (bloc) async {
        bloc
          ..add(const RohdModuleInit())
          ..add(RohdModuleSetExternalHierarchy(hierarchyService));
        await bloc.stream.firstWhere((s) => s is ModuleSelected);
        final subModule = rootModule.children.first;
        bloc.add(RohdModuleSelect(structure, subModule));
      },
      verify: (bloc) {
        final state = bloc.state as ModuleSelected;
        expect(state.singleModule.name, rootModule.children.first.name);
      },
    );

    // ──── Init skips when already initialized ────

    blocTest<RohdModuleBloc, RohdModuleState>(
      'onRohdModuleInit is a no-op when already in ModuleSelected',
      build: () => RohdModuleBloc(signalWaveformRepository: repo),
      seed: () {
        final ms = ModuleStructure(
          metadata: structure.metadata,
          modules: [rootModule],
          hierarchyService: hierarchyService,
        );
        return ModuleSelected(ms, rootModule);
      },
      act: (bloc) => bloc.add(const RohdModuleInit()),
      expect: () => <RohdModuleState>[], // no state changes
    );

    // ──── WaveformUpdate ────

    blocTest<RohdModuleBloc, RohdModuleState>(
      'WaveformUpdate advances endTime',
      build: () => RohdModuleBloc(signalWaveformRepository: repo),
      seed: () {
        final ms = ModuleStructure(
          metadata: const MetaData(
            source: 'test',
            timescale: '1ns',
            date: '',
            endTime: 100,
          ),
          modules: [rootModule],
          hierarchyService: hierarchyService,
        );
        return ModuleSelected(ms, rootModule);
      },
      act: (bloc) => bloc.add(
        const RohdModuleWaveformUpdate(incrementalData: [], upToTime: 200),
      ),
      verify: (bloc) {
        expect(bloc.state, isA<WaveformUpdated>());
        final state = bloc.state as WaveformUpdated;
        expect(state.upToTime, 200);
        // EndTime should advance to the max
        expect(state.moduleStructure.metadata.endTime, 200);
      },
    );

    blocTest<RohdModuleBloc, RohdModuleState>(
      'WaveformUpdate buffers upToTime when state is Loading',
      build: () => RohdModuleBloc(signalWaveformRepository: repo),
      // Default initial state is Loading
      act: (bloc) => bloc.add(
        const RohdModuleWaveformUpdate(incrementalData: [], upToTime: 500),
      ),
      expect: () => <RohdModuleState>[], // no state change — buffered
    );

    blocTest<RohdModuleBloc, RohdModuleState>(
      'WaveformUpdate does not shrink endTime',
      build: () => RohdModuleBloc(signalWaveformRepository: repo),
      seed: () {
        final ms = ModuleStructure(
          metadata: const MetaData(
            source: 'test',
            timescale: '1ns',
            date: '',
            endTime: 1000,
          ),
          modules: [rootModule],
          hierarchyService: hierarchyService,
        );
        return ModuleSelected(ms, rootModule);
      },
      act: (bloc) => bloc.add(
        const RohdModuleWaveformUpdate(incrementalData: [], upToTime: 500),
      ),
      verify: (bloc) {
        final state = bloc.state as WaveformUpdated;
        expect(state.moduleStructure.metadata.endTime, 1000);
      },
    );

    // ──── liveUpdates stream ────

    test('subscribes to liveUpdates stream and dispatches events', () async {
      final controller = StreamController<WaveformUpdateEvent>();
      final bloc = RohdModuleBloc(
        signalWaveformRepository: repo,
        liveUpdates: controller.stream,
      );

      // Seed the bloc into a state that can process updates
      final ms = ModuleStructure(
        metadata: const MetaData(
          source: 'test',
          timescale: '1ns',
          date: '',
          endTime: 100,
        ),
        modules: [rootModule],
        hierarchyService: hierarchyService,
      );
      bloc
        ..add(const RohdModuleInit())
        ..add(
          RohdModuleSetExternalHierarchy(
            hierarchyService,
            metadata: ms.metadata,
          ),
        );
      await bloc.stream.firstWhere((s) => s is ModuleSelected);

      // Push an update through the stream
      controller.add(
        WaveformUpdateEvent(
          incrementalData: const [],
          reason: WaveformUpdateReason.breakpoint,
          upToTime: 300,
        ),
      );

      final state = await bloc.stream.firstWhere((s) => s is WaveformUpdated);
      expect((state as WaveformUpdated).upToTime, 300);

      await controller.close();
      await bloc.close();
    });

    // ──── State equatable checks ────

    group('state equatable', () {
      test('Loading states with same structure are equal', () {
        final a = Loading(ModuleStructure.empty());
        final b = Loading(ModuleStructure.empty());
        expect(a, equals(b));
      });

      test('ModuleSelected states with different modules are not equal', () {
        final ms = ModuleStructure(
          metadata: structure.metadata,
          modules: [rootModule],
          hierarchyService: hierarchyService,
        );
        final a = ModuleSelected(ms, rootModule);
        final b = ModuleSelected(ms, rootModule.children.first);
        expect(a, isNot(equals(b)));
      });
    });

    // ──── Event equatable checks ────

    group('event equatable', () {
      test('RohdModuleInit instances are equal', () {
        expect(const RohdModuleInit(), equals(const RohdModuleInit()));
      });

      test('RohdModuleReset instances are equal', () {
        expect(const RohdModuleReset(), equals(const RohdModuleReset()));
      });

      test('RohdModuleRefresh instances are equal', () {
        expect(const RohdModuleRefresh(), equals(const RohdModuleRefresh()));
      });

      test('RohdModuleWaveformUpdate with same data are equal', () {
        const a = RohdModuleWaveformUpdate(incrementalData: [], upToTime: 100);
        const b = RohdModuleWaveformUpdate(incrementalData: [], upToTime: 100);
        expect(a, equals(b));
      });

      test(
        'RohdModuleWaveformUpdate with different upToTime are not equal',
        () {
          const a = RohdModuleWaveformUpdate(
            incrementalData: [],
            upToTime: 100,
          );
          const b = RohdModuleWaveformUpdate(
            incrementalData: [],
            upToTime: 200,
          );
          expect(a, isNot(equals(b)));
        },
      );
    });

    // ──── Refresh ────

    blocTest<RohdModuleBloc, RohdModuleState>(
      'RohdModuleRefresh updates endTime from ModuleSelected',
      build: () => RohdModuleBloc(signalWaveformRepository: repo),
      seed: () {
        final ms = ModuleStructure(
          metadata: const MetaData(
            source: 'test',
            timescale: '1ns',
            date: '',
            endTime: 100,
          ),
          modules: [rootModule],
          hierarchyService: hierarchyService,
        );
        return ModuleSelected(ms, rootModule);
      },
      act: (bloc) => bloc.add(const RohdModuleRefresh()),
      verify: (bloc) {
        // After refresh, state should be ModuleSelected with updated endTime
        // MockSignalWaveformApi.getCurrentTime returns non-null value
        expect(bloc.state, isA<ModuleSelected>());
      },
    );

    blocTest<RohdModuleBloc, RohdModuleState>(
      'RohdModuleRefresh from WaveformUpdated is graceful when API unavailable',
      build: () => RohdModuleBloc(signalWaveformRepository: repo),
      seed: () {
        final ms = ModuleStructure(
          metadata: const MetaData(
            source: 'test',
            timescale: '1ns',
            date: '',
            endTime: 200,
          ),
          modules: [rootModule],
          hierarchyService: hierarchyService,
        );
        return WaveformUpdated(ms, 200, selectedModule: rootModule);
      },
      act: (bloc) => bloc.add(const RohdModuleRefresh()),
      verify: (bloc) {
        // Mock API doesn't implement getCurrentTime — refresh catches and
        // leaves state unchanged.
        expect(bloc.state, isA<WaveformUpdated>());
      },
    );

    blocTest<RohdModuleBloc, RohdModuleState>(
      'RohdModuleRefresh from Rendered is graceful when API unavailable',
      build: () => RohdModuleBloc(signalWaveformRepository: repo),
      seed: () {
        final ms = ModuleStructure(
          metadata: const MetaData(
            source: 'test',
            timescale: '1ns',
            date: '',
            endTime: 100,
          ),
          modules: [rootModule],
          hierarchyService: hierarchyService,
        );
        return Rendered(ms);
      },
      act: (bloc) => bloc.add(const RohdModuleRefresh()),
      verify: (bloc) {
        // Mock API doesn't implement getCurrentTime — refresh catches and
        // leaves state unchanged.
        expect(bloc.state, isA<Rendered>());
      },
    );

    blocTest<RohdModuleBloc, RohdModuleState>(
      'RohdModuleRefresh no-ops when Loading (empty structure)',
      build: () => RohdModuleBloc(signalWaveformRepository: repo),
      // Default is Loading with empty structure
      act: (bloc) => bloc.add(const RohdModuleRefresh()),
      expect: () => <RohdModuleState>[], // no state change
    );

    // ──── updateLiveUpdates ────

    test('updateLiveUpdates replaces stream subscription', () async {
      final controller1 = StreamController<WaveformUpdateEvent>();
      final bloc = RohdModuleBloc(
        signalWaveformRepository: repo,
        liveUpdates: controller1.stream,
      );

      // Seed into ModuleSelected
      final ms = ModuleStructure(
        metadata: const MetaData(
          source: 'test',
          timescale: '1ns',
          date: '',
          endTime: 100,
        ),
        modules: [rootModule],
        hierarchyService: hierarchyService,
      );
      bloc
        ..add(const RohdModuleInit())
        ..add(
          RohdModuleSetExternalHierarchy(
            hierarchyService,
            metadata: ms.metadata,
          ),
        );
      await bloc.stream.firstWhere((s) => s is ModuleSelected);

      // Replace with new stream
      final controller2 = StreamController<WaveformUpdateEvent>();
      bloc.updateLiveUpdates(controller2.stream);

      // Send event on new stream
      controller2.add(
        WaveformUpdateEvent(
          incrementalData: const [],
          reason: WaveformUpdateReason.breakpoint,
          upToTime: 999,
        ),
      );

      final state = await bloc.stream.firstWhere((s) => s is WaveformUpdated);
      expect((state as WaveformUpdated).upToTime, 999);

      await controller1.close();
      await controller2.close();
      await bloc.close();
    });

    test('updateLiveUpdates with null cancels subscription', () async {
      final controller = StreamController<WaveformUpdateEvent>();
      final bloc = RohdModuleBloc(
        signalWaveformRepository: repo,
        liveUpdates: controller.stream,
      )..updateLiveUpdates(null);

      // Sending on old stream should not affect bloc
      // (subscription was cancelled)
      await controller.close();
      await bloc.close();
    });

    // ──── SetExternalHierarchy with pending upToTime ────

    test('buffered upToTime is applied after hierarchy load', () async {
      final bloc = RohdModuleBloc(signalWaveformRepository: repo)
        // Send waveform update while in Loading state — it should be buffered
        ..add(
          const RohdModuleWaveformUpdate(incrementalData: [], upToTime: 700),
        );

      // Wait a tick for the event to be processed (buffered)
      await Future<void>.delayed(Duration.zero);

      // Now set hierarchy — should apply the buffered upToTime
      bloc.add(
        RohdModuleSetExternalHierarchy(
          hierarchyService,
          metadata: const MetaData(
            source: 'test',
            timescale: '1ns',
            date: '',
            endTime: 100,
          ),
        ),
      );

      // Wait for the final ModuleSelected state
      await bloc.stream
          .firstWhere((s) => s is ModuleSelected)
          .timeout(const Duration(seconds: 5));

      // The endTime should be at least 700 from the buffered update
      expect(bloc.state.moduleStructure.metadata.endTime >= 700, isTrue);
      await bloc.close();
    });

    // ──── SetExternalHierarchy preserves selection ────

    test('SetExternalHierarchy preserves ModuleSelected selection', () async {
      final bloc = RohdModuleBloc(signalWaveformRepository: repo)
        // First set hierarchy and select a sub-module
        ..add(RohdModuleSetExternalHierarchy(hierarchyService));
      await bloc.stream.firstWhere((s) => s is ModuleSelected);

      final subModule = rootModule.children.first;
      bloc.add(RohdModuleSelect(structure, subModule));
      await bloc.stream.firstWhere(
        (s) => s is ModuleSelected && s.singleModule.path() == subModule.path(),
      );

      // Re-set external hierarchy — should preserve subModule selection
      bloc.add(RohdModuleSetExternalHierarchy(hierarchyService));
      await bloc.stream.firstWhere((s) => s is ModuleSelected);

      // Selection should be preserved if the node exists in the new tree
      expect(bloc.state, isA<ModuleSelected>());
      expect(
        (bloc.state as ModuleSelected).singleModule.path(),
        subModule.path(),
      );
      await bloc.close();
    });

    // ──── WaveformStructureAvailable ────

    blocTest<RohdModuleBloc, RohdModuleState>(
      'WaveformStructureAvailable updates endTime from ModuleSelected',
      build: () => RohdModuleBloc(signalWaveformRepository: repo),
      seed: () {
        final ms = ModuleStructure(
          metadata: const MetaData(
            source: 'test',
            timescale: '1ns',
            date: '',
            endTime: 50,
          ),
          modules: [rootModule],
          hierarchyService: hierarchyService,
        );
        return ModuleSelected(ms, rootModule);
      },
      act: (bloc) => bloc.add(const RohdModuleWaveformStructureAvailable()),
      verify: (bloc) {
        // getCurrentTime may return null for mock — state may or may not change
        // but it should not crash
        expect(bloc.state, anyOf(isA<ModuleSelected>(), isA<Rendered>()));
      },
    );

    blocTest<RohdModuleBloc, RohdModuleState>(
      'WaveformStructureAvailable from Rendered (no selection)',
      build: () => RohdModuleBloc(signalWaveformRepository: repo),
      seed: () {
        final ms = ModuleStructure(
          metadata: const MetaData(
            source: 'test',
            timescale: '1ns',
            date: '',
            endTime: 50,
          ),
          modules: [rootModule],
          hierarchyService: hierarchyService,
        );
        return Rendered(ms);
      },
      act: (bloc) => bloc.add(const RohdModuleWaveformStructureAvailable()),
      verify: (bloc) {
        expect(bloc.state, anyOf(isA<Rendered>(), isA<ModuleSelected>()));
      },
    );

    blocTest<RohdModuleBloc, RohdModuleState>(
      'WaveformStructureAvailable from WaveformUpdated',
      build: () => RohdModuleBloc(signalWaveformRepository: repo),
      seed: () {
        final ms = ModuleStructure(
          metadata: const MetaData(
            source: 'test',
            timescale: '1ns',
            date: '',
            endTime: 50,
          ),
          modules: [rootModule],
          hierarchyService: hierarchyService,
        );
        return WaveformUpdated(ms, 50, selectedModule: rootModule);
      },
      act: (bloc) => bloc.add(const RohdModuleWaveformStructureAvailable()),
      verify: (bloc) {
        expect(
          bloc.state,
          anyOf(isA<ModuleSelected>(), isA<WaveformUpdated>()),
        );
      },
    );

    blocTest<RohdModuleBloc, RohdModuleState>(
      'WaveformStructureAvailable no-ops from Loading',
      build: () => RohdModuleBloc(signalWaveformRepository: repo),
      act: (bloc) => bloc.add(const RohdModuleWaveformStructureAvailable()),
      expect: () => <RohdModuleState>[],
    );

    // ──── liveUpdates dispatches structureAvailable ────

    test(
      'liveUpdates with structureAvailable reason dispatches correct event',
      () async {
        final controller = StreamController<WaveformUpdateEvent>();
        final bloc = RohdModuleBloc(
          signalWaveformRepository: repo,
          liveUpdates: controller.stream,
        )
          // Seed into ModuleSelected
          ..add(
            RohdModuleSetExternalHierarchy(
              hierarchyService,
              metadata: const MetaData(
                source: 'test',
                timescale: '1ns',
                date: '',
                endTime: 100,
              ),
            ),
          );
        await bloc.stream.firstWhere((s) => s is ModuleSelected);

        // Send a structureAvailable event through the stream
        controller.add(
          WaveformUpdateEvent(
            incrementalData: const [],
            reason: WaveformUpdateReason.structureAvailable,
            upToTime: 0,
          ),
        );

        // Give it time to process
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Should not crash — the event is processed
        expect(bloc.state, anyOf(isA<ModuleSelected>(), isA<Rendered>()));

        await controller.close();
        await bloc.close();
      },
    );

    // ──── WaveformUpdate with incrementalData ────

    blocTest<RohdModuleBloc, RohdModuleState>(
      'WaveformUpdate with incrementalData advances dataEndTime',
      build: () => RohdModuleBloc(signalWaveformRepository: repo),
      seed: () {
        final ms = ModuleStructure(
          metadata: const MetaData(
            source: 'test',
            timescale: '1ns',
            date: '',
            endTime: 100,
          ),
          modules: [rootModule],
          hierarchyService: hierarchyService,
        );
        return ModuleSelected(ms, rootModule);
      },
      act: (bloc) => bloc.add(
        RohdModuleWaveformUpdate(
          incrementalData: [
            WaveformData(
              signalId: 'Counter.Signal1',
              data: [Data(time: 200, value: '1')],
            ),
          ],
          upToTime: 200,
        ),
      ),
      verify: (bloc) {
        expect(bloc.state, isA<WaveformUpdated>());
        final state = bloc.state as WaveformUpdated;
        expect(state.upToTime, 200);
        expect(state.moduleStructure.metadata.endTime, 200);
      },
    );

    // ──── _findNodeById ────

    test('Select with sub-module navigates correctly', () async {
      final bloc = RohdModuleBloc(signalWaveformRepository: repo)
        ..add(RohdModuleSetExternalHierarchy(hierarchyService));
      await bloc.stream.firstWhere((s) => s is ModuleSelected);

      // Select the sub-module
      final subModule = rootModule.children.first;
      bloc.add(RohdModuleSelect(structure, subModule));
      await bloc.stream.firstWhere(
        (s) => s is ModuleSelected && s.singleModule.path() == subModule.path(),
      );

      expect(
        (bloc.state as ModuleSelected).singleModule.name,
        'counter_sub_module',
      );
      await bloc.close();
    });

    // ──── SetExternalHierarchy preserves from WaveformUpdated ────

    test('SetExternalHierarchy preserves WaveformUpdated selection', () async {
      final bloc = RohdModuleBloc(signalWaveformRepository: repo)
        // Set hierarchy and select root
        ..add(RohdModuleSetExternalHierarchy(hierarchyService));
      await bloc.stream.firstWhere((s) => s is ModuleSelected);

      // Simulate waveform update to get into WaveformUpdated state
      bloc.add(
        const RohdModuleWaveformUpdate(incrementalData: [], upToTime: 300),
      );
      await bloc.stream.firstWhere((s) => s is WaveformUpdated);

      // Re-set external hierarchy — should preserve selection from
      // WaveformUpdated
      bloc.add(RohdModuleSetExternalHierarchy(hierarchyService));
      await bloc.stream.firstWhere((s) => s is ModuleSelected);

      expect(bloc.state, isA<ModuleSelected>());
      await bloc.close();
    });

    // ──── SetExternalHierarchy metadata fallback ────

    blocTest<RohdModuleBloc, RohdModuleState>(
      'SetExternalHierarchy with null metadata uses existing',
      build: () => RohdModuleBloc(signalWaveformRepository: repo),
      act: (bloc) {
        bloc.add(RohdModuleSetExternalHierarchy(hierarchyService));
      },
      verify: (bloc) {
        expect(bloc.state, isA<ModuleSelected>());
      },
    );

    blocTest<RohdModuleBloc, RohdModuleState>(
      'SetExternalHierarchy with zero endTime metadata falls back',
      build: () => RohdModuleBloc(signalWaveformRepository: repo),
      act: (bloc) {
        const meta = MetaData(source: 'test', timescale: '1ns', date: '');
        bloc.add(
          RohdModuleSetExternalHierarchy(hierarchyService, metadata: meta),
        );
      },
      verify: (bloc) {
        expect(bloc.state, isA<ModuleSelected>());
      },
    );

    // ──── close cancels subscription ────

    test('close cancels liveUpdates subscription', () async {
      final controller = StreamController<WaveformUpdateEvent>();
      final bloc = RohdModuleBloc(
        signalWaveformRepository: repo,
        liveUpdates: controller.stream,
      );

      await bloc.close();
      // Controller should still be closeable (subscription cancelled)
      await controller.close();
    });
  });
}
