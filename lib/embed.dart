// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// embed.dart
// Facade-based wrapper for embed helpers.
//
// 2024 April
// Author(s): Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
//            Max Korbel <max.korbel@intel.com>

import 'package:rohd_wave_viewer/src/platform/platform.dart' as plat;

/// Signals to the host that the embedded viewer is ready.
void signalEmbedReady([Map<String, dynamic>? info]) =>
    plat.signalEmbedReadyImpl(info);

/// Posts a message from the embedded viewer to its host.
void postMessageToHost(Object message) => plat.postMessageToHostImpl(message);

/// Returns whether the Shift key is currently pressed in the host context.
bool isShiftDownFromJs() => plat.isShiftDownFromJsImpl();
