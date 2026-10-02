// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// context_menu_blocker_stub.dart
// No-op stub for native platforms where DOM context-menu suppression
// is not needed (and dart:js_interop / package:web are unavailable).
//
// 2026 March
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

/// Creates a no-op context-menu blocker on native platforms.
Object? createContextMenuBlocker() => null;

/// Registers the blocker on the document (no-op on native).
void addContextMenuBlocker(Object? blocker) {}

/// Removes the blocker from the document (no-op on native).
void removeContextMenuBlocker(Object? blocker) {}
