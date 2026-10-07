// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_list_persistence.dart
// Serializable session state for monitored signals and viewer preferences.
//
// 2026 August
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';

import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_wave_viewer/src/cubit/wave_viewer_theme_cubit.dart';
import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';

/// One persisted monitored-signal row.
class SignalListEntry {
  /// Creates a persisted signal-list row.
  const SignalListEntry({
    required this.id,
    this.width,
    this.displayName,
    this.valueFormat = MonitorValueFormat.waveform,
    this.monitorGroup,
  });

  /// Full signal or bit-slice path.
  final String id;

  /// Optional width override for computed sub-fields.
  final int? width;

  /// Optional display-name override for computed sub-fields.
  final String? displayName;

  /// Value format for this specific monitor row.
  final MonitorValueFormat valueFormat;

  /// Optional monitor group for this row.
  final String? monitorGroup;

  /// Converts this row to its persisted JSON record.
  Map<String, Object?> toJson() => {
        'id': id,
        if (width != null) 'width': width,
        if (displayName != null) 'displayName': displayName,
        if (valueFormat != MonitorValueFormat.waveform)
          'format': valueFormat.name,
        if (monitorGroup != null) 'group': monitorGroup,
      };

  /// Parses a legacy path or current JSON record into a persisted row.
  static SignalListEntry? fromJson(Object? value) {
    if (value is String) {
      return SignalListEntry(id: value);
    }
    if (value is! Map) {
      return null;
    }
    final id = value['id'];
    if (id is! String) {
      return null;
    }
    final formatName = value['format'];
    return SignalListEntry(
      id: id,
      width: value['width'] is int ? value['width'] as int : null,
      displayName: value['displayName'] is String
          ? value['displayName'] as String
          : null,
      valueFormat: MonitorValueFormat.values.firstWhere(
        (format) => format.name == formatName,
        orElse: () => MonitorValueFormat.waveform,
      ),
      monitorGroup: value['group'] is String ? value['group'] as String : null,
    );
  }
}

/// Restorable waveform viewport state.
class SignalListViewportState {
  /// Creates a persisted viewport state.
  const SignalListViewportState({
    required this.zoomLevel,
    required this.scrollFraction,
  });

  /// Waveform zoom level.
  final double zoomLevel;

  /// Horizontal scroll position as a fraction of its maximum extent.
  final double scrollFraction;

  /// Converts this viewport state to its persisted JSON record.
  Map<String, double> toJson() => {
        'zoomLevel': zoomLevel,
        'scrollFraction': scrollFraction,
      };
}

/// Restorable viewer state stored alongside a signal list.
class SignalListSessionState {
  /// Creates persisted viewer session state.
  const SignalListSessionState({
    this.showInternalSignals,
    this.filterText,
    this.cursorTimePs,
    this.measurementMarkerTimePs,
    this.rowScale,
    this.themeMode,
    this.hierarchyPinned,
    this.appBarPinned,
    this.pinnedPanelWidth,
    this.viewport,
  });

  /// Internal-signal visibility, when persisted.
  final bool? showInternalSignals;

  /// Module-signal filter text, when persisted.
  final String? filterText;

  /// Primary cursor time, when persisted.
  final int? cursorTimePs;

  /// Measurement marker time, when persisted.
  final int? measurementMarkerTimePs;

  /// Row-height scale, when persisted.
  final double? rowScale;

  /// Viewer theme, when persisted.
  final WaveViewerThemeMode? themeMode;

  /// Hierarchy overlay pinning, when persisted.
  final bool? hierarchyPinned;

  /// App-bar pinning, when persisted.
  final bool? appBarPinned;

  /// Pinned selected-signals panel width, when persisted.
  final double? pinnedPanelWidth;

  /// Waveform viewport state, when persisted.
  final SignalListViewportState? viewport;

  /// Converts this viewer session state to its persisted JSON record.
  Map<String, Object?> toJson() => {
        if (showInternalSignals != null)
          'showInternalSignals': showInternalSignals,
        if (filterText != null) 'filterText': filterText,
        if (cursorTimePs != null) 'cursorTimePs': cursorTimePs,
        if (measurementMarkerTimePs != null)
          'measurementMarkerTimePs': measurementMarkerTimePs,
        if (rowScale != null) 'rowScale': rowScale,
        if (themeMode != null) 'themeMode': themeMode!.name,
        if (hierarchyPinned != null) 'hierarchyPinned': hierarchyPinned,
        if (appBarPinned != null) 'appBarPinned': appBarPinned,
        if (pinnedPanelWidth != null) 'pinnedPanelWidth': pinnedPanelWidth,
        if (viewport != null) 'viewport': viewport!.toJson(),
      };

  /// Parses an optional JSON record into restorable viewer session state.
  static SignalListSessionState? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final viewport = value['viewport'];
    final zoomLevel = viewport is Map ? viewport['zoomLevel'] : null;
    final scrollFraction = viewport is Map ? viewport['scrollFraction'] : null;
    final themeMode = _themeMode(value['themeMode']);
    return SignalListSessionState(
      showInternalSignals: value['showInternalSignals'] is bool
          ? value['showInternalSignals'] as bool
          : null,
      filterText:
          value['filterText'] is String ? value['filterText'] as String : null,
      cursorTimePs: _nonNegativeInt(value['cursorTimePs']),
      measurementMarkerTimePs:
          _nonNegativeInt(value['measurementMarkerTimePs']),
      rowScale: value['rowScale'] is num
          ? (value['rowScale'] as num).toDouble()
          : null,
      themeMode: themeMode,
      hierarchyPinned: value['hierarchyPinned'] is bool
          ? value['hierarchyPinned'] as bool
          : null,
      appBarPinned:
          value['appBarPinned'] is bool ? value['appBarPinned'] as bool : null,
      pinnedPanelWidth: value['pinnedPanelWidth'] is num
          ? (value['pinnedPanelWidth'] as num).toDouble()
          : null,
      viewport: zoomLevel is num && scrollFraction is num
          ? SignalListViewportState(
              zoomLevel: zoomLevel.toDouble(),
              scrollFraction: scrollFraction.toDouble(),
            )
          : null,
    );
  }

  static WaveViewerThemeMode? _themeMode(Object? value) {
    if (value is! String) {
      return null;
    }
    for (final mode in WaveViewerThemeMode.values) {
      if (mode.name == value) {
        return mode;
      }
    }
    return null;
  }
}

int? _nonNegativeInt(Object? value) =>
    value is int && value >= 0 ? value : null;

/// Parsed and hierarchy-validated signal-list restore plan.
class SignalListRestorePlan {
  /// Creates a restore plan.
  const SignalListRestorePlan({
    required this.entries,
    required this.skippedPaths,
    this.session,
  });

  /// Valid signal rows in their persisted order, including duplicates.
  final List<SignalListEntry> entries;

  /// Saved paths that could not be resolved in the current hierarchy.
  final List<String> skippedPaths;

  /// Optional restorable viewer state.
  final SignalListSessionState? session;

  /// Paths supplied to the monitor-list restore event.
  List<String> get signalPaths => entries.map((entry) => entry.id).toList();

  /// Per-row display formats supplied to the monitor-list restore event.
  List<MonitorValueFormat> get valueFormats =>
      entries.map((entry) => entry.valueFormat).toList();

  /// Per-row monitor groups supplied to the monitor-list restore event.
  List<String?> get monitorGroups =>
      entries.map((entry) => entry.monitorGroup).toList();

  /// Computed sub-field metadata supplied to the monitor-list restore event.
  Map<String, ({int width, String displayName})>? get metadata {
    final result = <String, ({int width, String displayName})>{};
    for (final entry in entries) {
      if (entry.width != null || entry.displayName != null) {
        result[entry.id] = (
          width: entry.width ?? 1,
          displayName: entry.displayName ?? entry.id.split('/').last,
        );
      }
    }
    return result.isEmpty ? null : result;
  }
}

/// Encodes and decodes persisted monitored-signal lists independently of UI.
abstract final class SignalListPersistence {
  /// Encodes ordered monitor rows and optional viewer state as signal-list
  /// JSON.
  static String encode({
    required List<SignalListEntry> entries,
    SignalListSessionState? session,
  }) =>
      const JsonEncoder.withIndent('  ').convert({
        'version': 6,
        'signals': entries.map((entry) => entry.toJson()).toList(),
        if (session != null) 'session': session.toJson(),
      });

  /// Parses [content] and retains only paths resolvable in [structure].
  static SignalListRestorePlan decodeAndResolve({
    required String content,
    required ModuleStructure structure,
  }) {
    final parsed = jsonDecode(content);
    if (parsed is! Map || parsed['signals'] is! List) {
      throw const FormatException(
        'Invalid signal list file (expected {"signals": [...]})',
      );
    }

    final hierarchy = _hierarchyFor(structure);
    final entries = <SignalListEntry>[];
    final skippedPaths = <String>[];
    for (final rawEntry in parsed['signals'] as List) {
      final entry = SignalListEntry.fromJson(rawEntry);
      if (entry == null) {
        continue;
      }
      if (_resolves(entry.id, hierarchy)) {
        entries.add(entry);
      } else {
        skippedPaths.add(entry.id);
      }
    }

    return SignalListRestorePlan(
      entries: entries,
      skippedPaths: skippedPaths,
      session: SignalListSessionState.fromJson(parsed['session']),
    );
  }

  static HierarchyService? _hierarchyFor(ModuleStructure structure) {
    if (structure.hierarchyService != null) {
      return structure.hierarchyService;
    }
    final modules = structure.modules;
    if (modules.isEmpty) {
      return null;
    }
    if (modules.length == 1) {
      return BaseHierarchyAdapter.fromTree(modules.first);
    }
    return BaseHierarchyAdapter.fromTree(
      HierarchyOccurrence(name: 'root', children: modules),
    );
  }

  static bool _resolves(String id, HierarchyService? hierarchy) {
    if (hierarchy == null) {
      return false;
    }
    final parentPath = id.contains('#') ? id.substring(0, id.indexOf('#')) : id;
    final address =
        OccurrenceAddress.tryFromPathname(parentPath, hierarchy.root);
    return address != null && hierarchy.signalByAddress(address) != null;
  }
}
