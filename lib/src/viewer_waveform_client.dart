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
/// Application code imports this library rather than the implementation under
/// `waveform_client_core`. When the reusable core moves to
/// `package:rohd_waveform`, this facade remains the single compatibility seam
/// for viewer-specific adaptation.
library;

export 'package:rohd_waveform/rohd_waveform.dart'
    show
        Data,
        MetaData,
        ModuleStructure,
        SignalDataService,
        SignalWaveformApi,
        WaveData,
        WaveFormat,
        WaveformData,
        WaveformUpdateEvent,
        WaveformUpdateReason;

export 'waveform_client_core/waveform_client_core.dart';
