// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// main_web.dart
// Web-specific entry point for ROHD Wave Viewer (VS Code extension embedding).
// This version does NOT use dart:io and receives VCD content via
// postMessage.
// Uses wellen Rust library via flutter_rust_bridge WASM bindings.
//
// 2024 December
// Author(s): Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
//            Max Korbel <max.korbel@intel.com>

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:dart_wellen/dart_wellen.dart' hide SignalWaveform;
import 'package:devtools_app_shared/ui.dart';
import 'package:devtools_app_shared/utils.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart'
    show CrossProbeService;
import 'package:rohd_wave_viewer/embedded_wave_viewer.dart';
import 'package:rohd_wave_viewer/src/const/app_version.dart';
import 'package:rohd_wave_viewer/src/platform/platform.dart' as plat;
import 'package:web/web.dart' as web;

/// Cross-probe service that exchanges signal selections with the VS Code host.
class VscodeCrossProbeService implements CrossProbeService {
  String? _viewerId;

  @override
  final ValueNotifier<bool> isActive = ValueNotifier<bool>(false);

  @override
  final ValueNotifier<List<String>?> incomingSignals =
      ValueNotifier<List<String>?>(null);

  /// Updates this viewer's identity after the VS Code host registers it.
  void updateAvailability({
    required bool canSendSignals,
    String? viewerId,
  }) {
    _viewerId = viewerId;
    isActive.value = canSendSignals;
  }

  /// Whether a cross-probe message from [sourceViewerId] targets another view.
  bool acceptsIncoming(String? sourceViewerId) =>
      sourceViewerId == null || sourceViewerId != _viewerId;

  @override
  void send(List<String> signalPaths, {required String source}) {
    if (!isActive.value || signalPaths.isEmpty) {
      return;
    }
    debugPrint(
      '[WebMain] sending ${signalPaths.length} signal(s) from $source',
    );
    plat.postMessageToHostImpl({
      'type': 'sendSignals',
      'source': source,
      'signalPaths': signalPaths,
    });
  }

  @override
  void dispose() {
    isActive.dispose();
    incomingSignals.dispose();
  }
}

// ===========================================================================
// JS interop for VS Code webview message callback
// Using typed callback following the pattern from schematic_viewer
// ===========================================================================

/// Set the window.__rohdMessageCallback to a typed Dart function.
/// This uses dart:js_interop properly with a typed function signature.
void _setWindowMessageCallback(JSAny? Function(JSAny?) callback) {
  final jsCallback = callback.toJS;
  (web.window as JSObject).setProperty(
    '__rohdMessageCallback'.toJS,
    jsCallback,
  );
}

// platform facade imported once above

/// Web-compatible wrapper that initializes WellenSignalWaveformApi with bytes.
class WebWellenApi {
  final WellenSignalWaveformApi _api = WellenSignalWaveformApi();
  bool _isLoaded = false;
  final _loadCompleter = Completer<void>();

  /// Returns the underlying API after loading is complete.
  WellenSignalWaveformApi get api => _api;

  /// Wait for the waveform to be loaded.
  Future<void> get loaded => _loadCompleter.future;

  /// Load VCD content from bytes received via postMessage.
  Future<void> loadFromVcdContent(String vcdContent) async {
    try {
      debugPrint(
        '[WebWellen] Loading VCD content (${vcdContent.length} chars)',
      );
      final bytes = utf8.encode(vcdContent);
      await _api.loadBytes(bytes, fileName: 'webview.vcd');
      _isLoaded = true;
      if (!_loadCompleter.isCompleted) {
        _loadCompleter.complete();
      }
      debugPrint('[WebWellen] VCD loaded successfully');
    } on Object catch (e, stackTrace) {
      debugPrint('[WebWellen] Error loading VCD: $e');
      debugPrint('[WebWellen] Stack trace: $stackTrace');
      // Do NOT complete the completer with an error: that would permanently
      // poison [loaded] and block recovery on a subsequent successful reload
      // (e.g. after a window-reload restore). Leave it pending so a later load
      // can still complete it.
    }
  }

  /// Load waveform from raw bytes (used by webview when posting binary files).
  Future<void> loadFromBytes(List<int> bytes, {String? fileName}) async {
    try {
      debugPrint('[WebWellen] Loading bytes (${bytes.length} bytes)');
      await _api.loadBytes(bytes, fileName: fileName);
      _isLoaded = true;
      if (!_loadCompleter.isCompleted) {
        _loadCompleter.complete();
      }
      debugPrint('[WebWellen] Bytes loaded successfully');
    } on Object catch (e, stackTrace) {
      debugPrint('[WebWellen] Error loading bytes: $e');
      debugPrint('[WebWellen] Stack trace: $stackTrace');
      // Do NOT complete the completer with an error: that would permanently
      // poison [loaded] and block recovery on a subsequent successful reload
      // (e.g. after a window-reload restore). Leave it pending so a later load
      // can still complete it.
    }
  }

  /// Whether the web waveform API has finished loading data.
  bool get isLoaded => _isLoaded;
}

void main() async {
  // Disable URL strategies to avoid replaceState errors in VS Code webviews
  plat.setUrlStrategySafe(null);

  WidgetsFlutterBinding.ensureInitialized();
  await initAppVersion();
  setGlobal(IdeTheme, getIdeTheme());

  // Initialize the wellen Rust library (WASM bindings)
  debugPrint('[WebMain] Initializing WellenSignalWaveformApi...');
  var wasmInitSuccess = false;
  try {
    await WellenSignalWaveformApi.init();
    debugPrint('[WebMain] WellenSignalWaveformApi initialized successfully');
    wasmInitSuccess = true;
    // Track whether WASM initialized. Expose a JS-global `wasmInitOk` so
    // the
    // host (extension) can detect success.
    try {
      plat.setGlobalProperty('wasmInitOk', true.toJS);
      debugPrint('[WebMain] Set wasmInitOk = true on window');
    } on Object catch (e) {
      debugPrint('[WebMain] Failed to set wasmInitOk: $e');
    }
  } on Object catch (e, stackTrace) {
    debugPrint('[WebMain] ERROR initializing WellenSignalWaveformApi: $e');
    debugPrint('[WebMain] Stack trace: $stackTrace');
    try {
      plat.setGlobalProperty('wasmInitOk', false.toJS);
    } on Object catch (_) {}
  }

  // Create web-compatible API wrapper
  final webApi = WebWellenApi();
  final crossProbeService = VscodeCrossProbeService();

  // Check for a query parameter to run a small WASM smoke-test from the
  // web entrypoint. This is useful for quick verification in browsers or
  // test harnesses before packaging into the extension.
  try {
    var href = '';
    try {
      final win = plat.getProperty(plat.globalThis, 'window');
      final loc = plat.getProperty(win, 'location');
      final h = plat.getProperty(loc, 'href');
      if (h is String) {
        href = h;
      }
    } on Object catch (_) {}
    final uri = Uri.parse(href.isNotEmpty ? href : '/');
    if (uri.queryParameters['wasmTest'] == '1') {
      // List of example files to load via loadBytes()
      final examples = [
        'surfer/examples/vhdl3.vcd',
        'surfer/examples/vhdl3.fst',
        'surfer/examples/vhdlfixed.ghw',
      ];

      // Run test sequence asynchronously; set a global flag when done.
      unawaited(() async {
        var overallOk = true;
        for (final rel in examples) {
          try {
            debugPrint('[WebWasmTest] Fetching $rel');
            final bytesView = await plat.fetchBytes('/$rel');
            await webApi.api.loadBytes(
              bytesView.toList(),
              fileName: rel.split('/').last,
            );
            final struct = await webApi.api.getModuleStructureOnly();
            debugPrint(
              '[WebWasmTest] Loaded $rel: modules=${struct.modules.length} '
              'signals=${struct.allSignalIds.length}',
            );
          } on Object catch (e, st) {
            overallOk = false;
            debugPrint('[WebWasmTest] Error loading $rel: $e');
            debugPrint('$st');
            break;
          }
        }
        try {
          plat.setProperty(plat.globalThis, 'wasmTestOk', overallOk);
        } on Object catch (_) {}
      }());
    }
  } on Object catch (e) {
    debugPrint('[WebMain] wasmTest check failed: $e');
  }

  // Set up listener for VCD content from host (VS Code extension)
  // Helper to process VCD messages
  Future<void> handleVcdMessage(dynamic data) async {
    debugPrint(
      '[WebMain] handleVcdMessage called with data type: ${data.runtimeType}',
    );
    try {
      String? type;
      String? text;
      Map<dynamic, dynamic>? dartMap;
      try {
        final dartified = plat.dartify(data);
        debugPrint('[WebMain] Dartified data: ${dartified.runtimeType}');
        if (dartified is Map) {
          dartMap = dartified;
          type = dartified['type']?.toString();
          text = dartified['text']?.toString();
          debugPrint(
            '[WebMain] Message type: $type, has text: ${text != null}',
          );
        }
      } on Object catch (e) {
        debugPrint('[WebMain] Dartify failed: $e');
        // Fallback parsing for string payloads
        if (data is String) {
          try {
            final parsed = json.decode(data);
            if (parsed is Map) {
              dartMap = parsed;
              type = parsed['type']?.toString();
              text = parsed['text']?.toString();
              debugPrint('[WebMain] Parsed from JSON - type: $type');
            }
          } on Object catch (e2) {
            debugPrint('[WebMain] JSON parse failed: $e2');
          }
        }
      }

      // If still null, try direct JS property access (JSObject cases)
      if (type == null && data != null) {
        try {
          final t = plat.getProperty(data, 'type');
          if (t != null) {
            type = t.toString();
            debugPrint('[WebMain] type via getProperty: $type');
          }
        } on Object catch (_) {}
      }
      if (text == null && data != null) {
        try {
          final txt = plat.getProperty(data, 'text');
          if (txt != null) {
            text = txt.toString();
            debugPrint('[WebMain] text via getProperty length=${text.length}');
          }
        } on Object catch (_) {}
      }

      if (type == 'signalViewerAvailability') {
        final canSend = _readBool(data, dartMap, 'canSendSignals') ?? false;
        crossProbeService.updateAvailability(
          canSendSignals: canSend,
          viewerId: _readString(data, dartMap, 'viewerId'),
        );
        debugPrint('[WebMain] signal viewer availability: canSend=$canSend');
      } else if (type == 'incomingSignals') {
        final signalPaths = _readStringList(data, dartMap, 'signalPaths');
        final sourceViewerId = _readString(data, dartMap, 'sourceViewerId');
        if (signalPaths.isNotEmpty &&
            crossProbeService.acceptsIncoming(sourceViewerId)) {
          crossProbeService.incomingSignals.value = signalPaths;
          debugPrint(
            '[WebMain] incomingSignals: ${signalPaths.length} signal(s)',
          );
        } else if (sourceViewerId != null) {
          debugPrint('[WebMain] ignored self-originated incomingSignals');
        }
      } else if (type == 'vcdUri') {
        // URL-based loading (like Surfer): fetch binary data via HTTP from
        // the vscode-webview:// URI.  This avoids serialising the entire file
        // through the postMessage channel.
        String? uri;
        String? fileName;
        // First try the dartified Map (works when data was already converted).
        if (dartMap != null) {
          uri = dartMap['uri']?.toString();
          fileName = dartMap['fileName']?.toString();
        }
        // Fallback to JS property access for raw JSObject data.
        if (uri == null && data != null) {
          try {
            final uriProp = plat.getProperty(data, 'uri');
            if (uriProp != null) {
              uri = uriProp.toString();
            }
            final fProp = plat.getProperty(data, 'fileName');
            if (fProp != null) {
              fileName = fProp.toString();
            }
          } on Object catch (_) {}
        }
        fileName ??= uri?.split('/').last ?? 'waveform.vcd';
        if (uri != null) {
          debugPrint('[WebMain] Fetching waveform from URI: $uri');
          try {
            final bytes = await plat.fetchBytes(uri);
            debugPrint('[WebMain] Fetched ${bytes.length} bytes for $fileName');
            await webApi.loadFromBytes(bytes, fileName: fileName);
            debugPrint('[WebMain] Waveform loaded from URI successfully');
          } on Object catch (e) {
            debugPrint('[WebMain] Error fetching/loading from URI: $e');
          }
        } else {
          debugPrint('[WebMain] vcdUri message missing uri property');
        }
      } else if (type == 'vcdContents' && text != null) {
        // Legacy text-based loading (standalone web mode)
        debugPrint('[WebMain] Loading VCD content (${text.length} chars)');
        await webApi.loadFromVcdContent(text);
      } else if (type == 'vcdBytes' && data != null) {
        // Legacy bytes-based loading
        try {
          final bytes =
              plat.dartify(plat.getProperty(data, 'bytes')) as List<dynamic>;
          final intList = bytes.map((e) => e as int).toList();
          String? uriStr;
          try {
            final uriProp = plat.getProperty(data, 'uri');
            if (uriProp != null) {
              uriStr = uriProp.toString();
            }
          } on Object catch (_) {
            uriStr = null;
          }
          final fName = uriStr != null ? uriStr.split('/').last : 'binary.wave';
          await webApi.loadFromBytes(intList, fileName: fName);
          debugPrint(
            '[WebMain] Binary waveform loaded from ${uriStr ?? 'unknown'}',
          );
        } on Object catch (e) {
          debugPrint('[WebMain] Error loading binary waveform: $e');
        }
      } else {
        debugPrint(
          '[WebMain] Message not handled - type: $type, '
          'hasText: ${text != null}',
        );
      }
    } on Object catch (e) {
      debugPrint('[WebMain] Error handling message: $e');
    }
  }

  try {
    final rohdEmbed = plat.rohdEmbed;
    debugPrint(
      '[WebMain] rohdEmbed is ${rohdEmbed != null ? "available" : "null"}',
    );
    if (rohdEmbed != null) {
      try {
        // Set window.__rohdMessageCallback using properly typed dart:js_interop
        // This creates a callback that JavaScript can invoke directly
        _setWindowMessageCallback((jsData) {
          debugPrint('[WebMain] __rohdMessageCallback invoked!');
          // Convert JSAny to Dart Map
          final data = plat.dartify(jsData);
          // Handle async in a microtask to not block JS
          unawaited(Future.microtask(() => handleVcdMessage(data)));
          return null;
        });
        debugPrint(
          '[WebMain] Set window.__rohdMessageCallback with typed callback',
        );

        // Manually replay any queued messages from __rohdMessageQueue Do NOT
        // call rohdEmbed.onMessage as it would overwrite our typed callback
        // with a broken one that went through callMethod/jsify
        try {
          final queue = plat.getGlobalPropertyExported('__rohdMessageQueue');
          if (queue != null) {
            final dartQueue = plat.dartify(queue);
            if (dartQueue is List && dartQueue.isNotEmpty) {
              debugPrint(
                '[WebMain] Replaying ${dartQueue.length} queued messages',
              );
              for (final msg in dartQueue) {
                try {
                  await handleVcdMessage(msg);
                } on Object catch (e) {
                  debugPrint('[WebMain] Error replaying queued message: $e');
                }
              }
              // Clear the queue by setting it to empty array
              plat.setGlobalProperty('__rohdMessageQueue', <JSAny?>[].toJS);
            } else {
              debugPrint('[WebMain] No queued messages to replay');
            }
          }
        } on Object catch (e) {
          debugPrint('[WebMain] Error reading message queue: $e');
        }
      } on Object catch (e) {
        debugPrint('[WebMain] rohdEmbed callback setup failed: $e');
      }
    } else {
      debugPrint('[WebMain] rohdEmbed is null');
    }
  } on Object catch (e) {
    debugPrint('[WebMain] checking rohdEmbed failed: $e');
  }

  // NOTE: We intentionally do NOT add a fallback window 'message' listener.
  // The embed shim already forwards all messages to __rohdMessageCallback
  // (or queues them for replay).  Adding a second listener on the same
  // window 'message' events would cause every VCD payload to be processed
  // twice, doubling the load time for large files.

  // Signal to host that we're ready
  // Use the local wasmInitSuccess flag that we set earlier instead of trying
  // to read it back from the JS global object.
  debugPrint('[WebMain] Signaling embed ready with wasm=$wasmInitSuccess');
  plat.signalEmbedReady({
    'platform': 'web',
    'version': '1.0.0',
    'wasm': wasmInitSuccess,
  });

  // Initialize with the webApi so that when VCD content arrives via
  // postMessage, the webApi loads it and the app can switch to showing real
  // data. Pass webApi.loaded as the apiReady future so the repository waits for
  // the waveform to be loaded before trying to access the data.
  runApp(
    EmbeddedWaveViewer(
      waveformApi: webApi.api,
      apiReady: webApi.loaded.then((_) {
        // API is ready after VCD loads, but for now just complete
        // The repository will retry failed calls after this completes
      }),
      crossProbeService: crossProbeService,
    ),
  );
}

bool? _readBool(dynamic data, Map<dynamic, dynamic>? dartMap, String key) {
  final fromMap = dartMap?[key];
  if (fromMap is bool) {
    return fromMap;
  }
  if (data != null) {
    try {
      final prop = plat.getProperty(data, key);
      if (prop is bool) {
        return prop;
      }
      if (prop != null) {
        return prop.toString() == 'true';
      }
    } on Object catch (_) {}
  }
  return null;
}

String? _readString(dynamic data, Map<dynamic, dynamic>? dartMap, String key) {
  final fromMap = dartMap?[key];
  if (fromMap != null) {
    return fromMap.toString();
  }
  if (data != null) {
    try {
      final prop = plat.getProperty(data, key);
      if (prop != null) {
        return prop.toString();
      }
    } on Object catch (_) {}
  }
  return null;
}

List<String> _readStringList(
  dynamic data,
  Map<dynamic, dynamic>? dartMap,
  String key,
) {
  final fromMap = dartMap?[key];
  if (fromMap is List) {
    return fromMap.map((item) => item.toString()).toList(growable: false);
  }
  if (data != null) {
    try {
      final prop = plat.getProperty(data, key);
      final dartified = plat.dartify(prop);
      if (dartified is List) {
        return dartified.map((item) => item.toString()).toList(growable: false);
      }
    } on Object catch (_) {}
  }
  return const [];
}

/// Stub function for conditional import from main.dart On web, this returns a
/// mock API since initialization happens via main() above.
Future<dynamic> initializeSignalWaveformApi(List<String> args) =>
    Future<dynamic>.error(
      UnsupportedError('Use kIsWeb check in main.dart instead'),
    );
