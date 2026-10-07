// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_data_service_test.dart
// Tests for the SignalDataService abstraction and RepositorySignalDataService
// implementation.
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';
import 'package:rohd_wave_viewer/testing.dart';

void main() {
  group('SignalDataService', () {
    late SignalWaveformRepository repository;
    late SignalDataService service;
    late ModuleStructure structure;

    setUp(() async {
      // Create repository with mock API
      final mockApi = MockSignalWaveformApi();
      repository = SignalWaveformRepository(signalWaveformApi: mockApi);

      // Load module structure from mock API (hierarchy comes from
      // rohd_hierarchy, not the repository).
      structure = await mockApi.getModuleStructure();
      repository.buildSignalCacheFromHierarchy(structure.modules);

      // Create service using repository
      service = RepositorySignalDataService(repository);
    });

    test('Service should fetch waveform data for a Port', () async {
      // Get first module and its first port
      expect(structure.modules, isNotEmpty);
      final module = structure.modules.first;
      expect(module.ports, isNotEmpty);
      final port = module.ports.first;

      // Fetch waveform data using service
      final waveData = await service.getSignalData(port);

      // Verify WaveData contains the Port
      expect(waveData.port, equals(port));
      expect(waveData.signalName, equals(port.name));
      expect(waveData.signalDirection, equals(port.direction));
      expect(waveData.signalWidth, equals(port.width));
      expect(waveData.signalType, equals('wire'));

      // Verify metadata is present
      expect(waveData.metadata, isNotNull);
      expect(waveData.metadata!['source'], equals('repository'));
    });

    test('Service should return empty data for unknown Port', () async {
      // Create a Port with ID that doesn't exist
      final unknownPort = SignalOccurrence(
        name: 'unknown_signal',
        direction: 'input',
        width: 1,
      );

      // Fetch waveform data
      final waveData = await service.getSignalData(unknownPort);

      // Verify it returns empty data, not error
      expect(waveData.port, equals(unknownPort));
      expect(waveData.data, isEmpty);
      expect(waveData.metadata!['cached'], equals(false));
    });

    test('Service should get ports for a module', () {
      final module = structure.modules.first;
      final ports = service.getPortsForModule(module);

      // Should return module's ports
      expect(ports, equals(module.ports));
      expect(ports, isNotEmpty);
    });

    test('WaveData should expose Port properties', () async {
      final module = structure.modules.first;
      final port = module.ports.first;

      final waveData = await service.getSignalData(port);

      // Verify WaveData exposes all Port properties
      expect(waveData.signalName, isNotEmpty);
      expect(waveData.signalDirection, isNotEmpty);
      expect(waveData.signalWidth, isPositive);
      expect(waveData.signalType, isNotEmpty);
    });

    test('Service should work with multiple signals', () async {
      // Get first module
      final module = structure.modules.first;
      expect(module.ports, isNotEmpty);

      // Fetch data for all ports in the module
      final waveDatas = <WaveData>[];
      for (final port in module.ports) {
        final waveData = await service.getSignalData(port);
        waveDatas.add(waveData);
      }

      // Verify all signals were fetched
      expect(waveDatas.length, equals(module.ports.length));

      // Verify each WaveData has correct Port
      for (var i = 0; i < waveDatas.length; i++) {
        expect(waveDatas[i].port, equals(module.ports[i]));
      }
    });
  });
}
