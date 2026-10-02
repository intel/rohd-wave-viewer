// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// wellen_wave_dumper.dart
// Manual adapter for writing timestamped waveform changes to VCD.
//
// 2026 January 03
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';

import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_waveform/rohd_waveform.dart';
import 'wellen_writer.dart';

/// A callback type for registering signal value changes.
typedef SignalChangeCallback = void Function(String signalId, String value);

/// A callback type for getting the current simulation time.
typedef SimulatorTimeGetter = int Function();

/// A manual adapter for recording signal changes in a native VCD file.
///
/// Callers register [SignalOccurrence] objects before [open], then forward
/// timestamped changes through [recordChange]. This class does not attach
/// itself to a ROHD simulator. FST output is not implemented.
class WellenWaveDumper {
  /// The output file path.
  final String outputPath;

  /// The output format.
  final WaveFormat format;

  /// The timescale string (e.g., "1ps", "1ns").
  final String timescale;

  /// Optional date string for the header.
  final String? date;

  /// Optional version string for the header.
  final String? version;

  /// The underlying writer.
  final WellenWriter _writer = WellenWriter();

  /// Registered signals.
  final Map<String, SignalOccurrence> _signals = {};

  /// Current timestamp for batching.
  int _currentTimestamp = 0;

  /// Pending value changes for the current timestamp.
  final Map<String, String> _pendingChanges = {};

  /// Whether the dumper is open.
  bool _isOpen = false;

  /// Creates a new WellenWaveDumper.
  ///
  /// [outputPath] - The output file path.
  /// [format] - The output format (only VCD is currently supported).
  /// [timescale] - The timescale string (default: "1ps").
  /// [date] - Optional date for the header.
  /// [version] - Optional version for the header.
  WellenWaveDumper(
    this.outputPath, {
    this.format = WaveFormat.vcd,
    this.timescale = '1ps',
    this.date,
    this.version,
  });

  /// Whether the dumper is currently open.
  bool get isOpen => _isOpen;

  /// Register a signal to be dumped.
  ///
  /// Must be called before [open].
  void registerSignal(SignalOccurrence signal) {
    if (_isOpen) {
      throw WellenWaveDumperException(
        'Cannot register signals after dumper is opened',
      );
    }
    _signals[signal.path()] = signal;
  }

  /// Register multiple signals at once.
  void registerSignals(Iterable<SignalOccurrence> signals) {
    signals.forEach(registerSignal);
  }

  /// Open the dumper and write the header.
  Future<void> open() async {
    if (_isOpen) {
      throw WellenWaveDumperException('Dumper is already open');
    }

    await _writer.open(
      outputPath,
      format: format,
      timescale: timescale,
      date: date,
      version: version,
    );

    // Register all signals with the writer
    _writer.registerSignals(_signals.values);

    // Write header
    _writer.writeHeader();

    _isOpen = true;

    // Write initial values (all zeros or X)
    _writeTimestamp(0);
    for (final signal in _signals.values) {
      final initialValue = '0' * signal.width;
      _writer.writeValue(0, signal.path(), initialValue);
    }
  }

  /// Record a value change for a signal.
  ///
  /// If [timestamp] is the same as the previous call, changes are batched.
  /// When [timestamp] advances, all pending changes are flushed.
  void recordChange(int timestamp, String signalId, String value) {
    if (!_isOpen) {
      throw WellenWaveDumperException('Dumper is not open');
    }

    if (!_signals.containsKey(signalId)) {
      throw WellenWaveDumperException(
        'SignalOccurrence not registered: $signalId',
      );
    }

    // If timestamp has advanced, flush pending changes
    if (timestamp != _currentTimestamp && _pendingChanges.isNotEmpty) {
      _flushPendingChanges();
    }

    _currentTimestamp = timestamp;
    _pendingChanges[signalId] = value;
  }

  /// Flush all pending changes to the output.
  void _flushPendingChanges() {
    if (_pendingChanges.isEmpty) return;

    _writeTimestamp(_currentTimestamp);
    for (final entry in _pendingChanges.entries) {
      _writer.writeValue(_currentTimestamp, entry.key, entry.value);
    }
    _pendingChanges.clear();
  }

  /// Write a timestamp marker (internal use).
  void _writeTimestamp(int timestamp) {
    // The writer handles timestamp deduplication internally
  }

  /// Capture the current simulation state.
  ///
  /// Call this at each simulation tick to record any pending changes.
  void captureTimestamp(int timestamp) {
    if (timestamp != _currentTimestamp && _pendingChanges.isNotEmpty) {
      _flushPendingChanges();
    }
    _currentTimestamp = timestamp;
  }

  /// Flush buffered output to the file.
  Future<void> flush() async {
    _flushPendingChanges();
    await _writer.flush();
  }

  /// Close the dumper and finalize the output file.
  Future<void> close() async {
    if (!_isOpen) return;

    // Flush any remaining changes
    _flushPendingChanges();

    await _writer.close();
    _isOpen = false;
    _signals.clear();
    _pendingChanges.clear();
  }
}

/// Exception thrown by WellenWaveDumper operations.
class WellenWaveDumperException implements Exception {
  /// Creates a new WellenWaveDumperException with the given message.
  WellenWaveDumperException(this.message);

  /// The error message.
  final String message;

  @override
  String toString() => 'WellenWaveDumperException: $message';
}
