// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// dart_wellen.dart
// Wellen waveform library bindings for ROHD.
//
// 2026 January 03
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

// Dartdoc uses this name to select the package's public library.
// ignore_for_file: unnecessary_library_name

/// Dart bindings to the Wellen Rust waveform library.
///
/// This library reads waveform files in these formats:
///
/// - **VCD** - Value Change Dump (IEEE 1364)
/// - **FST** - Fast SignalOccurrence Trace (GTKWave)
/// - **GHW** - GHDL Waveform
///
/// ## Reading Waveforms
///
/// ```dart
/// import 'package:dart_wellen/dart_wellen.dart';
///
/// await WellenReader.init();
/// final reader = WellenReader();
/// await reader.loadFile('simulation.vcd');
///
/// // Get the signal hierarchy
/// final hierarchy = await reader.getStructure();
///
/// // Get waveform data for specific signals
/// final data = await reader.getSignalData(['top.clk', 'top.reset']);
/// await reader.close();
/// ```
///
/// Native VCD writing is exported separately from
/// `package:dart_wellen/dart_wellen_io.dart`. The IO library is unavailable
/// on web, and FST writing is not implemented.
library dart_wellen;

// Re-export common types from rohd_waveform for convenience
export 'package:rohd_waveform/rohd_waveform.dart'
    show
        Data,
        MetaData,
        ModuleStructure,
        SignalWaveform,
        WaveFormat,
        WaveformData;

// Re-export hierarchy types for convenience
export 'package:rohd_hierarchy/rohd_hierarchy.dart'
    show HierarchyOccurrence, HierarchyService, SignalOccurrence;

export 'src/wellen_waveform_api.dart';
export 'src/wellen_reader.dart';

// Writer and WaveDumper are IO-only (use dart:io) - import separately:
// import 'package:dart_wellen/dart_wellen_io.dart';
