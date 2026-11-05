// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// viewer_waveform_client.dart
// Wave Viewer integration seam for backend-neutral waveform client state.
//
// 2026 September 28
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

/// Wave Viewer facade for waveform client state.
///
/// Application code imports the shared waveform services and viewer-owned
/// monitor-row state through this library.
library;

export 'package:rohd_waveform/rohd_waveform.dart'
    show
        Data,
        MetaData,
        ModuleStructure,
        RepositorySignalDataService,
        ResolvedModuleStructure,
        SignalDataService,
        SignalWaveform,
        SignalWaveformApi,
        SignalWaveformRepository,
        WaveData,
        WaveFormat,
        WaveformData,
        WaveformSearchCriterion,
        WaveformUpdateEvent,
        WaveformUpdateReason,
        resolveModuleStructure;

export 'modules/signal/models/monitor_row.dart';
