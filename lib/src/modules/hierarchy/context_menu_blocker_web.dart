// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// context_menu_blocker_web.dart
// Web implementation of DOM-level context-menu suppression.
// Loaded only on web via conditional import.
//
// 2026 March
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Creates a capturing JS event listener that calls preventDefault()
/// on the browser's native context-menu event.
Object? createContextMenuBlocker() => ((web.Event event) {
      event.preventDefault();
    }).toJS;

/// Registers [blocker] as a capturing 'contextmenu' listener on
/// the document.
void addContextMenuBlocker(Object? blocker) {
  if (blocker != null) {
    web.document.addEventListener(
      'contextmenu',
      blocker as JSFunction,
      web.AddEventListenerOptions()..capture = true,
    );
  }
}

/// Removes [blocker] from the document's 'contextmenu' listeners.
void removeContextMenuBlocker(Object? blocker) {
  if (blocker != null) {
    web.document.removeEventListener(
      'contextmenu',
      blocker as JSFunction,
      web.EventListenerOptions(capture: true),
    );
  }
}
