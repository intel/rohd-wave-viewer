// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// struct_scope_test.dart
// Validates that FST `$scope struct` entries are surfaced as expandable
// struct *signals* in the parent occurrence (with named sub-fields), and are
// NOT exposed as child hierarchy instances.
//
// Fixture: fp_adder_struct.fst (ROHD FloatingPointAdderSinglePath_E4M4).
// Top module `floatingpoint_adder_singlepath` contains struct scopes
// `a`, `b`, `sum`, `outSum`, each with fields:
//   mantissa(4) [bits 0..3], exponent(4) [bits 4..7], sign(1) [bit 8]  → width 9
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:dart_wellen/dart_wellen.dart';
import 'package:test/test.dart';

String get fixturesPath => 'test/fixtures';
const _fixture = 'fp_adder_struct.fst';
const _filterBankFixture = 'test/fixtures/filter_bank.fst';
const _topName = 'floatingpoint_adder_singlepath';
const _structNames = {'a', 'b', 'sum', 'outSum'};

void main() {
  setUpAll(() async {
    await WellenSignalWaveformApi.init();
  });

  test('struct scopes become expandable struct signals, not child instances',
      () async {
    final filePath = '$fixturesPath/$_fixture';

    final api = WellenSignalWaveformApi();
    await api.loadFile(filePath);
    final structure = await api.getModuleStructureOnly();

    final top = structure.modules.firstWhere(
      (m) => m.name == _topName,
      orElse: () => structure.firstModuleWithSignals!,
    );

    // (1) struct scopes must NOT appear as child instances.
    final childNames = top.children.map((c) => c.name).toSet();
    for (final name in _structNames) {
      expect(childNames, isNot(contains(name)),
          reason: 'struct "$name" should not be a child instance');
    }

    // (2) struct scopes appear as struct SignalOccurrence entries.
    final signalsByName = {for (final s in top.signals) s.name: s};
    for (final name in _structNames) {
      final sig = signalsByName[name];
      expect(sig, isNotNull, reason: 'struct signal "$name" missing');
      expect(sig!.isStruct, isTrue, reason: '"$name" should be a struct');
      expect(sig.width, 9, reason: '"$name" width = mantissa+exponent+sign');

      final fieldNames = sig.structFields.map((f) => f['name']).toList();
      expect(fieldNames, containsAll(['mantissa', 'exponent', 'sign']));
    }

    // (3) struct fields are not duplicated as top-level signals.
    final leafNames = top.signals.map((s) => s.name).toSet();
    for (final field in ['mantissa', 'exponent', 'sign']) {
      expect(
        leafNames,
        isNot(contains('a_$field')),
        reason: 'struct field a_$field should not be listed separately',
      );
    }

    // (4) a plain (non-struct) signal still resolves normally.
    expect(leafNames, contains('clk'));
  });

  test('struct signal waveform is the concatenation of its leaf fields',
      () async {
    final filePath = '$fixturesPath/$_fixture';

    final api = WellenSignalWaveformApi();
    await api.loadFile(filePath);
    final structure = await api.getModuleStructureOnly();
    final top = structure.modules.firstWhere(
      (m) => m.name == _topName,
      orElse: () => structure.firstModuleWithSignals!,
    );

    final aStruct = top.signals.firstWhere((s) => s.name == 'a');
    final aPath = aStruct.path();

    final rawPrefix = '${top.name}.a';
    final results = await api.getWaveformData(
      signalIds: [
        aPath,
        '$rawPrefix.mantissa',
        '$rawPrefix.exponent',
        '$rawPrefix.sign',
      ],
    );
    final byId = {for (final r in results) r.signalId: r};

    final parent = byId[aPath];
    expect(parent, isNotNull, reason: 'struct parent waveform missing');
    expect(parent!.data, isNotEmpty);

    final mantissa = byId['$rawPrefix.mantissa'];
    final exponent = byId['$rawPrefix.exponent'];
    final sign = byId['$rawPrefix.sign'];
    expect(mantissa, isNotNull);
    expect(exponent, isNotNull);
    expect(sign, isNotNull);

    // Every emitted struct value is 9 bits wide (or all-x), MSB-first:
    // [sign(1)][exponent(4)][mantissa(4)].
    for (final d in parent.data) {
      expect(d.value.length, 9,
          reason: 'packed struct value should be 9 bits: ${d.value}');
    }

    // Step-function lookup helper: value of [data] at or before [time].
    String at(List<Data> data, int time) {
      String v = data.isEmpty ? '' : data.first.value;
      for (final d in data) {
        if (d.time > time) break;
        v = d.value;
      }
      return v;
    }

    // For each struct transition, the packed bits must equal the
    // concatenation of the (MSB-first) leaf values at that time.
    for (final d in parent.data) {
      final s = at(sign!.data, d.time);
      final e = at(exponent!.data, d.time);
      final m = at(mantissa!.data, d.time);
      if (s.contains('x') || e.contains('x') || m.contains('x')) {
        continue; // skip undefined regions
      }
      expect(d.value, '$s$e$m',
          reason: 'struct value at t=${d.time} should be sign|exp|mantissa');
    }
  });

  test('FilterBank struct ports replace scopes and duplicate flat signals',
      () async {
    final api = WellenSignalWaveformApi();
    await api.loadFile(_filterBankFixture);
    final structure = await api.getModuleStructureOnly();
    final filterBank =
        structure.modules.firstWhere((module) => module.name == 'FilterBank');

    final childNames = filterBank.children.map((child) => child.name);
    expect(childNames, isNot(contains('sample0')));
    expect(childNames, isNot(contains('sample1')));
    for (final duplicateName in [
      'validIn',
      'validOut',
      'sampleIn',
      'dataOut',
    ]) {
      expect(
        filterBank.signals.where((signal) => signal.name == duplicateName),
        hasLength(1),
        reason: '$duplicateName should occur once in FilterBank',
      );
    }

    for (final structName in ['sample0', 'sample1']) {
      final signal =
          filterBank.signals.firstWhere((item) => item.name == structName);
      expect(signal.isStruct, isTrue);
      expect(signal.width, 17);
      expect(
        signal.structFields.map((field) => field['name']),
        ['data', 'valid'],
      );
      expect(
        filterBank.signals.map((item) => item.name),
        isNot(contains('${structName}_data')),
      );
      expect(
        filterBank.signals.map((item) => item.name),
        isNot(contains('${structName}_valid')),
      );
    }
  });
}
