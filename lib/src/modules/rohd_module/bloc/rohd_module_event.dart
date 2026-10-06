// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_module_event.dart
// The events for the ROHD module BLoC.
//
// 2024 April
// Author(s): Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
//            Yao Jing Quek <yao.jing.quek@intel.com>

part of 'rohd_module_bloc.dart';

/// Base class for ROHD module BLoC events.
sealed class RohdModuleEvent extends Equatable {
  /// Creates a ROHD module event.
  const RohdModuleEvent();
}

/// Initializes module state from the current repository contents.
final class RohdModuleInit extends RohdModuleEvent {
  /// Creates a module initialization event.
  const RohdModuleInit();

  @override
  List<Object> get props => [];
}

/// Resets the bloc to Loading state so that a subsequent [RohdModuleInit]
/// re-reads the (possibly replaced) waveform data from the repository.
final class RohdModuleReset extends RohdModuleEvent {
  /// Creates a module reset event.
  const RohdModuleReset();

  @override
  List<Object> get props => [];
}

/// Selects a module within the current hierarchy.
final class RohdModuleSelect extends RohdModuleEvent {
  /// The selected hierarchy node.
  final HierarchyOccurrence selectedModule;

  /// The hierarchy containing the selected module.
  final ModuleStructure moduleStructure;

  /// Creates a module selection event.
  const RohdModuleSelect(this.moduleStructure, this.selectedModule);

  @override
  List<Object> get props => [];
}

/// Event to set external hierarchy from parent application.
/// When dispatched, the bloc uses this hierarchy instead of loading its own.
final class RohdModuleSetExternalHierarchy extends RohdModuleEvent {
  /// The external hierarchy service from the parent (e.g., DevTools).
  final HierarchyService hierarchyService;

  /// Optional metadata from the waveform file (endTime, timescale, etc.).
  /// When provided (e.g. standalone VCD load), overrides the current state
  /// metadata.  When null (e.g. DevTools/VM service), the bloc preserves
  /// whatever metadata it already has.
  final MetaData? metadata;

  /// Module the host wants selected after the hierarchy is installed.
  final HierarchyOccurrence? selectedModule;

  /// Creates an event that swaps in an external hierarchy service.
  const RohdModuleSetExternalHierarchy(
    this.hierarchyService, {
    this.metadata,
    this.selectedModule,
  });

  @override
  List<Object?> get props => [hierarchyService, metadata, selectedModule];
}

/// Replaces the hierarchy from an already reloaded waveform.
final class RohdModuleRefresh extends RohdModuleEvent {
  /// A structure already validated by the caller.
  ///
  /// When omitted, the BLoC reads the structure from its Wellen API.
  final ModuleStructure? moduleStructure;

  /// Completes after the hierarchy and repository caches are rebuilt.
  final Completer<void>? completion;

  /// Creates a module refresh event.
  const RohdModuleRefresh({this.moduleStructure, this.completion});

  @override
  List<Object?> get props => [moduleStructure];
}

/// Event triggered when incremental waveform data arrives from live updates.
final class RohdModuleWaveformUpdate extends RohdModuleEvent {
  /// The incremental waveform data.
  final List<WaveformData> incrementalData;

  /// The simulation time up to which data has been received.
  final int upToTime;

  /// Creates a waveform update event.
  const RohdModuleWaveformUpdate({
    required this.incrementalData,
    required this.upToTime,
  });

  @override
  List<Object> get props => [incrementalData, upToTime];
}

/// The waveform service (WaveformService / signal dictionary) has become
/// available for the first time.  The bloc should re-fetch metadata from
/// the API and update the current state so that endTime and other waveform
/// properties are correct.
final class RohdModuleWaveformStructureAvailable extends RohdModuleEvent {
  /// Creates an event signaling waveform structure availability.
  const RohdModuleWaveformStructureAvailable();

  @override
  List<Object> get props => [];
}
