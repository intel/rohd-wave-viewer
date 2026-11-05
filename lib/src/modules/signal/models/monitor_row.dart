// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// monitor_row.dart
// Viewer-owned monitor-row state for shared waveform data.
//
// 2026 November
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_waveform/rohd_waveform.dart';

/// Display representation selected for a monitored waveform row.
enum MonitorValueFormat {
  /// Render the signal using its waveform shape and labels.
  waveform,

  /// Display numeric values as binary.
  binary,

  /// Display numeric values as hexadecimal.
  hexadecimal,

  /// Display numeric values as unsigned decimal.
  unsignedDecimal,

  /// Display numeric values as signed decimal.
  signedDecimal,

  /// Display numeric values as octal.
  octal,

  /// Display numeric values as ASCII characters.
  ascii,
}

/// Viewer-owned state for one presentation of a waveform.
class MonitorRow {
  static int _nextMonitorRow = 0;

  /// The independent waveform snapshot displayed by this row.
  final SignalWaveform waveform;

  /// Identity of this row, independent of the signal's identity.
  final String monitorId;

  /// Parent monitor-row identity for generated fields and bit slices.
  String? monitorParentId;

  /// Optional named group applied to this row.
  String? monitorGroup;

  /// Display representation selected for this row.
  MonitorValueFormat valueFormat;

  /// Creates a row with an independent waveform snapshot.
  MonitorRow({
    required String signalId,
    String? monitorId,
    List<Data>? data,
    bool isComputed = false,
    int? overrideWidth,
    String? overrideName,
    this.monitorParentId,
    this.monitorGroup,
    this.valueFormat = MonitorValueFormat.waveform,
  })  : monitorId = monitorId ?? signalId,
        waveform = SignalWaveform(
          signalId: signalId,
          data: data,
          isComputed: isComputed,
          overrideWidth: overrideWidth,
          overrideName: overrideName,
        );

  /// Creates an empty row.
  factory MonitorRow.empty(String signalId, {bool isComputed = false}) =>
      MonitorRow(signalId: signalId, isComputed: isComputed);

  /// Creates a row from a waveform transfer payload.
  factory MonitorRow.fromWaveformData(WaveformData data) =>
      MonitorRow.fromWaveform(
        SignalWaveform.fromWaveformData(data),
        monitorId: data.signalId,
      );

  /// Creates a distinct row from a repository waveform.
  factory MonitorRow.fromWaveform(
    SignalWaveform waveform, {
    String? monitorId,
    bool? isComputed,
  }) =>
      MonitorRow(
        signalId: waveform.signalId,
        monitorId: monitorId ?? '${waveform.signalId}#${_nextMonitorRow++}',
        data: List.of(waveform.data),
        isComputed: isComputed ?? waveform.isComputed,
        overrideWidth: waveform.overrideWidth,
        overrideName: waveform.overrideName,
      );

  /// Copies a row and its waveform snapshot.
  factory MonitorRow.copyFrom(
    MonitorRow other, {
    String? monitorId,
    bool? isComputed,
  }) =>
      MonitorRow.fromWaveform(
        other.waveform,
        monitorId: monitorId,
        isComputed: isComputed,
      )
        ..monitorParentId = other.monitorParentId
        ..monitorGroup = other.monitorGroup
        ..valueFormat = other.valueFormat;

  /// Signal identity used by the waveform source.
  String get signalId => waveform.signalId;

  /// Alias for the signal identity.
  String get id => waveform.id;

  /// Cached waveform samples.
  List<Data> get data => waveform.data;

  /// Signal metadata, if available.
  SignalOccurrence? get signal => waveform.signal;

  /// Signal hierarchy path.
  String get hierarchyPath => waveform.hierarchyPath;

  /// Signal path when metadata is available.
  String? get fullPath => waveform.fullPath;

  /// Signal display name.
  String get name => waveform.name;

  /// Signal width.
  int get width => waveform.width;

  /// Signal type used for waveform rendering.
  String get type => waveform.type;

  /// Explicit width for computed waveforms.
  int? get overrideWidth => waveform.overrideWidth;
  set overrideWidth(int? value) => waveform.overrideWidth = value;

  /// Explicit name for computed waveforms.
  String? get overrideName => waveform.overrideName;
  set overrideName(String? value) => waveform.overrideName = value;

  /// Whether this waveform was synthesized.
  bool get isComputed => waveform.isComputed;

  /// Whether this row represents the given hierarchy occurrence.
  bool matchesOccurrence(SignalOccurrence occurrence) =>
      waveform.matchesOccurrence(occurrence);

  /// Value at or before the requested time.
  String getValueByTime(int time) => waveform.getValueByTime(time);

  /// Index of the next data point after the requested time.
  int getNextDataPointIndex(int time) => waveform.getNextDataPointIndex(time);

  /// Index of the previous data point before the requested time.
  int getPreviousDataPointIndex(int time) =>
      waveform.getPreviousDataPointIndex(time);

  /// Index of the next matching sample.
  int getNextMatchingDataPointIndex(
    int time, {
    required WaveformSearchCriterion criterion,
    String? value,
  }) =>
      waveform.getNextMatchingDataPointIndex(
        time,
        criterion: criterion,
        value: value,
      );

  /// Index of the previous matching sample.
  int getPreviousMatchingDataPointIndex(
    int time, {
    required WaveformSearchCriterion criterion,
    String? value,
  }) =>
      waveform.getPreviousMatchingDataPointIndex(
        time,
        criterion: criterion,
        value: value,
      );
}

/// A monitored row with a user-defined display name.
class MonitoredSignal extends MonitorRow {
  /// Display name used in the monitored-signal list.
  final String displayName;

  /// Creates a named copy of an existing row.
  MonitoredSignal.fromWaveform(
    MonitorRow row, {
    required this.displayName,
  }) : super(
          signalId: row.signalId,
          monitorId: row.monitorId,
          data: List.of(row.data),
          isComputed: row.isComputed,
          overrideWidth: row.overrideWidth,
          overrideName: displayName,
          monitorParentId: row.monitorParentId,
          monitorGroup: row.monitorGroup,
          valueFormat: row.valueFormat,
        );

  @override
  String get name => displayName;
}
