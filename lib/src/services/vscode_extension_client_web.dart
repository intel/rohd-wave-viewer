// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// vscode_extension_client_web.dart
// Webview implementation of the VS Code extension client.
//
// 2026 August
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart'
    show RohdExtensionClient, RohdModuleInfo;
import 'package:web/web.dart' as web;

/// VS Code webview implementation of the ROHD extension protocol.
class VscodeExtensionClient implements RohdExtensionClient {
  /// Creates a client and begins listening for extension-host messages.
  VscodeExtensionClient() {
    _listener = _handleMessage.toJS;
    web.window.addEventListener('message', _listener);
  }

  @override
  final isAvailable = ValueNotifier<bool>(false);

  @override
  final currentModuleInfo = ValueNotifier<RohdModuleInfo?>(null);

  late final web.EventListener _listener;
  var _nextRequestId = 0;
  final _pending = <String, Completer<Map<String, dynamic>>>{};

  @override
  Future<bool> ping() async {
    final response =
        await _request(<String, Object?>{'type': 'ping'}, 'pingResponse');
    final available = response['available'] == true;
    isAvailable.value = available;
    return available;
  }

  @override
  Future<RohdModuleInfo> queryModule(
    String module, {
    List<String>? instancePath,
  }) async {
    try {
      final response = await _request(<String, Object?>{
        'type': 'getModuleInfo',
        'module': module,
        if (instancePath != null) 'instancePath': instancePath,
      }, 'getModuleInfoResult');
      final info = RohdModuleInfo.fromJson(response);
      currentModuleInfo.value = info;
      isAvailable.value = info.extensionAvailable;
      return info;
    } on Object {
      currentModuleInfo.value = RohdModuleInfo.unavailable;
      isAvailable.value = false;
      return RohdModuleInfo.unavailable;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> lookupSignalFrames({
    required List<Map<String, String>> signals,
    String? format,
  }) async {
    try {
      final response = await _request(<String, Object?>{
        'type': 'lookupSignalFrames',
        'signals': signals,
        if (format != null) 'format': format,
      }, 'lookupSignalFramesResult');
      final frames = response['frames'];
      if (frames is List) {
        return frames
            .whereType<Map<dynamic, dynamic>>()
            .map(Map<String, dynamic>.from)
            .toList(growable: false);
      }
    } on Object {
      // A missing extension response is represented as no source frames.
    }
    return const [];
  }

  @override
  void openSourceLocation({
    required String file,
    required int line,
    int col = 0,
  }) {
    _post(<String, Object?>{
      'type': 'openSourceLocation',
      'file': file,
      'line': line,
      'col': col,
    });
  }

  Future<Map<String, dynamic>> _request(
    Map<String, Object?> message,
    String responseType,
  ) async {
    final requestId = 'wave-${_nextRequestId++}';
    final completer = Completer<Map<String, dynamic>>();
    _pending[requestId] = completer;
    _post(<String, Object?>{
      ...message,
      'requestId': requestId,
      'responseType': responseType,
    });
    final response = await completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        _pending.remove(requestId);
        return <String, dynamic>{};
      },
    );
    return response;
  }

  void _post(Map<String, Object?> message) {
    final rohdEmbed = (web.window as JSObject).getProperty('rohdEmbed'.toJS);
    final rohdEmbedObject = rohdEmbed as JSObject?;
    if (rohdEmbedObject == null) {
      return;
    }
    final postFn = rohdEmbedObject.getProperty('postMessage'.toJS);
    final postFunction = postFn as JSFunction?;
    if (postFunction != null && postFunction.isA<JSFunction>()) {
      postFunction.callAsFunction(rohdEmbedObject, message.jsify());
    }
  }

  void _handleMessage(web.Event event) {
    if (!event.isA<web.MessageEvent>()) {
      return;
    }
    final messageEvent = event as web.MessageEvent;
    if (messageEvent.data == null) {
      return;
    }
    final decoded = messageEvent.data.dartify();
    if (decoded is! Map) {
      return;
    }
    final message = Map<String, dynamic>.from(decoded);
    final requestId = message['requestId'];
    if (requestId is! String) {
      return;
    }
    final completer = _pending.remove(requestId);
    if (completer != null && !completer.isCompleted) {
      completer.complete(message);
    }
  }

  @override
  void dispose() {
    web.window.removeEventListener('message', _listener);
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.complete(<String, dynamic>{});
      }
    }
    _pending.clear();
    isAvailable.dispose();
    currentModuleInfo.dispose();
  }
}

/// Creates a client for the VS Code webview protocol.
RohdExtensionClient createVscodeExtensionClient() => VscodeExtensionClient();
