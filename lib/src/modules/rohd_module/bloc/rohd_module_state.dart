// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_module_state.dart
// The state for the ROHD module BLoC.
//
// 2024 April
// Author(s): Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
//            Yao Jing Quek <yao.jing.quek@intel.com>

part of 'rohd_module_bloc.dart';

/// Base class for ROHD module BLoC states.
sealed class RohdModuleState extends Equatable {
  /// Module structure associated with the current state.
  final ModuleStructure moduleStructure;

  /// Creates a ROHD module state.
  const RohdModuleState(this.moduleStructure);

  @override
  List<Object> get props => [moduleStructure];
}

/// State emitted while module data is loading.
final class Loading extends RohdModuleState {
  /// Creates a loading state.
  const Loading(super.moduleStructure);

  @override
  List<Object> get props => [moduleStructure];
}

/// State emitted when module data is ready for rendering.
final class Rendered extends RohdModuleState {
  /// Rendered module hierarchy.
  final ModuleStructure module;

  /// Creates a rendered state.
  const Rendered(this.module) : super(module);

  /// Returns the rendered module hierarchy.
  ModuleStructure get rohdModules => module;

  @override
  List<Object> get props => [module];
}

/// State emitted when a single module is selected.
final class ModuleSelected extends RohdModuleState {
  /// The selected hierarchy node.
  final HierarchyOccurrence singleModule;

  /// Creates a module-selected state.
  const ModuleSelected(super.moduleStructure, this.singleModule);

  /// Returns the full module hierarchy.
  ModuleStructure get rohdModules => moduleStructure;

  @override
  List<Object> get props => [moduleStructure, singleModule];
}

/// State emitted when module loading fails.
final class RohdModuleError extends RohdModuleState {
  /// Creates an error state.
  const RohdModuleError(super.moduleStructure);

  @override
  List<Object> get props => [moduleStructure];
}

/// State emitted when waveform data is updated incrementally from live
/// simulation.
///
/// Each emission carries a unique `sequence` number so that BLoC never
/// considers two successive updates as equal — even when `upToTime` and
/// `moduleStructure` haven't changed (for example, a newly tracked signal whose
/// end time is below the current `_lastFetchedTime`).
final class WaveformUpdated extends RohdModuleState {
  /// Current simulation time
  final int upToTime;

  /// Currently selected module, if any
  final HierarchyOccurrence? selectedModule;

  /// Time up to which actual waveform data has been received.
  ///
  /// When non-null and less than the metadata endTime, the waveform
  /// painters draw a gray hatched region from [dataEndTime] to endTime
  /// to show that data has not been fetched for that range (pause).
  /// When null, all data up to endTime is considered present.
  final int? dataEndTime;

  /// Monotonically-increasing counter — guarantees Equatable uniqueness.
  final int sequence;

  /// Internal sequence source for [WaveformUpdated] emissions.
  static int _nextSequence = 0;

  /// Creates a waveform-updated state.
  WaveformUpdated(
    super.moduleStructure,
    this.upToTime, {
    this.selectedModule,
    this.dataEndTime,
  }) : sequence = _nextSequence++;

  /// Returns the full module hierarchy.
  ModuleStructure get rohdModules => moduleStructure;

  @override
  List<Object> get props => [
        moduleStructure,
        upToTime,
        selectedModule ?? '',
        sequence,
      ];
}
