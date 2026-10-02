// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_state.dart
// The state for the SignalOccurrence BLoC.
//
// 2024 April
// Author(s): Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
//            Yao Jing Quek <yao.jing.quek@intel.com>

part of 'signal_bloc.dart';

/// Base class for signal BLoC states.
sealed class SignalState extends Equatable {
  /// SignalOccurrence metadata for the current module (for display in signal
  /// list).
  final List<SignalOccurrence> signals;

  /// Waveforms for monitored signals (for waveform display and value lookup).
  final List<SignalWaveform> monitorSignalsList;

  /// Set of focused signal IDs for multi-select navigation. When non-empty,
  /// arrow keys navigate to the nearest edge of any focused signal.
  final Set<String> focusedSignalIds;

  /// Whether to show internal signals (wires, registers) in the signal list.
  /// When false, only ports are displayed.
  final bool showInternalSignals;

  /// The hierarchical path of the currently selected module.
  ///
  /// Used for scope-aware signal name display: signals belonging to the
  /// selected module show bare names, while signals from other modules
  /// get their parent module path prepended relative to the selected module.
  final String? selectedModulePath;

  /// When non-null, the UI should scroll all vertical panels so the signal
  /// at this index is visible. Cleared after the scroll is performed.
  final int? scrollToIndex;

  /// Monotonically increasing counter so that repeated scroll-to requests
  /// for the same index are not deduplicated by Equatable.
  final int scrollToCounter;

  /// Text or wildcard filter applied to the Module Signals list.
  /// Empty string means no filter (show all current module signals).
  final String filterText;

  /// Sort direction for the Module Signals list.
  /// null = unsorted (natural order), true = ascending, false = descending.
  final bool? sortAscending;

  /// Set of signal IDs selected in the Module Signals panel.
  /// Used for click/ctrl-click/shift-click selection before adding to
  /// the monitored waveform list.
  final Set<String> moduleSelectedSignalIds;

  /// Set of waveform IDs in the monitor list that are currently expanded
  /// (showing struct fields or array elements inline).
  final Set<String> expandedMonitorSignals;

  /// Creates a signal state.
  const SignalState(
    this.signals,
    this.monitorSignalsList, {
    this.focusedSignalIds = const {},
    this.showInternalSignals = false,
    this.selectedModulePath,
    this.scrollToIndex,
    this.scrollToCounter = 0,
    this.filterText = '',
    this.sortAscending,
    this.moduleSelectedSignalIds = const {},
    this.expandedMonitorSignals = const {},
  });

  /// Returns true if any signal is focused.
  bool get hasFocusedSignals => focusedSignalIds.isNotEmpty;

  /// Returns the focused waveforms from the monitor list.
  List<SignalWaveform> get focusedSignals => monitorSignalsList
      .where((waveform) => focusedSignalIds.contains(waveform.monitorId))
      .toList();

  /// Legacy getter for single focused signal (returns first if multiple, null
  /// if none).
  SignalWaveform? get focusedSignal =>
      focusedSignals.isNotEmpty ? focusedSignals.first : null;

  /// Check if a specific signal is focused.
  bool isSignalFocused(String monitorId) =>
      focusedSignalIds.contains(monitorId);

  /// Gets the display name for a monitored signal.
  ///
  /// If multiple signals with the same name are monitored, prepends parent
  /// module names to distinguish them. The display name uses '/' as separator.
  String getDisplayNameForSignal(SignalWaveform signal) {
    if (signal is MonitoredSignal) {
      return signal.displayName;
    }
    final displayNames = getMonitoredSignalDisplayNames();
    if (displayNames.containsKey(signal.id)) {
      return displayNames[signal.id]!;
    }
    // Fallback: extract the leaf name from signal.name.
    // signal.name may be the full path (signalId) if the lookup is broken.
    final name = signal.name;
    if (name.contains('.') || name.contains('/')) {
      final lastDot = name.lastIndexOf('.');
      final lastSlash = name.lastIndexOf('/');
      final lastSep = lastDot > lastSlash ? lastDot : lastSlash;
      return name.substring(lastSep + 1);
    }
    return name;
  }

  /// Gets display names for all monitored signals.
  ///
  /// Returns a map of signal ID to display name. When a selected module path
  /// is available, signals are named relative to that module's position in the
  /// hierarchy. Otherwise, falls back to duplicate-name disambiguation.
  Map<String, String> getMonitoredSignalDisplayNames() {
    if (monitorSignalsList.isEmpty) {
      return {};
    }

    return generateSignalDisplayNames(
      monitorSignalsList,
      selectedModulePath: selectedModulePath,
    );
  }

  /// Gets the filtered signal list based on showInternalSignals toggle
  /// and the user's text or wildcard filter.
  ///
  /// Returns only ports if showInternalSignals is false,
  /// otherwise returns all signals (ports + internal signals).
  /// Then applies the filterText filter if non-empty.
  /// Finally sorts alphabetically if sortAscending is set.
  List<SignalOccurrence> get filteredSignals {
    List<SignalOccurrence> result;
    if (showInternalSignals) {
      // Collect sub-field names from struct/array parents so we can hide
      // them as separate top-level entries.  The user can still expand them
      // via the caret on the parent signal row.
      final subFieldNames = <String>{};
      for (final s in signals) {
        if (s.isStruct || s.isArray) {
          for (final d in s.subFieldDescriptors) {
            subFieldNames.add(d.expectedName);
          }
        }
      }
      result = signals.where((s) => !subFieldNames.contains(s.name)).toList();
    } else {
      // Filter to show only ports (signals with direction)
      result = signals.where((s) => s.isPort).toList();
    }

    // Apply text/wildcard filter.
    if (filterText.isNotEmpty) {
      final hasWildcard = filterText.contains('*') || filterText.contains('?');
      if (hasWildcard) {
        result = result
            .where(
              (s) =>
                  _matchesWildcard(s.name, filterText) ||
                  _matchesWildcard(s.path(), filterText),
            )
            .toList();
      } else {
        // Plain text: case-insensitive prefix match on signal name
        // or hierarchy path.
        final lower = filterText.toLowerCase();
        result = result
            .where(
              (s) =>
                  s.name.toLowerCase().startsWith(lower) ||
                  s.path().toLowerCase().startsWith(lower),
            )
            .toList();
      }
    }

    // Apply sort if set.
    if (sortAscending != null) {
      result.sort((a, b) {
        final cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return sortAscending! ? cmp : -cmp;
      });
    }

    return result;
  }

  /// Matches [value] against a case-insensitive glob with `*` and `?`.
  static bool _matchesWildcard(String value, String pattern) {
    final lowerValue = value.toLowerCase();
    final lowerPattern = pattern.toLowerCase();
    var valueIndex = 0;
    var patternIndex = 0;
    var starIndex = -1;
    var starMatchIndex = 0;

    while (valueIndex < lowerValue.length) {
      if (patternIndex < lowerPattern.length &&
          (lowerPattern[patternIndex] == '?' ||
              lowerPattern[patternIndex] == lowerValue[valueIndex])) {
        valueIndex++;
        patternIndex++;
      } else if (patternIndex < lowerPattern.length &&
          lowerPattern[patternIndex] == '*') {
        starIndex = patternIndex++;
        starMatchIndex = valueIndex;
      } else if (starIndex >= 0) {
        patternIndex = starIndex + 1;
        valueIndex = ++starMatchIndex;
      } else {
        return false;
      }
    }

    while (patternIndex < lowerPattern.length &&
        lowerPattern[patternIndex] == '*') {
      patternIndex++;
    }
    return patternIndex == lowerPattern.length;
  }

  /// Whether a module-signal-panel signal is selected.
  bool isModuleSignalSelected(String signalId) =>
      moduleSelectedSignalIds.contains(signalId);

  @override
  List<Object?> get props => [
        monitorSignalsList,
        signals,
        focusedSignalIds,
        showInternalSignals,
        selectedModulePath,
        scrollToIndex,
        scrollToCounter,
        filterText,
        sortAscending,
        moduleSelectedSignalIds,
        expandedMonitorSignals,
      ];
}

/// State emitted while signal metadata is loading.
final class SignalLoading extends SignalState {
  /// Creates a loading signal state.
  SignalLoading({super.showInternalSignals = false})
      : super(
          [],
          [],
          focusedSignalIds: const {},
        );
}

/// State emitted after signal metadata has loaded.
final class SignalLoaded extends SignalState {
  /// Creates a loaded signal state.
  const SignalLoaded(
    super.signals,
    super.monitorSignalsList, {
    super.focusedSignalIds = const {},
    super.showInternalSignals = false,
    super.selectedModulePath,
    super.scrollToIndex,
    super.scrollToCounter = 0,
    super.filterText = '',
    super.sortAscending,
    super.moduleSelectedSignalIds = const {},
    super.expandedMonitorSignals = const {},
  });
}
