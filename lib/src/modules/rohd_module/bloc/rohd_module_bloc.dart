// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_module_bloc.dart
// The BLoC for ROHD modules.
//
// 2024 April
// Author(s): Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
//            Yao Jing Quek <yao.jing.quek@intel.com>

import 'dart:async';
import 'dart:developer' as dev;

import 'package:bloc/bloc.dart';
import 'package:dart_wellen/dart_wellen.dart' hide SignalWaveform;
import 'package:equatable/equatable.dart';
import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';

part 'rohd_module_event.dart';
part 'rohd_module_state.dart';

/// BLoC that manages hierarchy loading, selection, and live waveform updates.
class RohdModuleBloc extends Bloc<RohdModuleEvent, RohdModuleState> {
  /// Creates a new ROHD module bloc.
  ///
  /// If `expectsExternalHierarchy` is true, the hierarchy must be provided via
  /// [RohdModuleSetExternalHierarchy]; otherwise [onRohdModuleInit] will fetch
  /// it.
  RohdModuleBloc({
    required SignalWaveformRepository signalWaveformRepository,
    Stream<WaveformUpdateEvent>? liveUpdates,
    this.expectsExternalHierarchy = false,
  })  : _signalWaveformRepository = signalWaveformRepository,
        super(Loading(ModuleStructure.empty())) {
    on<RohdModuleInit>(onRohdModuleInit);
    on<RohdModuleReset>(_onReset);
    on<RohdModuleRefresh>(_onRefresh);
    on<RohdModuleSelect>(onModuleSelected);
    on<RohdModuleSetExternalHierarchy>(_onSetExternalHierarchy);
    on<RohdModuleWaveformUpdate>(_onWaveformUpdate);
    on<RohdModuleWaveformStructureAvailable>(_onWaveformStructureAvailable);

    // Subscribe to live updates if provided
    if (liveUpdates != null) {
      _liveUpdateSubscription = liveUpdates.listen(
        (event) {
          if (event.reason == WaveformUpdateReason.structureAvailable) {
            add(const RohdModuleWaveformStructureAvailable());
          } else {
            add(
              RohdModuleWaveformUpdate(
                incrementalData: event.incrementalData,
                upToTime: event.upToTime,
              ),
            );
          }
        },
        onError: (Object e) {
          dev.log('liveUpdates error: $e', name: 'RohdModuleBloc');
        },
      );
    }
    // Note: Do NOT call add(RohdModuleInit()) here - wait until VCD is loaded
  }

  final SignalWaveformRepository _signalWaveformRepository;
  StreamSubscription<WaveformUpdateEvent>? _liveUpdateSubscription;

  /// Buffer for the most recent upToTime from a WaveformUpdateEvent that
  /// arrived while the state was still [Loading].
  int? _pendingUpToTime;

  /// Time up to which waveform **data** (not just endTime) has been received.
  int _dataEndTime = 0;

  /// When `true`, the hierarchy will be provided externally.
  final bool expectsExternalHierarchy;

  /// Expose the repository for file loading operations
  SignalWaveformRepository get repository => _signalWaveformRepository;

  /// Current metadata from the bloc state (preserves endTime across refreshes).
  MetaData get _currentMetadata => state.moduleStructure.metadata;

  /// Rebind the live waveform update stream after reconnects.
  void updateLiveUpdates(Stream<WaveformUpdateEvent>? liveUpdates) {
    unawaited(_liveUpdateSubscription?.cancel());
    _liveUpdateSubscription = null;

    if (liveUpdates == null) {
      return;
    }

    _liveUpdateSubscription = liveUpdates.listen(
      (event) {
        if (event.reason == WaveformUpdateReason.structureAvailable) {
          add(const RohdModuleWaveformStructureAvailable());
        } else {
          add(
            RohdModuleWaveformUpdate(
              incrementalData: event.incrementalData,
              upToTime: event.upToTime,
            ),
          );
        }
      },
      onError: (Object e) {
        dev.log('liveUpdates error: $e', name: 'RohdModuleBloc');
      },
    );
  }

  /// Reset back to [Loading] so the next [RohdModuleInit] will reload.
  void _onReset(RohdModuleReset event, Emitter<RohdModuleState> emit) {
    _pendingUpToTime = null;
    _dataEndTime = 0;
    emit(Loading(ModuleStructure.empty()));
  }

  /// Rebuild the hierarchy after the waveform backend reloads.
  Future<void> _onRefresh(
    RohdModuleRefresh event,
    Emitter<RohdModuleState> emit,
  ) async {
    try {
      final currentState = state;
      final previousSelected = switch (currentState) {
        ModuleSelected() => currentState.singleModule,
        WaveformUpdated() => currentState.selectedModule,
        _ => null,
      };
      final api = _signalWaveformRepository.api;
      final sourceStructure = event.moduleStructure ??
          (api is WellenSignalWaveformApi
              ? await api.getModuleStructureOnly()
              : null);
      if (sourceStructure == null) {
        throw StateError(
          'RohdModuleRefresh requires a module structure for '
          '${api.runtimeType}.',
        );
      }

      final resolved = resolveModuleStructure(sourceStructure);
      final selected = previousSelected == null
          ? resolved.root
          : _findNodeByPath(
                [resolved.root],
                previousSelected.path(),
              ) ??
              resolved.root;

      _signalWaveformRepository
        ..clearSignalCache()
        ..hierarchyService = resolved.hierarchyService
        ..buildSignalCacheFromHierarchy([resolved.root])
        ..selectedModule = selected;

      emit(Rendered(resolved.structure));
      emit(ModuleSelected(resolved.structure, selected));
    } on Object catch (e, stackTrace) {
      dev.log(
        'Waveform hierarchy refresh failed: $e',
        name: 'RohdModuleBloc',
        error: e,
        stackTrace: stackTrace,
      );
      if (event.completion != null && !event.completion!.isCompleted) {
        event.completion!.completeError(e, stackTrace);
      }
    } finally {
      if (event.completion != null && !event.completion!.isCompleted) {
        event.completion!.complete();
      }
    }
  }

  /// Depth-first search for a [HierarchyOccurrence] with a matching path.
  static HierarchyOccurrence? _findNodeByPath(
    List<HierarchyOccurrence> nodes,
    String path,
  ) {
    for (final node in nodes) {
      if (node.path() == path) {
        return node;
      }
      final found = _findNodeByPath(node.children, path);
      if (found != null) {
        return found;
      }
    }
    return null;
  }

  /// Initializes the module hierarchy when running without an external source.
  Future<void> onRohdModuleInit(
    RohdModuleInit event,
    Emitter<RohdModuleState> emit,
  ) async {
    // In extension/devtools mode the hierarchy arrives exclusively via
    // RohdModuleSetExternalHierarchy.  Skip the API-based init path
    // entirely so the two sources can never race.
    if (expectsExternalHierarchy) {
      dev.log(
        'onRohdModuleInit: no-op — '
        'expects external hierarchy (extension mode)',
        name: 'RohdModuleBloc',
      );
      return;
    }

    // Check if we already have a valid structure
    final currentState = state;
    if (currentState is Rendered ||
        currentState is ModuleSelected ||
        currentState is WaveformUpdated) {
      dev.log(
        'onRohdModuleInit: skipping — '
        'already in ${currentState.runtimeType}',
        name: 'RohdModuleBloc',
      );
      return;
    }

    emit(Loading(ModuleStructure.empty()));
    await _initializeModule(emit);
  }

  Future<void> _initializeModule(Emitter<RohdModuleState> emit) async {
    // Try to extract hierarchy directly from the waveform API.
    // This handles the standalone/CLI case where VCD data is already loaded
    // before the widget tree dispatches RohdModuleInit.
    final api = _signalWaveformRepository.api;
    if (api is WellenSignalWaveformApi) {
      try {
        final structure = await api.getModuleStructureOnly();
        if (structure.modules.isNotEmpty) {
          final resolved = resolveModuleStructure(structure);
          final root = resolved.root;
          dev.log(
            '_initializeModule: '
            'built hierarchy from API — root=${root.name}',
            name: 'RohdModuleBloc',
          );

          emit(Rendered(resolved.structure));
          _signalWaveformRepository
            ..hierarchyService = resolved.hierarchyService
            ..buildSignalCacheFromHierarchy([root])
            ..selectedModule = root;
          emit(ModuleSelected(resolved.structure, root));
          return;
        }
      } on Object catch (e) {
        dev.log(
          '_initializeModule: '
          'API not ready yet ($e), staying in Loading',
          name: 'RohdModuleBloc',
        );
      }
    }

    // No data available yet — stay in Loading and wait for hierarchy
    // to arrive via RohdModuleSetExternalHierarchy (from the UI layer
    // after the user picks a file, or from the extension host).
    dev.log(
      '_initializeModule: '
      'waiting for external hierarchy',
      name: 'RohdModuleBloc',
    );
    if (state is! Loading) {
      emit(Loading(ModuleStructure.empty()));
    }
  }

  /// Selects a module in the hierarchy and updates repository state.
  Future<void> onModuleSelected(
    RohdModuleSelect event,
    Emitter<RohdModuleState> emit,
  ) async {
    try {
      _signalWaveformRepository.selectedModule = event.selectedModule;
      final currentStructure = state.moduleStructure;
      emit(ModuleSelected(currentStructure, event.selectedModule));
    } on Object catch (e) {
      dev.log(
        'Module selection deferred (structure not ready): $e',
        name: 'RohdModuleBloc',
      );
    }
  }

  /// Handle external hierarchy from parent application (e.g., DevTools). This
  /// allows the Wave Viewer to use a shared hierarchy instead of loading its
  /// own from VCD data.
  ///
  /// For VM service mode, waveform data comes from live updates (not
  /// preloaded). For loopback/demo mode, waveform data is preloaded after
  /// emitting the initial Rendered state.
  Future<void> _onSetExternalHierarchy(
    RohdModuleSetExternalHierarchy event,
    Emitter<RohdModuleState> emit,
  ) async {
    // New hierarchy means a fresh baseline for loaded waveform data.
    _dataEndTime = 0;

    // Reset the flag now that we're actually processing the event
    final root = event.hierarchyService.root;
    dev.log(
      '_onSetExternalHierarchy: '
      'root=${root.name}, children=${root.children.length}, '
      'signals=${root.signals.length}',
      name: 'RohdModuleBloc',
    );

    // The inner API (WaveformService) is the source of truth for signal data.
    // The hierarchy is used only for visualization and navigation.
    //
    // Flow the HierarchyService through so downstream consumers (search,
    // navigation) use the original service directly — preserving flat-map
    // adapters, connectivity data, and any other state the source attached.

    // Prefer metadata from the event (standalone VCD load) over existing
    // state metadata.  This ensures endTime from the VCD file propagates
    // instead of falling back to the 20ps default.
    final MetaData preservedMetadata;
    if (event.metadata != null && event.metadata!.endTime > 0) {
      preservedMetadata = event.metadata!;
    } else {
      final existingMeta = _currentMetadata;
      preservedMetadata =
          existingMeta.endTime > 0 ? existingMeta : MetaData.empty();
    }

    final moduleStructure = ModuleStructure(
      metadata: preservedMetadata,
      modules: [root],
      hierarchyService: event.hierarchyService,
    );

    // Preserve current selection when possible instead of forcing root.
    HierarchyOccurrence? desiredSelection;
    final currentState = state;
    if (currentState is ModuleSelected) {
      desiredSelection = _findNodeByPath([
        root,
      ], currentState.singleModule.path());
    } else if (currentState is WaveformUpdated) {
      final previous = currentState.selectedModule;
      if (previous != null) {
        desiredSelection = _findNodeByPath([root], previous.path());
      }
    }
    desiredSelection ??= root;

    // Emit Rendered state IMMEDIATELY to exit Loading state.
    // This prevents RohdModuleInit from being triggered in parallel.
    emit(Rendered(moduleStructure));

    // Set the hierarchy service so the repository can resolve pathnames
    // to OccurrenceAddress via tree-walks (no maps needed).
    _signalWaveformRepository
      ..hierarchyService = event.hierarchyService
      ..buildSignalCacheFromHierarchy([root])
      ..selectedModule = desiredSelection;
    emit(ModuleSelected(moduleStructure, desiredSelection));

    // Apply any WaveformUpdateEvent that arrived before the hierarchy
    // was set (state was Loading at the time, so it was buffered).
    // Do this BEFORE the potentially slow getCurrentTime() call
    // so the timeline endTime updates immediately — the API call can
    // block for seconds if the isolate is paused (service extension probe
    // timeout).
    if (_pendingUpToTime != null && _pendingUpToTime! > 0) {
      dev.log(
        'Applying buffered upToTime='
        '$_pendingUpToTime after hierarchy load',
        name: 'RohdModuleBloc',
      );
      final bufferedTime = _pendingUpToTime!;
      _pendingUpToTime = null;

      final bufferedMeta = MetaData(
        source: moduleStructure.metadata.source,
        timescale: moduleStructure.metadata.timescale,
        date: moduleStructure.metadata.date,
        startTime: moduleStructure.metadata.startTime,
        endTime: bufferedTime,
        timescaleFactor: moduleStructure.metadata.timescaleFactor,
        version: moduleStructure.metadata.version,
        format: moduleStructure.metadata.format,
      );
      final bufferedStructure = ModuleStructure(
        metadata: bufferedMeta,
        modules: [root],
        hierarchyService: event.hierarchyService,
      );
      emit(ModuleSelected(bufferedStructure, desiredSelection));
    }

    // Try to get actual endTime from the waveform API.
    // For loopback mode this returns instantly with the correct endTime.
    // For VM service mode this may take seconds if the isolate is paused.
    // The buffered upToTime already gives the UI a correct endTime so
    // the timeline is usable while this completes.
    try {
      final apiEndTime = await _signalWaveformRepository.getCurrentTime();
      if (apiEndTime != null && apiEndTime > 0) {
        final updatedStructure = ModuleStructure(
          metadata: MetaData(
            source: moduleStructure.metadata.source,
            timescale: moduleStructure.metadata.timescale,
            date: moduleStructure.metadata.date,
            endTime: apiEndTime,
          ),
          modules: [root],
          hierarchyService: event.hierarchyService,
        );
        // Re-emit preserving the active selection.
        emit(ModuleSelected(updatedStructure, desiredSelection));
      }
    } on Object catch (_) {
      // Will update on first waveform event
    }

    // Do NOT load signals upfront. Signals will be loaded lazily when:
    // 1. User selects a module (onModuleSelected)
    // 2. User selects a signal from UI
    // 3. User refreshes the display
    // This ensures minimal bandwidth usage by only fetching displayed signals.
  }

  /// The waveform service has become available for the first time.
  ///
  /// Re-fetch metadata (endTime, etc.) from the now-ready API and update
  /// the current state.  In extension mode this preserves the external
  /// hierarchy while injecting real waveform metadata.
  Future<void> _onWaveformStructureAvailable(
    RohdModuleWaveformStructureAvailable event,
    Emitter<RohdModuleState> emit,
  ) async {
    dev.log(
      'Waveform structure now available — '
      'refreshing endTime',
      name: 'RohdModuleBloc',
    );

    // If we're still in Loading state (e.g. the VCD arrived via postMessage
    // after the initial _initializeModule call found nothing), use
    // _initializeModule to pull the now-ready hierarchy from the API.
    if (state is Loading) {
      dev.log(
        '_onWaveformStructureAvailable: still in Loading — '
        'initializing hierarchy from API',
        name: 'RohdModuleBloc',
      );
      await _initializeModule(emit);
      return;
    }

    try {
      final apiEndTime = await _signalWaveformRepository.getCurrentTime();

      // Preserve the current hierarchy modules and selected module.
      final currentState = state;
      ModuleStructure? currentStructure;
      HierarchyOccurrence? selectedModule;

      if (currentState is ModuleSelected) {
        currentStructure = currentState.rohdModules;
        selectedModule = currentState.singleModule;
      } else if (currentState is WaveformUpdated) {
        currentStructure = currentState.rohdModules;
        selectedModule = currentState.selectedModule;
      } else if (currentState is Rendered) {
        currentStructure = currentState.rohdModules;
      }

      if (currentStructure == null) {
        return;
      }

      if (apiEndTime != null && apiEndTime > 0) {
        final oldMeta = currentStructure.metadata;
        final updatedStructure = ModuleStructure(
          metadata: MetaData(
            source: oldMeta.source,
            timescale: oldMeta.timescale,
            date: oldMeta.date,
            startTime: oldMeta.startTime,
            endTime: apiEndTime,
            timescaleFactor: oldMeta.timescaleFactor,
            version: oldMeta.version,
            format: oldMeta.format,
          ),
          modules: currentStructure.modules,
          hierarchyService: currentStructure.hierarchyService,
        );
        if (selectedModule != null) {
          emit(ModuleSelected(updatedStructure, selectedModule));
        } else {
          emit(Rendered(updatedStructure));
        }
        dev.log(
          'Waveform metadata updated: '
          'endTime=$apiEndTime',
          name: 'RohdModuleBloc',
        );
      }
    } on Object catch (e) {
      dev.log(
        'Waveform metadata not yet available: $e',
        name: 'RohdModuleBloc',
      );
    }
  }

  /// Handle incremental waveform updates from live simulation.
  void _onWaveformUpdate(
    RohdModuleWaveformUpdate event,
    Emitter<RohdModuleState> emit,
  ) {
    // Merge incremental data into repository cache
    for (final waveformData in event.incrementalData) {
      _signalWaveformRepository.appendDataToSignal(
        waveformData.signalId,
        waveformData.data,
      );
    }

    // Get current module structure and create updated version with new end time
    ModuleStructure? currentStructure;
    HierarchyOccurrence? selectedModule;

    final currentState = state;
    if (currentState is Rendered) {
      currentStructure = currentState.rohdModules;
    } else if (currentState is ModuleSelected) {
      currentStructure = currentState.rohdModules;
      selectedModule = currentState.singleModule;
    } else if (currentState is WaveformUpdated) {
      currentStructure = currentState.rohdModules;
      selectedModule = currentState.selectedModule;
    }

    if (currentStructure == null) {
      // State is Loading — buffer the upToTime for when hierarchy arrives.
      if (event.upToTime > 0) {
        _pendingUpToTime = event.upToTime;
        dev.log(
          '_onWaveformUpdate: state is Loading, '
          'buffered upToTime=${event.upToTime}',
          name: 'RohdModuleBloc',
        );
      }
      return;
    }

    // If this is the first time-only update, seed data-end from the
    // previously rendered endTime so we can show a paused/fetch gap.
    if (event.incrementalData.isEmpty && _dataEndTime == 0) {
      final seededEnd = currentStructure.metadata.endTime;
      if (seededEnd > 0) {
        _dataEndTime = seededEnd;
      }
    }

    // Advance _dataEndTime only when actual signal data was received.
    if (event.incrementalData.isNotEmpty && event.upToTime > _dataEndTime) {
      _dataEndTime = event.upToTime;
    }

    // Create updated metadata with new end time
    final oldMeta = currentStructure.metadata;
    final newEndTime =
        event.upToTime > oldMeta.endTime ? event.upToTime : oldMeta.endTime;

    final updatedMetadata = MetaData(
      source: oldMeta.source,
      timescale: oldMeta.timescale,
      date: oldMeta.date,
      startTime: oldMeta.startTime,
      endTime: newEndTime,
      timescaleFactor: oldMeta.timescaleFactor,
      version: oldMeta.version,
      format: oldMeta.format,
    );

    final updatedStructure = ModuleStructure(
      metadata: updatedMetadata,
      modules: currentStructure.modules,
      hierarchyService: currentStructure.hierarchyService,
    );

    // When dataEndTime < endTime, the gap region shows hatching.
    // Only report a gap after we have seen real waveform data at least once.
    final effectiveDataEndTime =
        (_dataEndTime > 0 && _dataEndTime < newEndTime) ? _dataEndTime : null;

    emit(
      WaveformUpdated(
        updatedStructure,
        event.upToTime,
        selectedModule: selectedModule,
        dataEndTime: effectiveDataEndTime,
      ),
    );
  }

  @override
  Future<void> close() async {
    await _liveUpdateSubscription?.cancel();
    await super.close();
  }
}
