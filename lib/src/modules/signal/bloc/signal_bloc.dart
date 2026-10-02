// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_bloc.dart
// The BLoC for the signal module.
//
// 2024 April
// Author(s): Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
//            Yao Jing Quek <yao.jing.quek@intel.com>

import 'dart:developer' as dev;

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart'
    show BitFieldDef, SignalValueFormat, SignalValueFormatRegistry;
import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_wave_viewer/src/modules/signal/utils/signal_display_utils.dart';
import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';

part 'signal_event.dart';
part 'signal_state.dart';

class _MonitorSnapshot {
  final List<SignalWaveform> monitorSignals;
  final Set<String> focusedMonitorIds;
  final Set<String> expandedMonitorIds;

  _MonitorSnapshot({
    required this.monitorSignals,
    required this.focusedMonitorIds,
    required this.expandedMonitorIds,
  });

  factory _MonitorSnapshot.fromState(SignalLoaded state) => _MonitorSnapshot(
        monitorSignals: state.monitorSignalsList
            .map(
              (waveform) => SignalWaveform.copyFrom(waveform,
                  monitorId: waveform.monitorId),
            )
            .toList(),
        focusedMonitorIds: Set<String>.from(state.focusedSignalIds),
        expandedMonitorIds: Set<String>.from(state.expandedMonitorSignals),
      );
}

({int high, int low})? _parseBitSlice(String value) {
  if (!value.startsWith('b[') || !value.endsWith(']')) {
    return null;
  }
  final range = value.substring(2, value.length - 1);
  final separator = range.indexOf(':');
  final high = int.tryParse(
    separator < 0 ? range : range.substring(0, separator),
  );
  final low =
      separator < 0 ? high : int.tryParse(range.substring(separator + 1));
  if (high == null || low == null || range.indexOf(':', separator + 1) >= 0) {
    return null;
  }
  return (high: high, low: low);
}

/// BLoC that manages available signals, monitored signals, and focus state.
class SignalBloc extends Bloc<SignalEvent, SignalState> {
  static const _maxMonitorHistory = 100;

  final SignalWaveformRepository _signalWaveformRepository;
  final _undoMonitorHistory = <_MonitorSnapshot>[];
  final _redoMonitorHistory = <_MonitorSnapshot>[];

  /// SignalOccurrence hierarchy paths to restore on the first
  /// [SignalUpdateEvent].
  ///
  /// Populated from a previous connection's monitored signals. Cleared after
  /// the first module selection triggers the restore so it only fires once.
  List<String>? _pendingSignalRestore;

  final Map<String, MonitorValueFormat> _occurrenceValueFormats = {};

  /// Creates a signal BLoC.
  SignalBloc(
    SignalWaveformRepository signalWaveformRepository, {
    List<String>? initialMonitoredSignalPaths,
    bool initialShowInternalSignals = false,
  })  : _signalWaveformRepository = signalWaveformRepository,
        _pendingSignalRestore = initialMonitoredSignalPaths,
        super(SignalLoading(showInternalSignals: initialShowInternalSignals)) {
    on<SignalUpdateEvent>(updateSignals);
    on<SignalSelectedEvent>(addSignalToMonitor);
    on<SignalRestoreMonitoredEvent>(_restoreMonitoredSignals);
    on<SignalFocusEvent>(focusSignal);
    on<SignalRangeFocusEvent>(rangeFocusSignal);
    on<SignalUnfocusEvent>(unfocusSignal);
    on<SignalUnfocusOneEvent>(unfocusOneSignal);
    on<SignalRemoveEvent>(removeSignal);
    on<SignalRemoveManyEvent>(_removeManySignals);
    on<SignalUndoMonitorEvent>(_undoMonitorEdit);
    on<SignalRedoMonitorEvent>(_redoMonitorEdit);
    on<SignalSetValueFormatEvent>(_setValueFormat);
    on<SignalSetOccurrenceValueFormatEvent>(_setOccurrenceValueFormat);
    on<SignalSetMonitorGroupEvent>(_setMonitorGroup);
    on<SignalResetEvent>(resetSignals);
    on<SignalRefreshEvent>(refreshSignals);
    on<SignalToggleInternalSignalsEvent>(toggleInternalSignals);
    on<SignalReorderEvent>(reorderSignal);
    on<SignalGroupReorderEvent>(reorderSignalGroup);
    on<SignalLoadListEvent>(loadSignalList);
    on<SignalFilterEvent>(_onFilter);
    on<SignalSortEvent>(_onSort);
    on<ModuleSignalSelectEvent>(_onModuleSignalSelect);
    on<ModuleSignalToggleEvent>(_onModuleSignalToggle);
    on<ModuleSignalRangeSelectEvent>(_onModuleSignalRangeSelect);
    on<ModuleSignalClearSelectionEvent>(_onModuleSignalClearSelection);
    on<ModuleSignalAddToMonitorEvent>(_onModuleSignalAddToMonitor);
    on<ModuleSignalRemoveFromMonitorEvent>(_onModuleSignalRemoveFromMonitor);
    on<ModuleSignalSelectAllEvent>(_onModuleSignalSelectAll);
    on<SignalFocusAllEvent>(_onFocusAll);
    on<SignalSubFieldSelectedEvent>(_onSubFieldSelected);
    on<SignalExpandMonitorEvent>(_onExpandMonitor);
    on<SignalCollapseMonitorEvent>(_onCollapseMonitor);
    on<SignalBitExpandEvent>(_onBitExpand);
    on<SignalBitChunkEvent>(_onBitChunks);
    on<SignalBitFieldsEvent>(_onBitFields);
  }

  /// Whether the most recent monitor-list edit can be reversed.
  bool get canUndoMonitorEdit => _undoMonitorHistory.isNotEmpty;

  /// Whether an undone monitor-list edit can be reapplied.
  bool get canRedoMonitorEdit => _redoMonitorHistory.isNotEmpty;

  void _recordMonitorEdit() {
    final currentState = state;
    if (currentState is! SignalLoaded) {
      return;
    }
    _undoMonitorHistory.add(_MonitorSnapshot.fromState(currentState));
    if (_undoMonitorHistory.length > _maxMonitorHistory) {
      _undoMonitorHistory.removeAt(0);
    }
    _redoMonitorHistory.clear();
  }

  void _undoMonitorEdit(
    SignalUndoMonitorEvent event,
    Emitter<SignalState> emit,
  ) {
    final currentState = state;
    if (currentState is! SignalLoaded || _undoMonitorHistory.isEmpty) {
      return;
    }
    _redoMonitorHistory.add(_MonitorSnapshot.fromState(currentState));
    _emitMonitorSnapshot(_undoMonitorHistory.removeLast(), currentState, emit);
  }

  void _redoMonitorEdit(
    SignalRedoMonitorEvent event,
    Emitter<SignalState> emit,
  ) {
    final currentState = state;
    if (currentState is! SignalLoaded || _redoMonitorHistory.isEmpty) {
      return;
    }
    _undoMonitorHistory.add(_MonitorSnapshot.fromState(currentState));
    _emitMonitorSnapshot(_redoMonitorHistory.removeLast(), currentState, emit);
  }

  void _emitMonitorSnapshot(
    _MonitorSnapshot snapshot,
    SignalLoaded currentState,
    Emitter<SignalState> emit,
  ) {
    emit(
      SignalLoaded(
        currentState.signals,
        snapshot.monitorSignals,
        focusedSignalIds: snapshot.focusedMonitorIds,
        showInternalSignals: currentState.showInternalSignals,
        selectedModulePath: currentState.selectedModulePath,
        filterText: currentState.filterText,
        sortAscending: currentState.sortAscending,
        moduleSelectedSignalIds: currentState.moduleSelectedSignalIds,
        expandedMonitorSignals: snapshot.expandedMonitorIds,
      ),
    );
  }

  void _setValueFormat(
    SignalSetValueFormatEvent event,
    Emitter<SignalState> emit,
  ) {
    if (event.monitorIds.isEmpty) {
      return;
    }
    final updatedRows = state.monitorSignalsList.map((waveform) {
      if (!event.monitorIds.contains(waveform.monitorId)) {
        return waveform;
      }
      return SignalWaveform.copyFrom(waveform, monitorId: waveform.monitorId)
        ..valueFormat = event.valueFormat;
    }).toList();
    _recordMonitorEdit();
    emit(
      SignalLoaded(
        state.signals,
        updatedRows,
        focusedSignalIds: state.focusedSignalIds,
        showInternalSignals: state.showInternalSignals,
        selectedModulePath: state.selectedModulePath,
        filterText: state.filterText,
        sortAscending: state.sortAscending,
        moduleSelectedSignalIds: state.moduleSelectedSignalIds,
        expandedMonitorSignals: state.expandedMonitorSignals,
      ),
    );
  }

  /// Returns the occurrence format currently selected for [signalPath].
  MonitorValueFormat valueFormatForSignalPath(String signalPath) =>
      _occurrenceValueFormats[signalPath] ?? MonitorValueFormat.waveform;

  MonitorValueFormat _valueFormatForNewSignal(
    String signalPath, {
    OccurrenceAddress? address,
  }) {
    final registeredFormat = SignalValueFormatRegistry.formatForAny([
      address,
    ]);
    if (registeredFormat == SignalValueFormat.waveform) {
      return valueFormatForSignalPath(signalPath);
    }
    return MonitorValueFormat.values.firstWhere(
      (format) =>
          format.name ==
          SignalValueFormatRegistry.formatToString(registeredFormat),
      orElse: () => valueFormatForSignalPath(signalPath),
    );
  }

  void _setOccurrenceValueFormat(
    SignalSetOccurrenceValueFormatEvent event,
    Emitter<SignalState> emit,
  ) {
    if (event.signalPaths.isEmpty) {
      return;
    }
    for (final path in event.signalPaths) {
      _occurrenceValueFormats[path] = event.valueFormat;
    }

    final updatedRows = state.monitorSignalsList.map((waveform) {
      final path = waveform.fullPath ?? waveform.signalId;
      if (!event.signalPaths.contains(path)) {
        return waveform;
      }
      return SignalWaveform.copyFrom(waveform, monitorId: waveform.monitorId)
        ..valueFormat = event.valueFormat;
    }).toList();

    _recordMonitorEdit();
    emit(
      SignalLoaded(
        state.signals,
        updatedRows,
        focusedSignalIds: state.focusedSignalIds,
        showInternalSignals: state.showInternalSignals,
        selectedModulePath: state.selectedModulePath,
        filterText: state.filterText,
        sortAscending: state.sortAscending,
        moduleSelectedSignalIds: state.moduleSelectedSignalIds,
        expandedMonitorSignals: state.expandedMonitorSignals,
      ),
    );
  }

  void _setMonitorGroup(
    SignalSetMonitorGroupEvent event,
    Emitter<SignalState> emit,
  ) {
    if (event.monitorIds.isEmpty) {
      return;
    }
    final groupName = event.groupName?.trim();
    final updatedRows = state.monitorSignalsList.map((waveform) {
      if (!event.monitorIds.contains(waveform.monitorId)) {
        return waveform;
      }
      return SignalWaveform.copyFrom(waveform, monitorId: waveform.monitorId)
        ..monitorGroup = groupName?.isEmpty ?? true ? null : groupName;
    }).toList();
    _recordMonitorEdit();
    emit(
      SignalLoaded(
        state.signals,
        updatedRows,
        focusedSignalIds: state.focusedSignalIds,
        showInternalSignals: state.showInternalSignals,
        selectedModulePath: state.selectedModulePath,
        filterText: state.filterText,
        sortAscending: state.sortAscending,
        moduleSelectedSignalIds: state.moduleSelectedSignalIds,
        expandedMonitorSignals: state.expandedMonitorSignals,
      ),
    );
  }

  /// Updates the available signal list for the currently selected module.
  void updateSignals(SignalUpdateEvent event, Emitter<SignalState> emit) {
    final signals = _signalWaveformRepository.getSignalsBySelectedModule(
      event.selectedModule,
    );

    emit(
      SignalLoaded(
        signals,
        state.monitorSignalsList,
        focusedSignalIds: state.focusedSignalIds,
        showInternalSignals: state.showInternalSignals,
        selectedModulePath: event.selectedModule.path(),
        filterText: state.filterText,
        sortAscending: state.sortAscending,
        expandedMonitorSignals: state.expandedMonitorSignals,
      ),
    );

    // Restore previously monitored signals after the first module loads.
    // Fires a single batch event so signals are loaded sequentially within
    // one handler, preserving their original order.
    if (_pendingSignalRestore != null && _pendingSignalRestore!.isNotEmpty) {
      final paths = _pendingSignalRestore!;
      _pendingSignalRestore = null;
      add(SignalRestoreMonitoredEvent(paths));
    } else {
      _pendingSignalRestore = null;
    }
  }

  /// Adds a selected signal to the monitored waveform list.
  Future<void> addSignalToMonitor(
    SignalSelectedEvent event,
    Emitter<SignalState> emit,
  ) async {
    // Duplicates allowed for performance studies — skip the focus/scroll
    // behavior and just add another instance directly.

    // Use the signal's OccurrenceAddress for O(1) cache lookup.
    final signalAddr = event.selectedSignal.address;
    final signalKey = event.selectedSignal.path();
    dev.log('addSignalToMonitor: requesting $signalKey', name: 'SignalBloc');

    // Only fetch from the backend if we don't already have real data.
    // _buildSignalCache() pre-populates _waveformCache with empty
    // SignalWaveform entries for every signal in the hierarchy, so a
    // non-null result from getWaveform does NOT mean data was fetched.
    // Check data.isEmpty to distinguish placeholders from real data.
    var cachedWaveform = signalAddr != null
        ? _signalWaveformRepository.getWaveform(signalAddr)
        : _signalWaveformRepository.getWaveformById(signalKey);
    if (cachedWaveform == null || cachedWaveform.data.isEmpty) {
      await _signalWaveformRepository.loadAndAppendWaveformData(
        signalIds: [signalKey],
      );
      cachedWaveform = signalAddr != null
          ? _signalWaveformRepository.getWaveform(signalAddr)
          : _signalWaveformRepository.getWaveformById(signalKey);
      dev.log(
        'addSignalToMonitor: fetched $signalKey -> '
        '${cachedWaveform?.data.length ?? 0} points',
        name: 'SignalBloc',
      );
    }

    // Create a COPY of the waveform for this monitor entry. This is critical
    // for duplicate signal support: when the same signal is added multiple
    // times, each monitor entry must have its own SignalWaveform instance.
    // Otherwise, all duplicates share the same object reference, which causes
    // visual corruption after reorder (painters read from the same data, strip
    // cache can't distinguish rows, etc.).
    final waveform = (cachedWaveform != null
        ? SignalWaveform.copyFrom(cachedWaveform)
        : SignalWaveform.empty(signalKey))
      ..valueFormat = _valueFormatForNewSignal(
        signalKey,
        address: signalAddr,
      );

    _recordMonitorEdit();
    emit(
      SignalLoaded(
        state.signals,
        [...state.monitorSignalsList, waveform],
        focusedSignalIds: state.focusedSignalIds,
        showInternalSignals: state.showInternalSignals,
        selectedModulePath: state.selectedModulePath,
        filterText: state.filterText,
        sortAscending: state.sortAscending,
        moduleSelectedSignalIds: state.moduleSelectedSignalIds,
        expandedMonitorSignals: state.expandedMonitorSignals,
      ),
    );
  }

  /// Restores a list of previously monitored signals after a reconnect.
  ///
  /// Loads each signal sequentially within a single handler so the final
  /// monitor list order matches the saved order, then emits one state update.
  Future<void> _restoreMonitoredSignals(
    SignalRestoreMonitoredEvent event,
    Emitter<SignalState> emit,
  ) async {
    final signalPaths = event.skipUnavailableSignals
        ? event.signalPaths
            .map(_resolveIncomingSignalPath)
            .whereType<String>()
            .toList()
        : event.signalPaths;

    // Batch: fetch all signals in one API call instead of one-at-a-time.
    await _signalWaveformRepository.loadAndAppendWaveformData(
      signalIds: signalPaths,
    );

    final restoredSignals = <SignalWaveform>[];
    for (var index = 0; index < signalPaths.length; index++) {
      final path = signalPaths[index];
      final cached = _signalWaveformRepository.getWaveformById(path);
      if (event.skipUnavailableSignals &&
          (cached == null || cached.data.isEmpty)) {
        continue;
      }
      final waveform = (cached != null
          ? SignalWaveform.copyFrom(cached)
          : SignalWaveform.empty(path))
        ..valueFormat =
            event.valueFormats != null && index < event.valueFormats!.length
                ? event.valueFormats![index]
                : MonitorValueFormat.waveform
        ..monitorGroup =
            event.monitorGroups != null && index < event.monitorGroups!.length
                ? event.monitorGroups![index]
                : null;

      // Set overrides for sub-field / bit-slice waveforms.
      if (path.contains('#')) {
        final meta = event.metadata?[path];
        if (meta != null) {
          // Use explicit metadata from save file.
          waveform
            ..overrideWidth = meta.width
            ..overrideName = meta.displayName;
        } else {
          // Derive from the signal ID structure.
          _deriveSubFieldOverrides(waveform, path);
        }
      }

      restoredSignals.add(waveform);
    }

    emit(
      SignalLoaded(
        state.signals,
        [...state.monitorSignalsList, ...restoredSignals],
        focusedSignalIds: state.focusedSignalIds,
        showInternalSignals: state.showInternalSignals,
        selectedModulePath: state.selectedModulePath,
        filterText: state.filterText,
        sortAscending: state.sortAscending,
        moduleSelectedSignalIds: state.moduleSelectedSignalIds,
        expandedMonitorSignals: state.expandedMonitorSignals,
      ),
    );
  }

  String? _resolveIncomingSignalPath(String requestedPath) {
    final separator = requestedPath.indexOf('#');
    final basePath =
        separator < 0 ? requestedPath : requestedPath.substring(0, separator);
    final suffix = separator < 0 ? '' : requestedPath.substring(separator);
    final knownIds = _signalWaveformRepository.cachedSignalIds;

    if (knownIds.contains(basePath)) {
      return requestedPath;
    }

    final slashPath = basePath.replaceAll('.', '/');
    if (knownIds.contains(slashPath)) {
      return '$slashPath$suffix';
    }

    final firstSeparator = slashPath.indexOf('/');
    if (firstSeparator < 0 || firstSeparator == slashPath.length - 1) {
      return null;
    }
    final hierarchyTail = slashPath.substring(firstSeparator + 1);
    final matches = knownIds
        .where((id) => id == hierarchyTail || id.endsWith('/$hierarchyTail'))
        .toList();
    return matches.length == 1 ? '${matches.single}$suffix' : null;
  }

  /// Derive `overrideWidth` and `overrideName` for a sub-field waveform
  /// from the signal ID structure and the parent signal's logicType metadata.
  void _deriveSubFieldOverrides(SignalWaveform waveform, String signalId) {
    final hashIdx = signalId.indexOf('#');
    if (hashIdx < 0) {
      return;
    }

    final parentPath = signalId.substring(0, hashIdx);
    final fieldLabel = signalId.substring(hashIdx + 1);

    // Derive display name: parentName + indices with dots removed.
    final parentName = parentPath.contains('/')
        ? parentPath.substring(parentPath.lastIndexOf('/') + 1)
        : parentPath;

    // Handle bit-slice patterns: b[N] or b[high:low]
    final bitSlice = _parseBitSlice(fieldLabel);
    if (bitSlice != null) {
      final high = bitSlice.high;
      final low = bitSlice.low;
      waveform
        ..overrideWidth = (high - low).abs() + 1
        ..overrideName = '$parentName[$high${low != high ? ':$low' : ''}]';
      return;
    }

    final indices = fieldLabel.replaceAll('.', '');
    waveform.overrideName = '$parentName$indices';

    // Derive width from parent's logicType metadata.
    final parentSignal = _signalWaveformRepository.getSignalById(parentPath);
    final logicType = parentSignal?.logicType;
    if (logicType == null) {
      return;
    }

    final width = _resolveFieldWidth(logicType, fieldLabel);
    if (width != null) {
      waveform.overrideWidth = width;
    }
  }

  /// Walk a logicType map following a dot-separated field path to find
  /// the width of the target sub-field.
  ///
  /// Handles struct fields (by name) and array elements (by `[index]`).
  static int? _resolveFieldWidth(
    Map<String, Object?> logicType,
    String fieldPath,
  ) {
    // Split on '.' to handle nested paths like "[0].[2]" or "mantissa.sub"
    final segments = fieldPath.split('.');
    Map<String, Object?>? currentType = logicType;

    for (final segment in segments) {
      if (currentType == null) {
        return null;
      }

      final descriptors = SignalOccurrence.subFieldDescriptorsForType(
        currentType,
        '',
      );
      if (descriptors.isEmpty) {
        return null;
      }

      // Find matching descriptor by fieldLabel.
      final match = descriptors.where((d) => d.fieldLabel == segment);
      if (match.isEmpty) {
        return null;
      }

      final desc = match.first;
      if (segment == segments.last) {
        return desc.width;
      }
      currentType = desc.subLogicType;
    }

    return null;
  }

  /// Focus on a signal for data-point-by-data-point navigation.
  /// If isMultiSelect is true, toggle the signal in the focused set.
  /// Otherwise, replace the focused set with just this signal.
  void focusSignal(SignalFocusEvent event, Emitter<SignalState> emit) {
    final monitorId = event.waveform.monitorId;
    Set<String> newFocusedIds;

    if (event.isMultiSelect) {
      // Toggle the signal in the focused set
      if (state.focusedSignalIds.contains(monitorId)) {
        // Remove from set
        newFocusedIds = Set.from(state.focusedSignalIds)..remove(monitorId);
      } else {
        // Add to set
        newFocusedIds = Set.from(state.focusedSignalIds)..add(monitorId);
      }
    } else {
      // Replace the focused set with just this signal
      newFocusedIds = {monitorId};
    }

    emit(
      SignalLoaded(
        state.signals,
        state.monitorSignalsList,
        focusedSignalIds: newFocusedIds,
        showInternalSignals: state.showInternalSignals,
        selectedModulePath: state.selectedModulePath,
        filterText: state.filterText,
        sortAscending: state.sortAscending,
        moduleSelectedSignalIds: state.moduleSelectedSignalIds,
        expandedMonitorSignals: state.expandedMonitorSignals,
      ),
    );
  }

  /// Focus a contiguous range of signals in the monitor list (shift-click).
  ///
  /// Selects all signals between the anchor and extent indices, inclusive.
  void rangeFocusSignal(
    SignalRangeFocusEvent event,
    Emitter<SignalState> emit,
  ) {
    final list = state.monitorSignalsList;
    if (list.isEmpty) {
      return;
    }

    final lo = event.anchorIndex.clamp(0, list.length - 1);
    final hi = event.extentIndex.clamp(0, list.length - 1);
    final start = lo < hi ? lo : hi;
    final end = lo < hi ? hi : lo;

    final rangeIds = <String>{};
    for (var i = start; i <= end; i++) {
      rangeIds.add(list[i].monitorId);
    }

    emit(
      SignalLoaded(
        state.signals,
        state.monitorSignalsList,
        focusedSignalIds: rangeIds,
        showInternalSignals: state.showInternalSignals,
        selectedModulePath: state.selectedModulePath,
        filterText: state.filterText,
        sortAscending: state.sortAscending,
        moduleSelectedSignalIds: state.moduleSelectedSignalIds,
        expandedMonitorSignals: state.expandedMonitorSignals,
      ),
    );
  }

  /// Unfocus all signals; return to normal navigation.
  void unfocusSignal(SignalUnfocusEvent event, Emitter<SignalState> emit) {
    emit(
      SignalLoaded(
        state.signals,
        state.monitorSignalsList,
        showInternalSignals: state.showInternalSignals,
        selectedModulePath: state.selectedModulePath,
        filterText: state.filterText,
        sortAscending: state.sortAscending,
        moduleSelectedSignalIds: state.moduleSelectedSignalIds,
        expandedMonitorSignals: state.expandedMonitorSignals,
      ),
    );
  }

  /// Unfocus a specific signal from the multi-select set.
  void unfocusOneSignal(
    SignalUnfocusOneEvent event,
    Emitter<SignalState> emit,
  ) {
    final newFocusedIds = Set<String>.from(state.focusedSignalIds)
      ..remove(event.signalId);
    emit(
      SignalLoaded(
        state.signals,
        state.monitorSignalsList,
        focusedSignalIds: newFocusedIds,
        showInternalSignals: state.showInternalSignals,
        selectedModulePath: state.selectedModulePath,
        filterText: state.filterText,
        sortAscending: state.sortAscending,
        moduleSelectedSignalIds: state.moduleSelectedSignalIds,
        expandedMonitorSignals: state.expandedMonitorSignals,
      ),
    );
  }

  /// Remove a signal from the monitor list.
  void removeSignal(SignalRemoveEvent event, Emitter<SignalState> emit) {
    _recordMonitorEdit();
    final updatedList = state.monitorSignalsList
        .where((waveform) => waveform.monitorId != event.waveform.monitorId)
        .toList();

    // If the removed signal was focused, remove it from focused set
    final newFocusedIds = Set<String>.from(state.focusedSignalIds)
      ..remove(event.waveform.monitorId);

    emit(
      SignalLoaded(
        state.signals,
        updatedList,
        focusedSignalIds: newFocusedIds,
        showInternalSignals: state.showInternalSignals,
        selectedModulePath: state.selectedModulePath,
        filterText: state.filterText,
        sortAscending: state.sortAscending,
        moduleSelectedSignalIds: state.moduleSelectedSignalIds,
        expandedMonitorSignals: state.expandedMonitorSignals,
      ),
    );
  }

  /// Removes multiple monitor rows while preserving a single undo checkpoint.
  void _removeManySignals(
    SignalRemoveManyEvent event,
    Emitter<SignalState> emit,
  ) {
    if (event.monitorIds.isEmpty) {
      return;
    }

    final currentState = state;
    if (currentState is! SignalLoaded) {
      return;
    }
    final updatedList = currentState.monitorSignalsList
        .where((waveform) => !event.monitorIds.contains(waveform.monitorId))
        .toList();
    if (updatedList.length == currentState.monitorSignalsList.length) {
      return;
    }

    _recordMonitorEdit();
    emit(
      SignalLoaded(
        currentState.signals,
        updatedList,
        focusedSignalIds: Set<String>.from(currentState.focusedSignalIds)
          ..removeAll(event.monitorIds),
        showInternalSignals: currentState.showInternalSignals,
        selectedModulePath: currentState.selectedModulePath,
        filterText: currentState.filterText,
        sortAscending: currentState.sortAscending,
        moduleSelectedSignalIds: currentState.moduleSelectedSignalIds,
        expandedMonitorSignals: currentState.expandedMonitorSignals,
      ),
    );
  }

  /// Reset the signal bloc to initial state when loading a new file.
  void resetSignals(SignalResetEvent event, Emitter<SignalState> emit) {
    _occurrenceValueFormats.clear();
    emit(SignalLoading());
  }

  /// Refresh the signal display to show updated waveform data.
  /// Re-loads waveform data for monitored signals and emits updated state.
  Future<void> refreshSignals(
    SignalRefreshEvent event,
    Emitter<SignalState> emit,
  ) async {
    // Re-load waveform data for all monitored signals to pick up new
    // breakpoints
    final monitoredSignalIds =
        state.monitorSignalsList.map((waveform) => waveform.id).toList();

    // When cacheOnly is true (breakpoint-triggered updates), skip the
    // network call — data was already placed in the repo cache by
    // appendDataToSignal.  Calling the data source while the isolate is
    // paused would hang because service-extensions can't run during pause.
    if (!event.cacheOnly && monitoredSignalIds.isNotEmpty) {
      await _signalWaveformRepository.loadAndAppendWaveformData(
        signalIds: monitoredSignalIds,
      );
    }

    // Get updated waveforms from the repository.
    // Always create fresh copies: the repo cache entry may be the same object
    // reference as the current monitor entry (after a previous refresh).
    // Without a copy, Equatable sees identical references → considers the
    // state unchanged → BLoC silently drops the emit → UI never updates.
    final updatedMonitorList = state.monitorSignalsList.map((waveform) {
      final updated = _signalWaveformRepository.getWaveformById(waveform.id);
      if (updated != null) {
        return SignalWaveform.copyFrom(updated, monitorId: waveform.monitorId);
      }
      return waveform;
    }).toList();

    emit(
      SignalLoaded(
        state.signals,
        updatedMonitorList,
        focusedSignalIds: state.focusedSignalIds,
        showInternalSignals: state.showInternalSignals,
        selectedModulePath: state.selectedModulePath,
        filterText: state.filterText,
        sortAscending: state.sortAscending,
        moduleSelectedSignalIds: state.moduleSelectedSignalIds,
        expandedMonitorSignals: state.expandedMonitorSignals,
      ),
    );
  }

  /// Toggle the display of internal signals in the signal list.
  /// When enabled, internal signals are shown alongside ports.
  /// When disabled, only ports are displayed.
  void toggleInternalSignals(
    SignalToggleInternalSignalsEvent event,
    Emitter<SignalState> emit,
  ) {
    emit(
      SignalLoaded(
        state.signals,
        state.monitorSignalsList,
        focusedSignalIds: state.focusedSignalIds,
        showInternalSignals: event.enable,
        selectedModulePath: state.selectedModulePath,
        filterText: state.filterText,
        sortAscending: state.sortAscending,
        moduleSelectedSignalIds: state.moduleSelectedSignalIds,
        expandedMonitorSignals: state.expandedMonitorSignals,
      ),
    );
  }

  /// Reorder a signal in the monitor list.
  void reorderSignal(SignalReorderEvent event, Emitter<SignalState> emit) {
    _recordMonitorEdit();
    final list = List<SignalWaveform>.from(state.monitorSignalsList);
    final item = list.removeAt(event.oldIndex);
    list.insert(event.newIndex, item);

    emit(
      SignalLoaded(
        state.signals,
        list,
        focusedSignalIds: state.focusedSignalIds,
        showInternalSignals: state.showInternalSignals,
        selectedModulePath: state.selectedModulePath,
        filterText: state.filterText,
        sortAscending: state.sortAscending,
        moduleSelectedSignalIds: state.moduleSelectedSignalIds,
        expandedMonitorSignals: state.expandedMonitorSignals,
      ),
    );
  }

  /// Reorder a group of signals, maintaining their relative order.
  void reorderSignalGroup(
    SignalGroupReorderEvent event,
    Emitter<SignalState> emit,
  ) {
    _recordMonitorEdit();
    final list = List<SignalWaveform>.from(state.monitorSignalsList);
    final oldIndices = List<int>.from(event.oldIndices)..sort();

    // Extract group items in their original relative order.
    final groupItems = <SignalWaveform>[for (final i in oldIndices) list[i]];

    // Remove group items from list (reverse to preserve indices).
    for (var i = oldIndices.length - 1; i >= 0; i--) {
      list.removeAt(oldIndices[i]);
    }

    // Compute where the block should be inserted.
    // In the final arrangement the group block starts at
    // blockFirst = anchorNewIndex − anchorPosInGroup.
    // That equals the number of non-group rows before the block,
    // which maps directly to the insertion index in the reduced list.
    final anchorPosInGroup = oldIndices.indexOf(event.anchorOldIndex);
    final insertAt = (event.anchorNewIndex - anchorPosInGroup).clamp(
      0,
      list.length,
    );

    // Insert the entire block.
    list.insertAll(insertAt, groupItems);

    emit(
      SignalLoaded(
        state.signals,
        list,
        focusedSignalIds: state.focusedSignalIds,
        showInternalSignals: state.showInternalSignals,
        selectedModulePath: state.selectedModulePath,
        filterText: state.filterText,
        sortAscending: state.sortAscending,
        moduleSelectedSignalIds: state.moduleSelectedSignalIds,
        expandedMonitorSignals: state.expandedMonitorSignals,
      ),
    );
  }

  /// Load a list of pre-resolved signals and replace the current monitor list.
  ///
  /// Each [SignalOccurrence] was already looked up from the hierarchy by the
  /// caller (via [OccurrenceAddress.tryFromPathname] +
  /// [HierarchyService.signalByAddress]).  This handler follows the same path
  /// as [addSignalToMonitor]: load waveform data for each signal, then retrieve
  /// the cached [SignalWaveform].
  ///
  /// **Appends** the resolved signals to the existing monitor list rather than
  /// replacing it.  Duplicates are allowed.
  Future<void> loadSignalList(
    SignalLoadListEvent event,
    Emitter<SignalState> emit,
  ) async {
    // Start from the existing monitor list so loaded signals are appended.
    final existing = List<SignalWaveform>.from(state.monitorSignalsList);

    // Batch: collect all signal keys and fetch in one API call.
    final signalKeys = event.signals.map((s) => s.path()).toList();
    if (signalKeys.isNotEmpty) {
      await _signalWaveformRepository.loadAndAppendWaveformData(
        signalIds: signalKeys,
      );
    }

    for (final signal in event.signals) {
      final signalAddr = signal.address;
      final signalKey = signal.path();
      final cachedWaveform = signalAddr != null
          ? _signalWaveformRepository.getWaveform(signalAddr)
          : _signalWaveformRepository.getWaveformById(signalKey);
      final waveform = cachedWaveform != null
          ? SignalWaveform.copyFrom(cachedWaveform)
          : SignalWaveform.empty(signalKey);
      existing.add(waveform);
    }

    _recordMonitorEdit();
    emit(
      SignalLoaded(
        state.signals,
        existing,
        focusedSignalIds: state.focusedSignalIds,
        showInternalSignals: state.showInternalSignals,
        selectedModulePath: state.selectedModulePath,
        filterText: state.filterText,
        sortAscending: state.sortAscending,
        moduleSelectedSignalIds: state.moduleSelectedSignalIds,
        expandedMonitorSignals: state.expandedMonitorSignals,
      ),
    );
  }

  // ─────────────── Module Signals filter / sort / selection ──────────

  void _onFilter(SignalFilterEvent event, Emitter<SignalState> emit) {
    emit(
      SignalLoaded(
        state.signals,
        state.monitorSignalsList,
        focusedSignalIds: state.focusedSignalIds,
        showInternalSignals: state.showInternalSignals,
        selectedModulePath: state.selectedModulePath,
        filterText: event.filterText,
        sortAscending: state.sortAscending,
        expandedMonitorSignals: state.expandedMonitorSignals,
      ),
    );
  }

  void _onSort(SignalSortEvent event, Emitter<SignalState> emit) {
    emit(
      SignalLoaded(
        state.signals,
        state.monitorSignalsList,
        focusedSignalIds: state.focusedSignalIds,
        showInternalSignals: state.showInternalSignals,
        selectedModulePath: state.selectedModulePath,
        filterText: state.filterText,
        sortAscending: event.ascending,
        moduleSelectedSignalIds: state.moduleSelectedSignalIds,
        expandedMonitorSignals: state.expandedMonitorSignals,
      ),
    );
  }

  void _onModuleSignalSelect(
    ModuleSignalSelectEvent event,
    Emitter<SignalState> emit,
  ) {
    emit(
      SignalLoaded(
        state.signals,
        state.monitorSignalsList,
        focusedSignalIds: state.focusedSignalIds,
        showInternalSignals: state.showInternalSignals,
        selectedModulePath: state.selectedModulePath,
        filterText: state.filterText,
        sortAscending: state.sortAscending,
        moduleSelectedSignalIds: {event.signalId},
        expandedMonitorSignals: state.expandedMonitorSignals,
      ),
    );
  }

  void _onModuleSignalToggle(
    ModuleSignalToggleEvent event,
    Emitter<SignalState> emit,
  ) {
    final newIds = Set<String>.from(state.moduleSelectedSignalIds);
    if (newIds.contains(event.signalId)) {
      newIds.remove(event.signalId);
    } else {
      newIds.add(event.signalId);
    }
    emit(
      SignalLoaded(
        state.signals,
        state.monitorSignalsList,
        focusedSignalIds: state.focusedSignalIds,
        showInternalSignals: state.showInternalSignals,
        selectedModulePath: state.selectedModulePath,
        filterText: state.filterText,
        sortAscending: state.sortAscending,
        moduleSelectedSignalIds: newIds,
        expandedMonitorSignals: state.expandedMonitorSignals,
      ),
    );
  }

  void _onModuleSignalRangeSelect(
    ModuleSignalRangeSelectEvent event,
    Emitter<SignalState> emit,
  ) {
    final filtered = state.filteredSignals;
    if (filtered.isEmpty) {
      return;
    }
    final lo = event.anchorIndex.clamp(0, filtered.length - 1);
    final hi = event.extentIndex.clamp(0, filtered.length - 1);
    final start = lo < hi ? lo : hi;
    final end = lo < hi ? hi : lo;

    final rangeIds = <String>{};
    for (var i = start; i <= end; i++) {
      rangeIds.add(filtered[i].path());
    }

    emit(
      SignalLoaded(
        state.signals,
        state.monitorSignalsList,
        focusedSignalIds: state.focusedSignalIds,
        showInternalSignals: state.showInternalSignals,
        selectedModulePath: state.selectedModulePath,
        filterText: state.filterText,
        sortAscending: state.sortAscending,
        moduleSelectedSignalIds: rangeIds,
        expandedMonitorSignals: state.expandedMonitorSignals,
      ),
    );
  }

  void _onModuleSignalClearSelection(
    ModuleSignalClearSelectionEvent event,
    Emitter<SignalState> emit,
  ) {
    emit(
      SignalLoaded(
        state.signals,
        state.monitorSignalsList,
        focusedSignalIds: state.focusedSignalIds,
        showInternalSignals: state.showInternalSignals,
        selectedModulePath: state.selectedModulePath,
        filterText: state.filterText,
        sortAscending: state.sortAscending,
        expandedMonitorSignals: state.expandedMonitorSignals,
      ),
    );
  }

  Future<void> _onModuleSignalAddToMonitor(
    ModuleSignalAddToMonitorEvent event,
    Emitter<SignalState> emit,
  ) async {
    // Find the actual SignalOccurrence objects for each selected ID.
    final selectedIds = state.moduleSelectedSignalIds;
    if (selectedIds.isEmpty) {
      return;
    }

    final signals = state.signals.where((s) => selectedIds.contains(s.path()));

    // Batch: collect all signal keys and fetch waveform data in one call.
    final signalKeys = signals.map((s) => s.path()).toList();
    if (signalKeys.isEmpty) {
      return;
    }

    await _signalWaveformRepository.loadAndAppendWaveformData(
      signalIds: signalKeys,
    );

    // Build waveform list from cache after the single batch fetch.
    final newWaveforms = <SignalWaveform>[];
    for (final signalKey in signalKeys) {
      final cached = _signalWaveformRepository.getWaveformById(signalKey);
      final waveform = (cached != null
          ? SignalWaveform.copyFrom(cached)
          : SignalWaveform.empty(signalKey))
        ..valueFormat = valueFormatForSignalPath(signalKey);
      newWaveforms.add(waveform);
    }

    // Single emit after all signals loaded.
    _recordMonitorEdit();
    emit(
      SignalLoaded(
        state.signals,
        [...state.monitorSignalsList, ...newWaveforms],
        focusedSignalIds: state.focusedSignalIds,
        showInternalSignals: state.showInternalSignals,
        selectedModulePath: state.selectedModulePath,
        filterText: state.filterText,
        sortAscending: state.sortAscending,
        expandedMonitorSignals: state.expandedMonitorSignals,
      ),
    );
  }

  void _onModuleSignalRemoveFromMonitor(
    ModuleSignalRemoveFromMonitorEvent event,
    Emitter<SignalState> emit,
  ) {
    final selectedIds = state.moduleSelectedSignalIds;
    if (selectedIds.isEmpty) {
      return;
    }

    final selectedSignals = state.signals
        .where((signal) => selectedIds.contains(signal.path()))
        .toList();
    bool isSelected(SignalWaveform waveform) =>
        selectedIds.contains(waveform.signalId) ||
        selectedSignals.any(waveform.matchesOccurrence);

    final removedMonitorIds = state.monitorSignalsList
        .where(isSelected)
        .map((waveform) => waveform.monitorId);
    final updatedList = state.monitorSignalsList
        .where((waveform) => !isSelected(waveform))
        .toList();

    final newFocusedIds = Set<String>.from(state.focusedSignalIds)
      ..removeAll(removedMonitorIds);

    _recordMonitorEdit();
    emit(
      SignalLoaded(
        state.signals,
        updatedList,
        focusedSignalIds: newFocusedIds,
        showInternalSignals: state.showInternalSignals,
        selectedModulePath: state.selectedModulePath,
        filterText: state.filterText,
        sortAscending: state.sortAscending,
        expandedMonitorSignals: state.expandedMonitorSignals,
      ),
    );
  }

  /// Select all visible signals in the Module Signals panel (Ctrl+A).
  void _onModuleSignalSelectAll(
    ModuleSignalSelectAllEvent event,
    Emitter<SignalState> emit,
  ) {
    final allIds = state.filteredSignals.map((s) => s.path()).toSet();
    emit(
      SignalLoaded(
        state.signals,
        state.monitorSignalsList,
        focusedSignalIds: state.focusedSignalIds,
        showInternalSignals: state.showInternalSignals,
        selectedModulePath: state.selectedModulePath,
        filterText: state.filterText,
        sortAscending: state.sortAscending,
        moduleSelectedSignalIds: allIds,
        expandedMonitorSignals: state.expandedMonitorSignals,
      ),
    );
  }

  /// Focus all signals in the Selected Signals panel (Ctrl+A).
  void _onFocusAll(SignalFocusAllEvent event, Emitter<SignalState> emit) {
    final allIds = state.monitorSignalsList.map((w) => w.monitorId).toSet();
    emit(
      SignalLoaded(
        state.signals,
        state.monitorSignalsList,
        focusedSignalIds: allIds,
        showInternalSignals: state.showInternalSignals,
        selectedModulePath: state.selectedModulePath,
        filterText: state.filterText,
        sortAscending: state.sortAscending,
        moduleSelectedSignalIds: state.moduleSelectedSignalIds,
        expandedMonitorSignals: state.expandedMonitorSignals,
      ),
    );
  }

  /// Add a sub-field of a struct/array signal to the monitor list.
  ///
  /// Uses the `#` sub-field path convention so the waveform API can
  /// synthesize the data via bit-slicing from the parent signal.
  Future<void> _onSubFieldSelected(
    SignalSubFieldSelectedEvent event,
    Emitter<SignalState> emit,
  ) async {
    // Build the sub-field signal ID using the # separator convention.
    final parentPath = event.parentSignal.path();
    final subFieldId = '$parentPath#${event.fieldLabel}';
    dev.log(
      'addSubFieldToMonitor: $subFieldId '
      '(bits [${event.startBit + event.width - 1}:${event.startBit}])',
      name: 'SignalBloc',
    );

    // Fetch the bit-sliced waveform via the repository.
    await _signalWaveformRepository.loadAndAppendWaveformData(
      signalIds: [subFieldId],
    );

    final cachedWaveform = _signalWaveformRepository.getWaveformById(
      subFieldId,
    );
    final waveform = (cachedWaveform != null
        ? SignalWaveform.copyFrom(cachedWaveform)
        : SignalWaveform.empty(subFieldId))
      // Set override metadata for sub-field waveforms that don't exist in the
      // hierarchy tree (so signal lookup returns null).
      ..overrideWidth = event.width
      ..valueFormat = valueFormatForSignalPath(subFieldId);

    // Use explicit override name if provided (user-defined bit-field),
    // otherwise build from fieldLabel.
    if (event.overrideName != null) {
      waveform.overrideName = event.overrideName;
    } else {
      // Build a display name like "deserialized[0][2]" from fieldLabel
      // "[0].[2]"
      final parentName = event.parentSignal.name;
      final indices = event.fieldLabel.replaceAll('.', '');
      waveform.overrideName = '$parentName$indices';
    }

    _recordMonitorEdit();
    emit(
      SignalLoaded(
        state.signals,
        [...state.monitorSignalsList, waveform],
        focusedSignalIds: state.focusedSignalIds,
        showInternalSignals: state.showInternalSignals,
        selectedModulePath: state.selectedModulePath,
        filterText: state.filterText,
        sortAscending: state.sortAscending,
        moduleSelectedSignalIds: state.moduleSelectedSignalIds,
        expandedMonitorSignals: state.expandedMonitorSignals,
      ),
    );
  }

  /// Expand a struct/array signal in the monitor list by inserting sub-field
  /// waveforms immediately after it.
  Future<void> _onExpandMonitor(
    SignalExpandMonitorEvent event,
    Emitter<SignalState> emit,
  ) async {
    final parentWaveform = event.waveform;
    final parentSignal = parentWaveform.signal;
    if (parentSignal == null) {
      return;
    }

    final descriptors = parentSignal.subFieldDescriptors;
    if (descriptors.isEmpty) {
      return;
    }

    // Filter to selected field indices if specified.
    final selectedIndices = event.fieldIndices;

    // Build sub-field waveforms for each descriptor.
    final subWaveforms = <SignalWaveform>[];
    for (var i = 0; i < descriptors.length; i++) {
      if (selectedIndices != null && !selectedIndices.contains(i)) {
        continue;
      }
      final desc = descriptors[i];
      final parentPath = parentSignal.path();
      final subFieldId = '$parentPath#${desc.fieldLabel}';

      // Check if the sub-field exists as a tracked signal in the hierarchy.
      SignalOccurrence? childSignal;
      final parentModule = parentSignal.parent;
      if (parentModule != null) {
        final idx = parentModule.signalIndexByName(desc.expectedName);
        if (idx >= 0) {
          childSignal = parentModule.signals[idx];
        }
      }

      if (childSignal != null) {
        // Sub-field exists as a real tracked signal — use its path.
        final childPath = childSignal.path();
        var cachedWaveform = _signalWaveformRepository.getWaveformById(
          childPath,
        );
        if (cachedWaveform == null || cachedWaveform.data.isEmpty) {
          await _signalWaveformRepository.loadAndAppendWaveformData(
            signalIds: [childPath],
          );
          cachedWaveform = _signalWaveformRepository.getWaveformById(childPath);
        }
        final waveform = cachedWaveform != null
            ? SignalWaveform.copyFrom(cachedWaveform)
            : SignalWaveform.empty(childPath);
        subWaveforms.add(waveform..monitorParentId = parentWaveform.monitorId);
      } else {
        // Use bit-slice computed waveform.
        await _signalWaveformRepository.loadAndAppendWaveformData(
          signalIds: [subFieldId],
        );
        final cachedWaveform = _signalWaveformRepository.getWaveformById(
          subFieldId,
        );
        final waveform = (cachedWaveform != null
            ? SignalWaveform.copyFrom(cachedWaveform, isComputed: true)
            : SignalWaveform.empty(subFieldId, isComputed: true))
          ..overrideWidth = desc.width;
        // Build display name like "parentName[0]" or "parentName_field"
        final parentName = parentSignal.name;
        final label = desc.fieldLabel;
        waveform
          ..overrideName = label.startsWith('[')
              ? '$parentName$label'
              : '${parentName}_$label'
          ..monitorParentId = parentWaveform.monitorId;
        subWaveforms.add(waveform);
      }
    }

    if (subWaveforms.isEmpty) {
      return;
    }

    // Insert sub-fields after the parent in the monitor list.
    final insertIndex = event.index + 1;
    final updatedList = List<SignalWaveform>.from(state.monitorSignalsList)
      ..insertAll(
        insertIndex.clamp(0, state.monitorSignalsList.length),
        subWaveforms,
      );

    final newExpanded = Set<String>.from(state.expandedMonitorSignals)
      ..add(parentWaveform.monitorId);

    _recordMonitorEdit();
    emit(
      SignalLoaded(
        state.signals,
        updatedList,
        focusedSignalIds: state.focusedSignalIds,
        showInternalSignals: state.showInternalSignals,
        selectedModulePath: state.selectedModulePath,
        filterText: state.filterText,
        sortAscending: state.sortAscending,
        moduleSelectedSignalIds: state.moduleSelectedSignalIds,
        expandedMonitorSignals: newExpanded,
      ),
    );
  }

  /// Collapse a previously expanded signal by removing its sub-field entries.
  void _onCollapseMonitor(
    SignalCollapseMonitorEvent event,
    Emitter<SignalState> emit,
  ) {
    final parentWaveform = event.waveform;
    final parentSignal = parentWaveform.signal;
    if (parentSignal == null) {
      return;
    }

    final descriptors = parentSignal.subFieldDescriptors;
    if (descriptors.isEmpty) {
      return;
    }

    final childMonitorIds = state.monitorSignalsList
        .where(
          (waveform) => waveform.monitorParentId == parentWaveform.monitorId,
        )
        .map((waveform) => waveform.monitorId)
        .toSet();
    final updatedList = state.monitorSignalsList
        .where((waveform) => !childMonitorIds.contains(waveform.monitorId))
        .toList();

    final newExpanded = Set<String>.from(state.expandedMonitorSignals)
      ..remove(parentWaveform.monitorId);

    // Remove any collapsed child IDs from focused set.
    final newFocused = Set<String>.from(state.focusedSignalIds)
      ..removeAll(childMonitorIds);

    _recordMonitorEdit();
    emit(
      SignalLoaded(
        state.signals,
        updatedList,
        focusedSignalIds: newFocused,
        showInternalSignals: state.showInternalSignals,
        selectedModulePath: state.selectedModulePath,
        filterText: state.filterText,
        sortAscending: state.sortAscending,
        moduleSelectedSignalIds: state.moduleSelectedSignalIds,
        expandedMonitorSignals: newExpanded,
      ),
    );
  }

  /// Expand a multi-bit signal into individual bit waveforms synthesised
  /// by the repository's bit-slice engine.
  Future<void> _onBitExpand(
    SignalBitExpandEvent event,
    Emitter<SignalState> emit,
  ) async {
    final parentWaveform = event.waveform;
    final parentPath = parentWaveform.fullPath ?? parentWaveform.signalId;
    final parentName = parentWaveform.name;
    final bitStart = event.bitStart;
    final bitEnd = event.bitEnd;

    final subWaveforms = <SignalWaveform>[];
    for (var bit = bitEnd; bit >= bitStart; bit--) {
      final subFieldId = '$parentPath#b[$bit]';
      await _signalWaveformRepository.loadAndAppendWaveformData(
        signalIds: [subFieldId],
      );
      final cached = _signalWaveformRepository.getWaveformById(subFieldId);
      final waveform = (cached != null
          ? SignalWaveform.copyFrom(cached, isComputed: true)
          : SignalWaveform.empty(subFieldId, isComputed: true))
        ..overrideWidth = 1
        ..overrideName = '$parentName[$bit]'
        ..monitorParentId = parentWaveform.monitorId;
      subWaveforms.add(waveform);
    }

    if (subWaveforms.isEmpty) {
      return;
    }

    final insertIndex = _findInsertAfterSubFields(
      state.monitorSignalsList,
      event.index,
      parentPath,
    );
    final updatedList = List<SignalWaveform>.from(state.monitorSignalsList)
      ..insertAll(
        insertIndex.clamp(0, state.monitorSignalsList.length),
        subWaveforms,
      );

    final newExpanded = Set<String>.from(state.expandedMonitorSignals)
      ..add(parentWaveform.monitorId);

    _recordMonitorEdit();
    emit(
      SignalLoaded(
        state.signals,
        updatedList,
        focusedSignalIds: state.focusedSignalIds,
        showInternalSignals: state.showInternalSignals,
        selectedModulePath: state.selectedModulePath,
        filterText: state.filterText,
        sortAscending: state.sortAscending,
        moduleSelectedSignalIds: state.moduleSelectedSignalIds,
        expandedMonitorSignals: newExpanded,
      ),
    );
  }

  /// Split a flat bitvector into contiguous chunks after a user-specified
  /// LSB offset. Chunks are displayed from MSB to LSB, with a partial final
  /// high chunk when the remaining width is not divisible by the chunk size.
  Future<void> _onBitChunks(
    SignalBitChunkEvent event,
    Emitter<SignalState> emit,
  ) async {
    final parentWaveform = event.waveform;
    final width = parentWaveform.width;
    if (event.chunkWidth <= 0 ||
        event.bitOffset < 0 ||
        event.bitOffset >= width) {
      return;
    }

    final parentPath = parentWaveform.fullPath ?? parentWaveform.signalId;
    final parentName = parentWaveform.name;
    final ranges = <({int high, int low})>[];
    for (var low = event.bitOffset; low < width; low += event.chunkWidth) {
      final high = (low + event.chunkWidth - 1) < width
          ? low + event.chunkWidth - 1
          : width - 1;
      ranges.add((high: high, low: low));
    }

    final subWaveforms = <SignalWaveform>[];
    for (final range in ranges.reversed) {
      final subFieldId = range.high == range.low
          ? '$parentPath#b[${range.low}]'
          : '$parentPath#b[${range.high}:${range.low}]';
      await _signalWaveformRepository.loadAndAppendWaveformData(
        signalIds: [subFieldId],
      );
      final cached = _signalWaveformRepository.getWaveformById(subFieldId);
      final waveform = (cached != null
          ? SignalWaveform.copyFrom(cached, isComputed: true)
          : SignalWaveform.empty(subFieldId, isComputed: true))
        ..overrideWidth = range.high - range.low + 1
        ..overrideName = range.high == range.low
            ? '$parentName[${range.low}]'
            : '$parentName[${range.high}:${range.low}]'
        ..monitorParentId = parentWaveform.monitorId
        ..monitorGroup = parentWaveform.monitorGroup;
      subWaveforms.add(waveform);
    }

    final insertIndex = _findInsertAfterSubFields(
      state.monitorSignalsList,
      event.index,
      parentPath,
    );
    final updatedList = List<SignalWaveform>.from(state.monitorSignalsList)
      ..insertAll(
        insertIndex.clamp(0, state.monitorSignalsList.length),
        subWaveforms,
      );
    final newExpanded = Set<String>.from(state.expandedMonitorSignals)
      ..add(parentWaveform.monitorId);

    _recordMonitorEdit();
    emit(
      SignalLoaded(
        state.signals,
        updatedList,
        focusedSignalIds: state.focusedSignalIds,
        showInternalSignals: state.showInternalSignals,
        selectedModulePath: state.selectedModulePath,
        filterText: state.filterText,
        sortAscending: state.sortAscending,
        moduleSelectedSignalIds: state.moduleSelectedSignalIds,
        expandedMonitorSignals: newExpanded,
      ),
    );
  }

  /// Handle [SignalBitFieldsEvent]: add named bit-field waveforms after the
  /// parent signal in the monitor list.
  Future<void> _onBitFields(
    SignalBitFieldsEvent event,
    Emitter<SignalState> emit,
  ) async {
    final parentWaveform = event.waveform;
    final parentPath = parentWaveform.fullPath ?? parentWaveform.signalId;
    final parentName = parentWaveform.name;

    final subWaveforms = <SignalWaveform>[];
    for (final field in event.fields) {
      final subFieldId = field.high == field.low
          ? '$parentPath#b[${field.low}]'
          : '$parentPath#b[${field.high}:${field.low}]';
      await _signalWaveformRepository.loadAndAppendWaveformData(
        signalIds: [subFieldId],
      );
      final cached = _signalWaveformRepository.getWaveformById(subFieldId);
      final waveform = (cached != null
          ? SignalWaveform.copyFrom(cached, isComputed: true)
          : SignalWaveform.empty(subFieldId, isComputed: true))
        ..overrideWidth = field.width
        ..overrideName = '$parentName.${field.name}'
        ..monitorParentId = parentWaveform.monitorId;
      subWaveforms.add(waveform);
    }

    if (subWaveforms.isEmpty) {
      return;
    }

    final insertIndex = _findInsertAfterSubFields(
      state.monitorSignalsList,
      event.index,
      parentPath,
    );
    final updatedList = List<SignalWaveform>.from(state.monitorSignalsList)
      ..insertAll(
        insertIndex.clamp(0, state.monitorSignalsList.length),
        subWaveforms,
      );

    _recordMonitorEdit();
    emit(
      SignalLoaded(
        state.signals,
        updatedList,
        focusedSignalIds: state.focusedSignalIds,
        showInternalSignals: state.showInternalSignals,
        selectedModulePath: state.selectedModulePath,
        filterText: state.filterText,
        sortAscending: state.sortAscending,
        moduleSelectedSignalIds: state.moduleSelectedSignalIds,
        expandedMonitorSignals: state.expandedMonitorSignals,
      ),
    );
  }

  /// Find the insertion index after all existing sub-fields of a parent signal.
  ///
  /// Scans forward from [parentIndex] looking for consecutive entries whose
  /// path starts with `parentPath#` (sub-field separator).  Returns the index
  /// immediately after the last such entry.
  static int _findInsertAfterSubFields(
    List<SignalWaveform> list,
    int parentIndex,
    String parentPath,
  ) {
    final prefix = '$parentPath#';
    var i = parentIndex + 1;
    while (i < list.length) {
      final path = list[i].fullPath ?? list[i].signalId;
      if (!path.startsWith(prefix)) {
        break;
      }
      i++;
    }
    return i;
  }
}
