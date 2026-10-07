// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// layout.dart
// Layout-related constants used across the app.
//
// 2024 April
// Author(s): Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
//            Yao Jing Quek <yao.jing.quek@intel.com>

/// Left padding used to align timescale, waveforms, and cursor markers.
const double waveformLeftOffset =
    12; // pixels; tweak this to shift timescale/waveforms/marker

/// Base height for a single signal row (before scaling).
const double baseSignalRowHeight = 30;

/// Standard height for a single signal row (waveform row, selection row, value
/// row).
///
/// Legacy alias for [baseSignalRowHeight].  Prefer reading the scaled height
/// from `WaveformScaleCubit` when available.
const double signalRowHeight = baseSignalRowHeight;

/// Height for the signal tab container (header for a row).
// Keep the tab/container height consistent with the waveform row height so
// selection/value rows align with waveform rows.
/// Height for the signal tab container.
const double signalTabContainerHeight = baseSignalRowHeight;
