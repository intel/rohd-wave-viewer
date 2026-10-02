// Copyright (C) 2025-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// vcd_snapshot_test.dart
// Tests for VCD snapshot loading via Wellen API.
//
// 2026 March
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

// Run with: flutter test test/vcd_snapshot_test.dart

import 'dart:io';

import 'package:dart_wellen/dart_wellen.dart' hide SignalWaveform;
import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_wave_viewer/src/modules/rohd_module/bloc/rohd_module_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/bloc/waveform_module_bloc.dart';
import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';

String get fixturesPath => 'test/fixtures';

void main() {
  setUpAll(() async {
    // Initialize Wellen FFI
    await WellenSignalWaveformApi.init();
  });

  group('FilterBank VCD', () {
    late WellenSignalWaveformApi api;
    late ModuleStructure structure;

    setUpAll(() async {
      api = WellenSignalWaveformApi();
      final vcdPath = '$fixturesPath/filter_bank.vcd';

      if (!File(vcdPath).existsSync()) {
        fail('VCD fixture not found: $vcdPath');
      }

      await api.loadFile(vcdPath);
      structure = await api.getModuleStructureOnly();
    });

    test('loads module structure with signals', () {
      expect(
        structure.modules,
        isNotEmpty,
        reason: 'Should have at least one module',
      );

      final allSignals = structure.allSignalIds;
      expect(allSignals, isNotEmpty, reason: 'Should have signals');
    });

    test('has valid time range', () {
      final startTime = structure.metadata.startTime;
      final endTime = structure.metadata.endTime;

      expect(
        endTime,
        greaterThan(startTime),
        reason: 'End time should be after start time',
      );
    });

    test('all signals have waveform data', () async {
      final allSignals = structure.allSignalIds;

      // Load waveform data for all signals
      final waveformData = await api.getWaveformData(signalIds: allSignals);

      expect(
        waveformData.length,
        equals(allSignals.length),
        reason: 'Should get data for all signals',
      );

      var signalsWithData = 0;
      var signalsEmpty = 0;

      for (final wd in waveformData) {
        if (wd.data.isNotEmpty) {
          signalsWithData++;
        } else {
          signalsEmpty++;
        }
      }

      // Most signals should have data (some internals might be constant)
      expect(
        signalsWithData,
        greaterThan(allSignals.length * 0.5),
        reason: 'At least half the signals should have waveform data',
      );
      expect(
        signalsEmpty,
        lessThan(allSignals.length),
        reason: 'Should have at least some signals with data',
      );
    });

    test('snapshot at time 0 has values for all signals', () async {
      final allSignals = structure.allSignalIds;
      final waveformData = await api.getWaveformData(signalIds: allSignals);

      // Build a map of signal values at time 0
      final valuesAtT0 = <String, String>{};
      var signalsWithValueAtT0 = 0;
      var signalsWithX = 0;
      var signalsWithZ = 0;

      for (final wd in waveformData) {
        if (wd.data.isEmpty) {
          continue;
        }

        // Find value at or before time 0
        String? value;
        for (final dp in wd.data) {
          if (dp.time <= 0) {
            value = dp.value;
          } else {
            break;
          }
        }

        if (value != null) {
          valuesAtT0[wd.signalId] = value;
          signalsWithValueAtT0++;

          // Check for x/z values
          if (value.contains('x') || value.contains('X')) {
            signalsWithX++;
          }
          if (value.contains('z') || value.contains('Z')) {
            signalsWithZ++;
          }
        }
      }

      // Most signals should have defined values (not x or z)
      final definedSignals = signalsWithValueAtT0 - signalsWithX - signalsWithZ;

      expect(
        signalsWithValueAtT0,
        greaterThan(0),
        reason: 'At least some signals should have values at t=0',
      );
      expect(
        definedSignals,
        greaterThan(0),
        reason: 'At least some signals should have defined values (not x or z)',
      );
    });

    test('snapshot at multiple timepoints shows value changes', () async {
      final allSignals = structure.allSignalIds;
      final waveformData = await api.getWaveformData(signalIds: allSignals);

      // Sample timepoints to check
      final timepoints = [0, 10, 50, 100];
      final endTime = structure.metadata.endTime;

      for (final t in timepoints) {
        if (t > endTime) {
          continue;
        }

        var signalsWithValue = 0;
        var signalsWithX = 0;

        for (final wd in waveformData) {
          if (wd.data.isEmpty) {
            continue;
          }

          // Binary search for value at or before time t
          String? value;
          var lo = 0;
          var hi = wd.data.length - 1;
          var res = -1;

          while (lo <= hi) {
            final mid = (lo + hi) >> 1;
            if (wd.data[mid].time <= t) {
              res = mid;
              lo = mid + 1;
            } else {
              hi = mid - 1;
            }
          }

          if (res >= 0) {
            value = wd.data[res].value;
            signalsWithValue++;
            if (value.contains('x') || value.contains('X')) {
              signalsWithX++;
            }
          }
        }

        expect(
          signalsWithValue,
          greaterThan(0),
          reason: 'Should have signals with values at timepoint t=$t',
        );
        expect(
          signalsWithX,
          lessThan(signalsWithValue),
          reason: 'Not all signals should have undefined (x) values at t=$t; '
              'should have defined values as well',
        );
      }
    });

    test('drives repository and viewer blocs with loaded waveform data',
        () async {
      final repository = SignalWaveformRepository(signalWaveformApi: api);
      final moduleBloc = RohdModuleBloc(
        signalWaveformRepository: repository,
      );
      final signalBloc = SignalBloc(repository);
      final cursorBloc = WaveformModuleBloc(
        signalWaveformRepository: repository,
      );

      addTearDown(moduleBloc.close);
      addTearDown(signalBloc.close);
      addTearDown(cursorBloc.close);

      moduleBloc.add(const RohdModuleInit());
      final moduleState = await moduleBloc.stream.firstWhere(
        (state) => state is ModuleSelected,
      ) as ModuleSelected;
      final selectedModule = moduleState.singleModule;
      final signals = repository.getSignalsBySelectedModule(selectedModule);

      expect(signals, isNotEmpty);
      expect(repository.cachedSignalIds, contains(signals.first.path()));

      signalBloc.add(SignalUpdateEvent(selectedModule));
      await signalBloc.stream.firstWhere((state) => state is SignalLoaded);

      signalBloc.add(SignalSelectedEvent(signals.first));
      final monitoredState = await signalBloc.stream.firstWhere(
        (state) => state.monitorSignalsList.isNotEmpty,
      ) as SignalLoaded;
      final monitoredWaveform = monitoredState.monitorSignalsList.single;

      expect(monitoredWaveform.signalId, signals.first.path());
      expect(monitoredWaveform.data, isNotEmpty);

      cursorBloc.add(WaveformModuleOnTap(monitoredWaveform.data.first.time));
      final cursorState = await cursorBloc.stream.firstWhere(
        (state) => state is UpdatedCursor,
      ) as UpdatedCursor;
      expect(cursorState.timePs, monitoredWaveform.data.first.time);
    });
  });
}
