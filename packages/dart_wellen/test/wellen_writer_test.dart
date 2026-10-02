// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// wellen_writer_test.dart
// Regression tests for safe writer opening and VCD hierarchy generation.
//
// 2026 October
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

@TestOn('vm')
library;

import 'dart:io';

import 'package:dart_wellen/dart_wellen.dart';
import 'package:dart_wellen/dart_wellen_io.dart';
import 'package:test/test.dart';

void main() {
  late Directory outputDirectory;
  late WellenWriter writer;

  setUp(() {
    outputDirectory = Directory('.dart_tool/test_output/wellen_writer');
    if (outputDirectory.existsSync()) {
      outputDirectory.deleteSync(recursive: true);
    }
    outputDirectory.createSync(recursive: true);
    writer = WellenWriter();
  });

  tearDown(() async {
    await writer.close();
    if (outputDirectory.existsSync()) {
      outputDirectory.deleteSync(recursive: true);
    }
  });

  test('unsupported FST preserves its destination and leaves no open sink',
      () async {
    const originalContents = 'existing waveform data\n';
    final destination = File('${outputDirectory.path}/existing.fst');
    await destination.writeAsString(originalContents);

    await expectLater(
      writer.open(destination.path, format: WaveFormat.fst),
      throwsA(
        isA<WellenWriterException>().having(
          (error) => error.message,
          'message',
          'FST writing not yet implemented',
        ),
      ),
    );

    expect(await destination.readAsString(), originalContents);
    expect(writer.isOpen, isFalse);
    expect(writer.format, WaveFormat.vcd);

    final retryDestination = File('${outputDirectory.path}/retry.vcd');
    await writer.open(
      retryDestination.path,
      date: '2026-10-02',
      version: 'WellenWriter test',
    );
    writer.writeHeader();
    await writer.close();

    expect(writer.isOpen, isFalse);
    expect(
      await retryDestination.readAsString(),
      contains(r'$enddefinitions $end'),
    );
  });

  test('filesystem open failure leaves the writer reusable', () async {
    final missingParentPath = '${outputDirectory.path}/missing/output.vcd';

    await expectLater(
      writer.open(missingParentPath),
      throwsA(isA<FileSystemException>()),
    );
    expect(writer.isOpen, isFalse);

    final retryDestination = File('${outputDirectory.path}/after_failure.vcd');
    await writer.open(
      retryDestination.path,
      date: '2026-10-02',
      version: 'WellenWriter test',
    );
    writer.writeHeader();
    await writer.close();

    expect(writer.isOpen, isFalse);
    expect(retryDestination.existsSync(), isTrue);
  });

  test('nested and sibling canonical paths produce valid VCD scopes', () async {
    final topSignal = SignalOccurrence(name: 'top_flag', width: 1);
    final leftSignal = SignalOccurrence(name: 'left_value', width: 2);
    final nestedSignal = SignalOccurrence(name: 'nested_value', width: 3);
    final rightSignal = SignalOccurrence(name: 'right_value', width: 4);
    HierarchyOccurrence(
      name: 'top',
      signals: [topSignal],
      children: [
        HierarchyOccurrence(
          name: 'left',
          signals: [leftSignal],
          children: [
            HierarchyOccurrence(
              name: 'nested',
              signals: [nestedSignal],
            ),
          ],
        ),
        HierarchyOccurrence(
          name: 'right',
          signals: [rightSignal],
        ),
      ],
    )..buildAddresses();
    final expectedSignalPaths = {
      'top/top_flag',
      'top/left/left_value',
      'top/left/nested/nested_value',
      'top/right/right_value',
    };

    expect(
      {
        topSignal.path(),
        leftSignal.path(),
        nestedSignal.path(),
        rightSignal.path(),
      },
      expectedSignalPaths,
    );

    final destination = File('${outputDirectory.path}/hierarchy.vcd');
    await writer.open(
      destination.path,
      date: '2026-10-02',
      version: 'WellenWriter test',
    );
    writer.registerSignals([
      rightSignal,
      nestedSignal,
      topSignal,
      leftSignal,
    ]);
    writer.writeHeader();
    writer.writeValues(0, {
      topSignal.path(): '0',
      leftSignal.path(): '01',
      nestedSignal.path(): '010',
      rightSignal.path(): '0011',
    });
    await writer.close();

    final vcd = await destination.readAsString();
    expect(_declaredSignalPaths(vcd), expectedSignalPaths);
    expect(
      vcd
          .split('\n')
          .map((line) => line.trim())
          .where(
            (line) => line.startsWith(r'$scope ') || line == r'$upscope $end',
          )
          .toList(),
      [
        r'$scope module top $end',
        r'$scope module left $end',
        r'$scope module nested $end',
        r'$upscope $end',
        r'$upscope $end',
        r'$scope module right $end',
        r'$upscope $end',
        r'$upscope $end',
      ],
    );

    await WellenReader.init();
    final reader = WellenReader();
    try {
      final metadata = await reader.loadFile(destination.path);
      expect(metadata.format, WaveFormat.vcd);

      final structure = await reader.getStructure();
      final parsedTop = structure.modules.singleWhere(
        (module) => module.name == 'top',
      )..buildAddresses();
      expect(structure.allSignalIds, containsAll(expectedSignalPaths));
      expect(parsedTop.signals.map((signal) => signal.name), ['top_flag']);
      expect(
        parsedTop.children.map((module) => module.name),
        ['left', 'right'],
      );
      expect(
        parsedTop.children
            .singleWhere((module) => module.name == 'left')
            .children
            .single
            .name,
        'nested',
      );
    } finally {
      await reader.close();
    }
  });
}

Set<String> _declaredSignalPaths(String vcd) {
  final scopes = <String>[];
  final signalPaths = <String>{};
  var foundEndDefinitions = false;

  for (final rawLine in vcd.split('\n')) {
    final line = rawLine.trim();
    if (line.startsWith(r'$scope ')) {
      final match = RegExp(
        r'^\$scope\s+\S+\s+(\S+)\s+\$end$',
      ).firstMatch(line);
      expect(match, isNotNull, reason: 'Malformed VCD scope: $line');
      if (match != null) {
        scopes.add(match.group(1)!);
      }
    } else if (line == r'$upscope $end') {
      expect(scopes, isNotEmpty, reason: 'VCD scope stack underflow');
      if (scopes.isNotEmpty) {
        scopes.removeLast();
      }
    } else if (line.startsWith(r'$var ')) {
      final match = RegExp(
        r'^\$var\s+\S+\s+\d+\s+\S+\s+(\S+)\s+\$end$',
      ).firstMatch(line);
      expect(match, isNotNull, reason: 'Malformed VCD variable: $line');
      if (match != null) {
        signalPaths.add([...scopes, match.group(1)!].join('/'));
      }
    } else if (line == r'$enddefinitions $end') {
      expect(scopes, isEmpty, reason: 'VCD scopes must be balanced');
      foundEndDefinitions = true;
    }
  }

  expect(foundEndDefinitions, isTrue);
  expect(scopes, isEmpty, reason: 'VCD scopes must be balanced');
  return signalPaths;
}
