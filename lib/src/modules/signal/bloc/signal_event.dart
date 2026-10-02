// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_event.dart
// The events for the SignalOccurrence BLoC.
//
// 2024 April
// Author(s): Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
//            Yao Jing Quek <yao.jing.quek@intel.com>

part of 'signal_bloc.dart';

/// Base class for all signal BLoC events.
sealed class SignalEvent extends Equatable {}

/// Updates the selected module backing the signal views.
class SignalUpdateEvent extends SignalEvent {
  /// The module selected in the hierarchy.
  final HierarchyOccurrence selectedModule;

  /// Creates a signal update event.
  SignalUpdateEvent(this.selectedModule);

  @override
  List<Object?> get props => [selectedModule];
}

/// Event to add a signal to the monitor list. Takes a SignalOccurrence
/// (metadata) and looks up the waveform from the repository.
class SignalSelectedEvent extends SignalEvent {
  /// The signal selected for monitoring.
  final SignalOccurrence selectedSignal;

  /// Creates a signal selection event.
  SignalSelectedEvent(this.selectedSignal);

  @override
  List<Object?> get props => [selectedSignal];
}

/// Selects a waveform for focus-mode navigation (arrow keys navigate data
/// points). When isMultiSelect is true, toggles the signal in the focused set.
/// When isMultiSelect is false (default), replaces the focused set with just
/// this signal.
class SignalFocusEvent extends SignalEvent {
  /// The waveform to focus.
  final SignalWaveform waveform;

  /// Whether to extend the current focus selection.
  final bool isMultiSelect;

  /// Creates a signal focus event.
  SignalFocusEvent(this.waveform, {this.isMultiSelect = false});

  @override
  List<Object?> get props => [waveform, isMultiSelect];
}

/// Selects a range of signals in the monitor list (shift-click).
///
/// Selects all signals between [anchorIndex] and [extentIndex] inclusive,
/// replacing the current focused set.
class SignalRangeFocusEvent extends SignalEvent {
  /// The first selected row index.
  final int anchorIndex;

  /// The last selected row index.
  final int extentIndex;

  /// Creates a range focus event.
  SignalRangeFocusEvent({required this.anchorIndex, required this.extentIndex});

  @override
  List<Object?> get props => [anchorIndex, extentIndex];
}

/// Deselects all focused signals; arrow keys return to normal pan.
class SignalUnfocusEvent extends SignalEvent {
  @override
  List<Object?> get props => [];
}

/// Unfocuses a specific signal from the multi-select set.
class SignalUnfocusOneEvent extends SignalEvent {
  /// Identifier of the signal to unfocus.
  final String signalId;

  /// Creates an event that removes one focused signal.
  SignalUnfocusOneEvent(this.signalId);

  @override
  List<Object?> get props => [signalId];
}

/// Removes a signal from the monitor list (used when DEL key is pressed).
class SignalRemoveEvent extends SignalEvent {
  /// The waveform to remove.
  final SignalWaveform waveform;

  /// Creates a signal removal event.
  SignalRemoveEvent(this.waveform);

  @override
  List<Object?> get props => [waveform];
}

/// Removes several signals from the monitor list as one undoable edit.
class SignalRemoveManyEvent extends SignalEvent {
  /// The monitor-row identities to remove.
  final Set<String> monitorIds;

  /// Creates a batched signal removal event.
  SignalRemoveManyEvent(Iterable<String> monitorIds)
      : monitorIds = Set.unmodifiable(monitorIds);

  @override
  List<Object?> get props => [monitorIds];
}

/// Restores the previous monitored-signal edit.
class SignalUndoMonitorEvent extends SignalEvent {
  @override
  List<Object?> get props => [];
}

/// Reapplies a monitored-signal edit that was undone.
class SignalRedoMonitorEvent extends SignalEvent {
  @override
  List<Object?> get props => [];
}

/// Changes the display format for one or more monitored rows.
class SignalSetValueFormatEvent extends SignalEvent {
  /// Monitor-row identities to update.
  final Set<String> monitorIds;

  /// Format applied to every row in [monitorIds].
  final MonitorValueFormat valueFormat;

  /// Creates a display-format update.
  SignalSetValueFormatEvent({
    required this.monitorIds,
    required this.valueFormat,
  });

  @override
  List<Object?> get props => [monitorIds, valueFormat];
}

/// Changes the display format associated with one or more signal occurrences.
///
/// The preference applies to every existing monitored row for an occurrence
/// and to rows added later during this viewer session.
class SignalSetOccurrenceValueFormatEvent extends SignalEvent {
  /// Hierarchy paths of the signal occurrences to update.
  final Set<String> signalPaths;

  /// Format applied to every occurrence in [signalPaths].
  final MonitorValueFormat valueFormat;

  /// Creates an occurrence display-format update.
  SignalSetOccurrenceValueFormatEvent({
    required this.signalPaths,
    required this.valueFormat,
  });

  @override
  List<Object?> get props => [signalPaths, valueFormat];
}

/// Assigns or clears a named group for monitored rows.
class SignalSetMonitorGroupEvent extends SignalEvent {
  /// Monitor-row identities to update.
  final Set<String> monitorIds;

  /// Group name, or null to remove the current group assignment.
  final String? groupName;

  /// Creates a group assignment update.
  SignalSetMonitorGroupEvent({
    required this.monitorIds,
    required this.groupName,
  });

  @override
  List<Object?> get props => [monitorIds, groupName];
}

/// Resets the signal bloc to initial state (clears selected signals and focus).
class SignalResetEvent extends SignalEvent {
  @override
  List<Object?> get props => [];
}

/// Restores previously monitored signals after a reconnect or file load.
///
/// Loads waveform data for each path sequentially (preserving order)
/// and appends them all to the monitor list in a single emit.
///
/// [metadata] provides optional per-signal overrides (width, displayName)
/// for sub-field / bit-slice waveforms that don't have real hierarchy entries.
/// Keys are the signal IDs from [signalPaths].
class SignalRestoreMonitoredEvent extends SignalEvent {
  /// Signal paths to restore into the monitor list.
  final List<String> signalPaths;

  /// Per-signal metadata for sub-field entries (from file save/load).
  /// If null, overrides are derived at restore time from the signal ID
  /// structure and the parent signal's logicType.
  final Map<String, ({int width, String displayName})>? metadata;

  /// Per-row display formats, ordered to match [signalPaths].
  final List<MonitorValueFormat>? valueFormats;

  /// Per-row group names, ordered to match [signalPaths].
  final List<String?>? monitorGroups;

  /// Whether paths without loaded waveform data should be omitted.
  ///
  /// Cross-probe senders may include an internal signal followed by a directly
  /// connected port driver. The internal signal is omitted when it has no
  /// waveform, leaving the usable driver in the monitor list.
  final bool skipUnavailableSignals;

  /// Creates an event that restores monitored signals.
  SignalRestoreMonitoredEvent(
    this.signalPaths, {
    this.metadata,
    this.valueFormats,
    this.monitorGroups,
    this.skipUnavailableSignals = false,
  });

  @override
  List<Object?> get props => [
        signalPaths,
        metadata,
        valueFormats,
        monitorGroups,
        skipUnavailableSignals,
      ];
}

/// Triggers a refresh of the signal display to show updated waveform data.
/// Used when incremental waveform data arrives from live simulation.
///
/// When [cacheOnly] is true, the refresh reads from the repository cache
/// without making any network/VM-service calls.  This is essential for
/// breakpoint-triggered updates: the data is already in the cache (put there
/// by cached append operations, and calling the data-source during an isolate
/// pause would hang because service-extensions can't run while paused.
class SignalRefreshEvent extends SignalEvent {
  /// Whether to refresh strictly from cached data.
  final bool cacheOnly;

  /// Whether this refresh establishes a new waveform-session baseline.
  ///
  /// Backend replacements set this so undo cannot restore rows or samples
  /// captured from the previous waveform.
  final bool resetMonitorHistory;

  /// Creates a signal refresh event.
  SignalRefreshEvent({
    this.cacheOnly = false,
    this.resetMonitorHistory = false,
  });

  @override
  List<Object?> get props => [cacheOnly, resetMonitorHistory];
}

/// Toggles the display of internal signals (wires, registers) in the signal
/// list. When enabled, internal signals are shown alongside ports. When
/// disabled, only ports are displayed.
class SignalToggleInternalSignalsEvent extends SignalEvent {
  /// Whether internal signals should be shown.
  final bool enable;

  /// Creates an internal-signal visibility toggle event.
  SignalToggleInternalSignalsEvent({required this.enable});

  @override
  List<Object?> get props => [enable];
}

/// Reorders a signal in the monitor list by moving it from one position to
/// another.
class SignalReorderEvent extends SignalEvent {
  /// Original index of the moved signal.
  final int oldIndex;

  /// New index of the moved signal.
  final int newIndex;

  /// Creates a signal reorder event.
  SignalReorderEvent({required this.oldIndex, required this.newIndex});

  @override
  List<Object?> get props => [oldIndex, newIndex];
}

/// Reorders a group of signals, maintaining their relative order.
///
/// [oldIndices] are the original sorted ascending indices of the group.
/// [anchorOldIndex] is the index of the row the user grabbed.
/// [anchorNewIndex] is where that row would land after the drag.
class SignalGroupReorderEvent extends SignalEvent {
  /// Sorted original indices for the dragged group.
  final List<int> oldIndices;

  /// Original index of the dragged anchor row.
  final int anchorOldIndex;

  /// New index for the dragged anchor row.
  final int anchorNewIndex;

  /// Creates a grouped signal reorder event.
  SignalGroupReorderEvent({
    required this.oldIndices,
    required this.anchorOldIndex,
    required this.anchorNewIndex,
  });

  @override
  List<Object?> get props => [oldIndices, anchorOldIndex, anchorNewIndex];
}

/// Loads a list of resolved [SignalOccurrence] objects and **appends** them to
/// the current monitor list (skipping duplicates).  Used by the "load signal
/// list" feature.
///
/// The caller is responsible for resolving signal IDs (from JSON) to
/// [SignalOccurrence] objects via [OccurrenceAddress.tryFromPathname] +
/// [HierarchyService.signalByAddress] before dispatching this event.
class SignalLoadListEvent extends SignalEvent {
  /// Resolved signals to add to the monitor list.
  final List<SignalOccurrence> signals;

  /// Creates an event that loads a resolved signal list.
  SignalLoadListEvent(this.signals);

  @override
  List<Object?> get props => [signals];
}

// ─────────────── Module Signals filter / sort / selection events ──────────

/// Sets the filter text for the Module Signals panel.
/// Empty string clears the filter (shows all signals).
class SignalFilterEvent extends SignalEvent {
  /// Filter text applied to the module signal list.
  final String filterText;

  /// Creates a signal filter event.
  SignalFilterEvent(this.filterText);

  @override
  List<Object?> get props => [filterText];
}

/// Toggles alphabetical sort direction for the Module Signals panel.
/// null = unsorted, true = ascending, false = descending.
class SignalSortEvent extends SignalEvent {
  /// Sort direction, or null to clear sorting.
  final bool? ascending;

  /// Creates a signal sort event.
  SignalSortEvent({required this.ascending});

  @override
  List<Object?> get props => [ascending];
}

/// Selects a single signal in the Module Signals panel (plain click).
/// Replaces the current module selection with just this signal.
class ModuleSignalSelectEvent extends SignalEvent {
  /// Identifier of the module signal to select.
  final String signalId;

  /// Creates a module signal selection event.
  ModuleSignalSelectEvent(this.signalId);

  @override
  List<Object?> get props => [signalId];
}

/// Toggles a signal in the Module Signals panel selection (Ctrl+click).
class ModuleSignalToggleEvent extends SignalEvent {
  /// Identifier of the module signal to toggle.
  final String signalId;

  /// Creates a module signal toggle event.
  ModuleSignalToggleEvent(this.signalId);

  @override
  List<Object?> get props => [signalId];
}

/// Range-selects signals in the Module Signals panel (Shift+click).
/// Selects all signals between [anchorIndex] and [extentIndex] inclusive
/// from the current filteredSignals list.
class ModuleSignalRangeSelectEvent extends SignalEvent {
  /// The first selected module-signal row index.
  final int anchorIndex;

  /// The last selected module-signal row index.
  final int extentIndex;

  /// Creates a module signal range selection event.
  ModuleSignalRangeSelectEvent({
    required this.anchorIndex,
    required this.extentIndex,
  });

  @override
  List<Object?> get props => [anchorIndex, extentIndex];
}

/// Clears all module-signal selections.
class ModuleSignalClearSelectionEvent extends SignalEvent {
  @override
  List<Object?> get props => [];
}

/// Adds all currently module-selected signals to the monitor (waveform) list.
class ModuleSignalAddToMonitorEvent extends SignalEvent {
  @override
  List<Object?> get props => [];
}

/// Removes all currently module-selected signals from the monitor list
/// (if they are present).
class ModuleSignalRemoveFromMonitorEvent extends SignalEvent {
  @override
  List<Object?> get props => [];
}

/// Selects all signals in the Module Signals panel (Ctrl+A).
class ModuleSignalSelectAllEvent extends SignalEvent {
  @override
  List<Object?> get props => [];
}

/// Focuses all signals in the Selected Signals panel (Ctrl+A).
class SignalFocusAllEvent extends SignalEvent {
  @override
  List<Object?> get props => [];
}

/// Expands a struct/array signal in the monitor list, inserting sub-field
/// waveforms immediately after the parent signal.
///
/// The sub-fields are determined from the parent signal's logic-type
/// metadata (struct fields or array elements).
///
/// When [fieldIndices] is non-null, only the specified descriptor indices
/// are expanded.  When null, all sub-fields are inserted.
class SignalExpandMonitorEvent extends SignalEvent {
  /// The waveform entry in the monitor list to expand.
  final SignalWaveform waveform;

  /// Index of the waveform in the monitor list.
  final int index;

  /// Optional subset of sub-field descriptor indices to expand.
  /// When null, all sub-fields are expanded.
  final List<int>? fieldIndices;

  /// Creates an event that expands a monitored signal.
  SignalExpandMonitorEvent({
    required this.waveform,
    required this.index,
    this.fieldIndices,
  });

  @override
  List<Object?> get props => [waveform, index, fieldIndices];
}

/// Collapses a previously expanded struct/array signal in the monitor list,
/// removing its sub-field waveform entries.
class SignalCollapseMonitorEvent extends SignalEvent {
  /// The waveform entry in the monitor list to collapse.
  final SignalWaveform waveform;

  /// Creates an event that collapses a monitored signal.
  SignalCollapseMonitorEvent({required this.waveform});

  @override
  List<Object?> get props => [waveform];
}

/// Adds a sub-field of a struct/array signal to the monitor list.
///
/// When the sub-field doesn't exist as a tracked signal in the hierarchy,
/// this creates a bit-slice computed waveform using the parent's data.
/// The signal ID uses the `#` sub-field path convention:
///   `{parentPath}#{fieldLabel}`
class SignalSubFieldSelectedEvent extends SignalEvent {
  /// The parent struct/array signal.
  final SignalOccurrence parentSignal;

  /// The field label (for example, `mantissa`, `[0]`, or `b[31:21]`).
  final String fieldLabel;

  /// Start bit within the parent signal.
  final int startBit;

  /// Width of this sub-field in bits.
  final int width;

  /// Optional display name override (e.g. user-defined "exponent").
  final String? overrideName;

  /// Creates an event that adds a sub-field waveform.
  SignalSubFieldSelectedEvent({
    required this.parentSignal,
    required this.fieldLabel,
    required this.startBit,
    required this.width,
    String? displayName,
    String? overrideName,
  }) : overrideName = overrideName ?? displayName;

  @override
  List<Object?> get props => [
        parentSignal,
        fieldLabel,
        startBit,
        width,
        overrideName,
      ];
}

/// Expands a multi-bit signal into individual bit (or bit-range) waveforms
/// and adds them to the monitor list immediately after the parent.
///
/// Uses the `#b[high:low]` convention for signal IDs so the repository
/// synthesises bit-sliced waveforms from the parent's data.  Single bits
/// use `#b[N]`.  The `b` prefix denotes flat bitvector access, distinct
/// from structural access (`#[N]` for array elements, `#field` for structs).
///
/// When [bitStart] and [bitEnd] are provided, only those bits are expanded.
/// When null, all bits (0..width-1) are expanded as individual 1-bit signals.
class SignalBitExpandEvent extends SignalEvent {
  /// The monitored waveform to expand (must already be in the monitor list).
  final SignalWaveform waveform;

  /// Index of [waveform] in the monitor list (for insertion after it).
  final int index;

  /// First bit to expand (inclusive, LSB-indexed). Defaults to 0.
  final int bitStart;

  /// Last bit to expand (inclusive, LSB-indexed). Defaults to width-1.
  final int bitEnd;

  /// Creates an event that expands bits from a monitored waveform.
  SignalBitExpandEvent({
    required this.waveform,
    required this.index,
    required this.bitStart,
    required this.bitEnd,
  });

  @override
  List<Object?> get props => [waveform, index, bitStart, bitEnd];
}

/// Splits a monitored bitvector into contiguous chunks after an LSB offset.
///
/// Bits below [bitOffset] are left unsplit. The final chunk may be narrower
/// than [chunkWidth].
class SignalBitChunkEvent extends SignalEvent {
  /// The monitored waveform to split.
  final SignalWaveform waveform;

  /// Index of [waveform] in the monitor list.
  final int index;

  /// First bit included in chunking, indexed from the LSB.
  final int bitOffset;

  /// Preferred width of each generated chunk.
  final int chunkWidth;

  /// Creates a chunk-splitting event.
  SignalBitChunkEvent({
    required this.waveform,
    required this.index,
    required this.bitOffset,
    required this.chunkWidth,
  });

  @override
  List<Object?> get props => [waveform, index, bitOffset, chunkWidth];
}

/// Adds named bit-field waveforms to the monitor list after the parent.
///
/// Each [BitFieldDef] creates a `signal#b[high:low]` sub-waveform with the
/// given display name.  This allows the user to overlay a virtual structure
/// onto a flat bitvector signal.
class SignalBitFieldsEvent extends SignalEvent {
  /// The monitored waveform to define fields on.
  final SignalWaveform waveform;

  /// Index of [waveform] in the monitor list (for insertion after it).
  final int index;

  /// The named field definitions.
  final List<BitFieldDef> fields;

  /// Creates an event that adds named bit fields.
  SignalBitFieldsEvent({
    required this.waveform,
    required this.index,
    required this.fields,
  });

  @override
  List<Object?> get props => [waveform, index, fields];
}
