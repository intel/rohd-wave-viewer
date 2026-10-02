// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// home.dart
// The home page for the waveform viewer.
//
// 2024 April
// Author(s): Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
//            Yao Jing Quek <yao.jing.quek@intel.com>

import 'dart:async' show StreamSubscription, unawaited;
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:dart_wellen/dart_wellen.dart' hide SignalWaveform;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_wave_viewer/src/const/app_theme.dart';
import 'package:rohd_wave_viewer/src/const/layout.dart';
import 'package:rohd_wave_viewer/src/cubit/wave_viewer_theme_cubit.dart';
import 'package:rohd_wave_viewer/src/cubit/waveform_scale_cubit.dart';
import 'package:rohd_wave_viewer/src/modules/hierarchy/hierarchy_overlay.dart';
import 'package:rohd_wave_viewer/src/modules/hierarchy/hierarchy_widget.dart';
import 'package:rohd_wave_viewer/src/modules/home/session/signal_list_persistence.dart';
import 'package:rohd_wave_viewer/src/modules/rohd_module/bloc/rohd_module_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/shared/widgets/widgets.dart';
import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/signal/utils/signal_display_utils.dart';
import 'package:rohd_wave_viewer/src/modules/signal/view/selected_signal_panel.dart';
import 'package:rohd_wave_viewer/src/modules/signal/view/signal_value_panel.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/bloc/waveform_module_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/view/waveform_panel.dart';
import 'package:rohd_wave_viewer/src/platform/devtools_shared_ui.dart';
import 'package:rohd_wave_viewer/src/platform/platform_io.dart'
    if (dart.library.html) 'package:rohd_wave_viewer/src/platform/platform_web.dart'
    as platform;
import 'package:rohd_wave_viewer/src/services/vscode_extension_client.dart'
    show RohdExtensionClient, RohdModuleInfo, createVscodeExtensionClient;
import 'package:rohd_wave_viewer/src/services/vscode_webview_interop_io.dart'
    if (dart.library.js_interop) 'package:rohd_wave_viewer/src/services/vscode_webview_interop_web.dart'
    as vscode;

/// Main page for the standalone and embedded waveform viewer.
class WaveFormViewerPage extends StatefulWidget {
  /// Whether running in extension mode (embedded in another app).
  /// When true, hides file picker and other standalone-only UI elements.
  final bool _isExtensionMode;

  /// Callback invoked when the user requests a snapshot of all signal values
  /// at the current marker time. The argument is the marker time in
  /// picoseconds.
  final void Function(int timePs)? _onSnapshotRequested;

  /// The time (in picoseconds) of the most recent snapshot, if any.
  /// Displayed in the snapshot button tooltip so the user knows when the
  /// last snapshot was taken — even when the button is disabled.
  final int? _lastSnapshotTimePs;

  /// Live notifier for snapshot availability.
  ///
  /// When provided, the snapshot button reactively listens to this notifier
  /// instead of deriving availability from `onSnapshotRequested` being
  /// non-null.
  final ValueNotifier<bool>? _canSnapshotNotifier;

  /// Whether the snapshot system is in video (live tracking) mode.
  final bool _isVideoMode;

  /// Called when the user toggles between camera and video mode.
  final VoidCallback? _onVideoModeToggled;

  /// Callback when user wants to send selected signals to other viewers.
  final void Function(List<String> signalPaths)? _onSendSignals;

  /// Callback when user wants to navigate to a signal's source for a chosen
  /// [RohdSourceFormat].
  final GoToSourceCallback? _onGoToSource;

  /// Notifier for incoming signal paths from other viewers (cross-probing).
  final ValueNotifier<List<String>?>? _incomingSignalPaths;

  /// Optional [CrossProbeService] for cross-probing between viewers.
  ///
  /// When provided, overrides the incoming-signal notifier for receiving
  /// signals and broadcasts sends through the service instead.
  /// Also shows a cross-probe button in the app bar.
  final CrossProbeService? _crossProbeService;

  /// Optional ROHD extension client for handshaking.
  ///
  /// When provided, the wave viewer:
  ///   • Pings the extension at startup so availability can be observed.
  ///   • Shows ROHD, SystemVerilog, and SystemC source menu items only when
  ///     the extension reports each format as available for the current module.
  ///
  /// Supply an FLC-backed extension client in DevTools mode, a
  /// VS Code webview extension client in VS Code mode. Without availability
  /// information, no source-navigation menu items are shown.
  final RohdExtensionClient? _extensionClient;

  /// Events emitted after VS Code reloads the waveform API.
  final Stream<void>? _apiReloads;

  /// Creates the waveform viewer page.
  const WaveFormViewerPage({
    super.key,
    bool isExtensionMode = false,
    void Function(int timePs)? onSnapshotRequested,
    int? lastSnapshotTimePs,
    ValueNotifier<bool>? canSnapshotNotifier,
    bool isVideoMode = false,
    VoidCallback? onVideoModeToggled,
    void Function(List<String> signalPaths)? onSendSignals,
    GoToSourceCallback? onGoToSource,
    ValueNotifier<List<String>?>? incomingSignalPaths,
    CrossProbeService? crossProbeService,
    RohdExtensionClient? extensionClient,
    Stream<void>? apiReloads,
  })  : _isExtensionMode = isExtensionMode,
        _onSnapshotRequested = onSnapshotRequested,
        _lastSnapshotTimePs = lastSnapshotTimePs,
        _canSnapshotNotifier = canSnapshotNotifier,
        _isVideoMode = isVideoMode,
        _onVideoModeToggled = onVideoModeToggled,
        _onSendSignals = onSendSignals,
        _onGoToSource = onGoToSource,
        _incomingSignalPaths = incomingSignalPaths,
        _crossProbeService = crossProbeService,
        _extensionClient = extensionClient,
        _apiReloads = apiReloads;

  @override
  State<WaveFormViewerPage> createState() => _WaveFormViewerPageState();
}

class _WaveFormViewerPageState extends State<WaveFormViewerPage> {
  // Key for the RepaintBoundary wrapping all 3 viewer panes (PNG export)
  final GlobalKey _exportBoundaryKey = GlobalKey();

  /// When true, hides the export button during PNG capture.
  final ValueNotifier<bool> _snapshotModeNotifier = ValueNotifier(false);

  /// Capture the waveform as a PNG, hiding the export button during capture.
  Future<void> _exportToPng() async {
    _snapshotModeNotifier.value = true;
    try {
      await captureBoundaryToPng(
        context,
        boundaryKey: _exportBoundaryKey,
        filePrefix: 'waveform',
        saveFn: _isVscodeWebview ? _vscodeSavePng : null,
      );
    } finally {
      _snapshotModeNotifier.value = false;
    }
  }

  /// Save PNG bytes through the VS Code extension host (native Save dialog).
  /// Used as the `saveFn` callback for `captureBoundaryToPng` when running
  /// inside a VS Code webview.
  Future<String?> _vscodeSavePng(Uint8List pngBytes, String fileName) async {
    final base64Data = base64Encode(pngBytes);
    vscode.postSavePng(pngBase64: base64Data, suggestedName: fileName);
    // The extension handles the save dialog and writes the file.
    // We return null since the actual path comes back asynchronously.
    return null;
  }

  // Each panel needs its own scroll controller to avoid attaching multiple
  // ScrollPositions to the same controller, which breaks interactive
  // Scrollbars.
  final ScrollController _selectedSignalsScrollController = ScrollController();
  final ScrollController _signalValueScrollController = ScrollController();
  final ScrollController _waveformVerticalScrollController = ScrollController();

  /// Command channel: increment to trigger fit-to-viewport on the waveform.
  final ValueNotifier<int> _fitCommandNotifier = ValueNotifier<int>(0);

  /// Live waveform viewport state used by session save and restore.
  final ValueNotifier<WaveformViewport> _viewportNotifier =
      ValueNotifier(const WaveformViewport());

  /// Local waveform measurement marker; it does not drive cross-view time.
  final ValueNotifier<int?> _measurementMarkerNotifier = ValueNotifier(null);

  // Guard flag to prevent infinite recursion in synchronized scrolling
  bool _isSynchronizingScroll = false;

  // Track monitor signal count to detect additions
  int _lastMonitorCount = 0;

  String? _fileName;
  String? _filePath;
  List<int>? _fileBytes;
  bool _isLoadingFile = false;

  /// Whether waveform data has been loaded (from any source — file picker,
  /// VS Code extension host, DevTools parent, etc.).  Used to enable
  /// the auto-hiding AppBar overlay.
  bool _hasWaveformsLoaded = false;

  /// Whether running in an embedded context (DevTools parent or VS Code
  /// webview).  When true, standalone-only UI (file picker, etc.) is hidden.
  late final bool _isExtensionMode;

  /// Whether running inside a VS Code webview specifically.
  /// When true, file I/O is delegated to the VS Code extension host via
  /// `rohdEmbed.postMessage`.  This is a subset of `_isExtensionMode`.
  late final bool _isVscodeWebview;

  /// Rebuilds the hierarchy when a VS Code webview reloads its waveform.
  StreamSubscription<void>? _apiReloadSub;

  /// File System Access API handle for true disk reload on web (standalone mode
  /// only). When available, this allows refreshing from the actual file on disk
  /// (e.g., after resimulating and generating a new VCD file).
  platform.FileSystemHandle? _fileHandle;

  /// Whether color emoji fonts are available on this system. Web always uses
  /// emoji; native starts with optimistic assumption and verifies.
  late bool _hasColorEmoji; // Assume available, verify on native platforms

  /// Whether the hierarchy panel is pinned open (normal pane, not overlay).
  bool _hierarchyPinned = true;

  /// Whether the top AppBar remains visible instead of auto-hiding.
  bool _appBarPinned = true;

  /// Tracked pixel width of the Selected Signals pane so the hierarchy
  /// overlay/panel can match it.
  double _selectedSignalsWidth = 240;

  /// Width of the pinned hierarchy panel, computed from the max signal name
  /// width at the time the pin is toggled.
  double _pinnedPanelWidth = 240;

  /// Minimum width for the Selected Signals pane (and pinned hierarchy)
  /// so that the "Selected Signals" header text never wraps.
  /// 13 px semi-bold "Selected Signals" ≈ 108 px + 24 px horizontal padding.
  static const double _minSelectedSignalsWidth = 140;

  /// Cross-panel drag-reorder controller.  Shared across Selected Signals,
  /// SignalOccurrence Value, and Waveform panels so that dragging in any panel
  /// animates all three in lockstep.
  final DragReorderController _dragController = DragReorderController();

  bool _isTextInputFocused() {
    final focused = FocusManager.instance.primaryFocus;
    if (focused == null) {
      return false;
    }
    final ctx = focused.context;
    if (ctx == null) {
      return false;
    }
    if (ctx.widget is EditableText) {
      return true;
    }
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  @override
  void initState() {
    super.initState();
    _isVscodeWebview = vscode.isVscodeWebview();
    _isExtensionMode = widget._isExtensionMode || _isVscodeWebview;

    if (_isVscodeWebview) {
      _apiReloadSub = widget._apiReloads?.listen((_) {
        unawaited(_onApiReloaded());
      });
    }

    // Set up synchronized vertical scrolling for the three panels
    _setupSynchronizedScrolling();

    // Detect color emoji font availability on native platforms before first
    // frame to avoid flickering. Skip in test environment to avoid Process.run
    // timer issues.
    if (!kIsWeb) {
      // Only run font detection if not in test mode
      // (flutter test uses AutomatedTestWidgetsFlutterBinding)
      final isTestMode = WidgetsBinding.instance.runtimeType
          .toString()
          .contains('AutomatedTestWidgets');
      if (!isTestMode) {
        _hasColorEmoji = true; // Default to true
        unawaited(_detectEmojiFont());
      } else {
        _hasColorEmoji = true; // Default in test mode
      }
    } else {
      _hasColorEmoji = true; // Web always has color emoji
    }

    // Note: Removed auto-init call - user should explicitly load a VCD file.
    // Previously tried to init in standalone mode, but this caused errors
    // when no waveform was loaded yet.

    // Cross-probing: listen for incoming signal paths from other viewers.
    if (widget._crossProbeService != null) {
      widget._crossProbeService!.incomingSignals.addListener(
        _onIncomingSignals,
      );
      widget._crossProbeService!.isActive.addListener(
        _onCrossProbeActiveChanged,
      );
    } else {
      widget._incomingSignalPaths?.addListener(_onIncomingSignals);
    }

    // In VS Code webview mode without an injected extension client, create
    // our own so we can query format availability. Also create local go-to
    // callbacks that talk to the extension host via the rohdEmbed bridge.
    if (_isVscodeWebview) {
      if (widget._extensionClient == null) {
        _ownedExtensionClient = createVscodeExtensionClient();
      }
      if (widget._onGoToSource == null) {
        _localGoToSource =
            (format, paths) => _handleGoToSource(paths, format: format.name);
      }
    }

    // Extension handshake: ping on startup, subscribe to module info updates.
    final client = _effectiveClient;
    if (client != null) {
      unawaited(client.ping());
      client.currentModuleInfo.addListener(_onModuleInfoChanged);
    }

    if (_isVscodeWebview) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(
          Future<void>.delayed(const Duration(seconds: 1), () {
            if (!mounted || _hasWaveformsLoaded) {
              return;
            }
            final api = context.read<RohdModuleBloc>().repository.api;
            if (api is WellenSignalWaveformApi && api.isLoaded) {
              unawaited(_onApiReloaded());
            } else {
              vscode.requestExtensionReload();
            }
          }),
        );
      });
    }
  }

  Future<void> _onApiReloaded() async {
    if (!mounted) {
      return;
    }
    final repository = context.read<RohdModuleBloc>().repository;
    final api = repository.api;
    if (api is! WellenSignalWaveformApi) {
      return;
    }
    repository.clearSignalCache();
    context.read<SignalBloc>().add(SignalResetEvent());
    context.read<WaveformModuleBloc>().add(const WaveformModuleReset());
    context.read<RohdModuleBloc>().add(const RohdModuleReset());
    await _pushHierarchyFromApi(api);
  }

  /// Handle incoming cross-probed signal paths by adding them to the
  /// monitor list via [SignalRestoreMonitoredEvent].
  void _onIncomingSignals() {
    final paths = widget._crossProbeService?.incomingSignals.value ??
        widget._incomingSignalPaths?.value;
    if (paths == null || paths.isEmpty) {
      return;
    }
    context.read<SignalBloc>().add(
          SignalRestoreMonitoredEvent(
            paths,
            skipUnavailableSignals: true,
          ),
        );
  }

  void _onCrossProbeActiveChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  // ── Extension-aware module info ───────────────────────────────────────────

  /// Extension client owned by this state (created in VS Code webview mode
  /// when no external client is injected via `widget.extensionClient`).
  /// Disposed in `dispose`.
  RohdExtensionClient? _ownedExtensionClient;

  /// Convenience getter for whichever client is active.
  RohdExtensionClient? get _effectiveClient =>
      widget._extensionClient ?? _ownedExtensionClient;

  /// Local go-to-source callback used in VS Code webview mode when no
  /// parent callback is injected (i.e. the wave viewer is opened directly
  /// from VS Code, not embedded inside the DevTools extension).
  GoToSourceCallback? _localGoToSource;

  void Function(List<String> signalPaths)? get _effectiveSendSignals {
    if (!widget._isExtensionMode && widget._crossProbeService == null) {
      return null;
    }
    final service = widget._crossProbeService;
    if (service != null) {
      if (!service.isActive.value) {
        return null;
      }
      return (paths) => service.send(paths, source: 'wave');
    }
    return widget._onSendSignals;
  }

  /// Latest module info from the extension (null until first query).
  RohdModuleInfo? _moduleInfo;
  String? _lastModuleInfoPath;
  String? _lastModuleInfoQueryName;
  List<String>? _lastModuleInfoInstancePath;

  void _onModuleInfoChanged() {
    final info = _effectiveClient?.currentModuleInfo.value;
    if (mounted) {
      setState(() {
        _moduleInfo = info;
      });
      // If the query errored (e.g. rohd extension not yet activated),
      // retry once after a short delay to handle the race condition.
      if (info?.error != null) {
        unawaited(
          Future.delayed(const Duration(seconds: 2), () {
            final client = _effectiveClient;
            final queryName = _lastModuleInfoQueryName;
            if (mounted && client != null && queryName != null) {
              unawaited(
                client.queryModule(
                  queryName,
                  instancePath: _lastModuleInfoInstancePath,
                ),
              );
            }
          }),
        );
      }
    }
  }

  void _refreshModuleInfoForModule(
    HierarchyOccurrence module, {
    bool force = false,
  }) {
    final client = _effectiveClient;
    if (client == null) {
      return;
    }

    final modulePath = module.path();
    if (!force && _lastModuleInfoPath == modulePath) {
      return;
    }
    _lastModuleInfoPath = modulePath;

    final queryName = module.definition ??
        (module.name.isNotEmpty ? module.name : modulePath);
    final instancePath =
        modulePath.split('/').where((segment) => segment.isNotEmpty).toList();
    _lastModuleInfoQueryName = queryName;
    _lastModuleInfoInstancePath = instancePath;
    unawaited(client.queryModule(queryName, instancePath: instancePath));
  }

  /// Effective go-to-source callback: the injected parent callback, falling
  /// back to the local VS Code webview callback.  Per-format availability is
  /// handled separately by [_availableSourceFormats].
  GoToSourceCallback? get _effectiveGoToSource =>
      widget._onGoToSource ?? _localGoToSource;

  /// Discovers which source formats are navigable for the current module.
  AvailableSourceFormats get _availableSourceFormats =>
      () => resolveNavigableFormats(_moduleInfo);

  /// Handle "Go to Source" by looking up frames from the extension host,
  /// then showing a popup if multiple frames are found.
  void _handleGoToSource(List<String> paths, {String? format}) {
    final client = _effectiveClient;
    if (client == null) {
      return;
    }

    final signalList = paths.map((fp) {
      final segments = fp.contains('/') ? fp.split('/') : fp.split('.');
      final name = segments.last;
      final module =
          segments.length > 1 ? segments[segments.length - 2] : segments.first;
      return {'module': module, 'name': name};
    }).toList();

    unawaited(
      client.lookupSignalFrames(signals: signalList, format: format).then((
        frames,
      ) {
        if (!mounted) {
          return;
        }
        if (frames.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No source locations found'),
              duration: Duration(seconds: 2),
            ),
          );
          return;
        }

        if (frames.length == 1) {
          final f = frames.first;
          client.openSourceLocation(
            file: f['file'] as String? ?? '',
            line: f['line'] as int? ?? 0,
            col: f['col'] as int? ?? 0,
          );
        } else {
          _showFrameSelectionPopup(frames);
        }
      }),
    );
  }

  /// Show a popup menu listing available source frames for user selection.
  void _showFrameSelectionPopup(List<Map<String, dynamic>> frames) {
    final items = <PopupMenuEntry<int>>[];
    for (var i = 0; i < frames.length; i++) {
      final f = frames[i];
      final file = (f['file'] as String? ?? '').split('/').last;
      final line = f['line'] as int? ?? 0;
      final desc = f['desc'] as String? ?? '';
      final type = f['type'] as String? ?? '';
      final label = desc.isNotEmpty
          ? '$file:$line  $desc'
          : '$file:$line${type.isNotEmpty ? '  [$type]' : ''}';
      items.add(
        PopupMenuItem<int>(
          value: i,
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: const TextStyle(fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final size = overlay.size;
    final rect = RelativeRect.fromLTRB(
      size.width / 3,
      size.height / 3,
      size.width / 3,
      size.height / 3,
    );

    unawaited(
      showMenu<int>(context: context, position: rect, items: items).then((idx) {
        if (idx == null) {
          return;
        }
        final f = frames[idx];
        _effectiveClient?.openSourceLocation(
          file: f['file'] as String? ?? '',
          line: f['line'] as int? ?? 0,
          col: f['col'] as int? ?? 0,
        );
      }),
    );
  }

  /// Set up synchronized vertical scrolling between the three panels.
  /// All three panels truncate their viewport to the same whole number of
  /// signal rows, so their maxScrollExtent values are identical.  We simply
  /// copy the source offset (clamped) to every target.
  void _setupSynchronizedScrolling() {
    void synchronizeScroll(ScrollController source) {
      if (_isSynchronizingScroll) {
        return;
      }
      _isSynchronizingScroll = true;

      try {
        if (!source.hasClients) {
          return;
        }
        final offset = source.offset;

        final targets = <ScrollController>[
          _selectedSignalsScrollController,
          _signalValueScrollController,
          _waveformVerticalScrollController,
        ];

        for (final target in targets) {
          if (target != source && target.hasClients) {
            final targetMax = target.position.maxScrollExtent;
            final clamped = offset.clamp(0.0, targetMax);
            if ((target.offset - clamped).abs() > 0.5) {
              target.jumpTo(clamped);
            }
          }
        }
      } finally {
        _isSynchronizingScroll = false;
      }
    }

    _selectedSignalsScrollController.addListener(() {
      synchronizeScroll(_selectedSignalsScrollController);
    });
    _signalValueScrollController.addListener(() {
      synchronizeScroll(_signalValueScrollController);
    });
    _waveformVerticalScrollController.addListener(() {
      synchronizeScroll(_waveformVerticalScrollController);
    });
  }

  /// Detect color emoji font availability without causing rebuild flicker.
  /// Runs font check before the widget is painted.
  Future<void> _detectEmojiFont() async {
    final hasFont = await platform.isEmojiFontInstalled();
    // Only update state if it differs from initial assumption
    if (mounted && hasFont != _hasColorEmoji) {
      setState(() => _hasColorEmoji = hasFont);
    }
    debugPrint('[Home] Color emoji available: $hasFont');
  }

  @override
  void dispose() {
    unawaited(_apiReloadSub?.cancel());
    _apiReloadSub = null;
    widget._crossProbeService?.incomingSignals.removeListener(
      _onIncomingSignals,
    );
    widget._crossProbeService?.isActive.removeListener(
      _onCrossProbeActiveChanged,
    );
    widget._incomingSignalPaths?.removeListener(_onIncomingSignals);
    _effectiveClient?.currentModuleInfo.removeListener(_onModuleInfoChanged);
    _ownedExtensionClient?.dispose();
    _ownedExtensionClient = null;
    _fitCommandNotifier.dispose();
    _viewportNotifier.dispose();
    _measurementMarkerNotifier.dispose();
    _dragController.dispose();
    _selectedSignalsScrollController.dispose();
    _signalValueScrollController.dispose();
    _waveformVerticalScrollController.dispose();
    super.dispose();
  }

  /// Load a VCD file from the file picker.
  /// On web with File System Access API support (Chrome/Edge), we use the
  /// native picker which provides a persistent file handle for later refresh.
  /// Otherwise, we fall back to FilePicker which only provides one-time bytes.
  Future<void> _loadVcdFile() async {
    // Capture repository before async gap
    final repository = context.read<RohdModuleBloc>().repository;

    try {
      String? fileName;
      String? filePath;
      List<int>? bytes;
      platform.FileSystemHandle? fileHandle;

      // Try File System Access API first (Chrome/Edge on web)
      if (platform.isFileSystemAccessSupported) {
        debugPrint('[Home] Using File System Access API');
        final handle = await platform.showOpenFilePickerNative(
          extensions: ['vcd', 'fst', 'ghw'],
        );

        if (handle != null) {
          fileName = handle.name;
          bytes = await handle.readBytes();
          fileHandle = handle;
          debugPrint(
            '[Home] Got file handle for: $fileName (${bytes.length} bytes)',
          );
        }
      }

      // Fall back to file_selector if FSAA not available or user cancelled
      if (bytes == null) {
        debugPrint('[Home] Using file_selector fallback');
        const typeGroup = XTypeGroup(
          label: 'Waveform files',
          extensions: <String>['vcd', 'fst', 'ghw'],
        );
        final xfile = await openFile(
          acceptedTypeGroups: <XTypeGroup>[typeGroup],
        );

        if (xfile != null) {
          fileName = xfile.name;
          bytes = await xfile.readAsBytes();
          filePath = xfile.path;
        }
      }

      if (!mounted) {
        return;
      }

      if (bytes != null && fileName != null) {
        setState(() {
          _isLoadingFile = true;
          _fileName = fileName;
          _filePath = filePath;
          _fileBytes = bytes;
          _fileHandle = fileHandle;
        });

        // Allow the loading overlay to render before starting heavy processing
        await Future<void>.delayed(Duration.zero);

        // Repository already captured before async gap
        final api = repository.api;

        // Load the file bytes into the API
        if (api is WellenSignalWaveformApi) {
          debugPrint('[Home] Loading $fileName (${bytes.length} bytes)');

          // Clear the old signal cache and reset BLoCs before loading new file
          repository.clearSignalCache();
          if (mounted) {
            context.read<SignalBloc>().add(SignalResetEvent());
            context.read<WaveformModuleBloc>().add(const WaveformModuleReset());
            context.read<RohdModuleBloc>().add(const RohdModuleReset());
          }

          await api.loadBytes(bytes, fileName: fileName);
          debugPrint('[Home] File loaded successfully');

          // Extract hierarchy from the loaded VCD and push it into the bloc
          await _pushHierarchyFromApi(api);
        } else {
          debugPrint(
            '[Home] API is not WellenSignalWaveformApi: ${api.runtimeType}. '
            'Creating a WellenSignalWaveformApi to load file.',
          );

          final newApi = WellenSignalWaveformApi();

          // Clear caches and reset BLoCs before swapping API
          repository.clearSignalCache();
          if (mounted) {
            context.read<SignalBloc>().add(SignalResetEvent());
            context.read<WaveformModuleBloc>().add(const WaveformModuleReset());
            context.read<RohdModuleBloc>().add(const RohdModuleReset());
          }

          await newApi.loadBytes(bytes, fileName: fileName);

          // Swap the repository to use the new Wellen API
          repository.setSignalWaveformApi(newApi);

          // Extract hierarchy from the loaded VCD and push it into the bloc
          await _pushHierarchyFromApi(newApi);
        }

        setState(() {
          _isLoadingFile = false;
        });
      }
    } on Object catch (e, stackTrace) {
      debugPrint('[Home] Error loading file: $e');
      debugPrint('[Home] Stack trace: $stackTrace');
      setState(() => _isLoadingFile = false);

      // Show error to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Extract the hierarchy from a loaded [WellenSignalWaveformApi] and
  /// dispatch [RohdModuleSetExternalHierarchy] so the bloc transitions
  /// out of [Loading].
  Future<void> _pushHierarchyFromApi(WellenSignalWaveformApi api) async {
    final structure = await api.getModuleStructureOnly();
    if (structure.modules.isEmpty) {
      debugPrint('[Home] No modules found in loaded file');
      return;
    }
    final root = structure.modules.first;
    final hierarchyService = BaseHierarchyAdapter.fromTree(root);
    debugPrint(
      '[Home] Built hierarchy from VCD: '
      'root=${root.name}, children=${root.children.length}',
    );
    if (mounted) {
      context.read<RohdModuleBloc>().add(
            RohdModuleSetExternalHierarchy(
              hierarchyService,
              metadata: structure.metadata,
            ),
          );
    }
  }

  /// Refresh the current waveform by reloading from disk.
  /// Behavior depends on mode:
  /// - Extension mode: Request extension to re-send the original file
  /// - Standalone web: Use FSAA handle or stored bytes
  /// - Native: Use file path
  Future<void> _refreshWaveform() async {
    // In VS Code webview mode, ask the extension to re-send the file
    if (_isVscodeWebview) {
      debugPrint('[Home] Requesting extension to reload file');
      vscode.requestExtensionReload();
      // The extension will re-send via postMessage, which triggers
      // handleVcdMessage in main_web.dart and reloads the data
      return;
    }

    // Standalone mode - need to reload ourselves
    if (_fileName == null) {
      debugPrint('[Home] No file loaded to refresh');
      return;
    }

    final repository = context.read<RohdModuleBloc>().repository;

    setState(() => _isLoadingFile = true);

    // Allow the loading overlay to render before starting heavy processing
    await Future<void>.delayed(Duration.zero);

    try {
      late List<int> bytes;

      // Priority 1: Use File System Access API handle (true disk reload on web)
      if (_fileHandle != null) {
        debugPrint(
          '[Home] Reloading from disk via File System Access API: '
          '${_fileHandle!.name}',
        );
        try {
          bytes = await _fileHandle!.readBytes();
          // Update stored bytes with fresh data
          _fileBytes = bytes;
          debugPrint('[Home] Read ${bytes.length} fresh bytes from disk');
        } on Object catch (e) {
          debugPrint('[Home] Failed to read via FSAA handle: $e');
          // Fall through to other methods
          if (_filePath != null && _filePath!.isNotEmpty) {
            bytes = await platform.readFileBytes(_filePath!);
          } else if (_fileBytes != null) {
            debugPrint('[Home] Falling back to stored bytes');
            bytes = _fileBytes!;
          } else {
            throw Exception('No file data available for refresh');
          }
        }
      }
      // Priority 2: Use file path on native platforms
      else if (_filePath != null && _filePath!.isNotEmpty) {
        debugPrint('[Home] Reloading from disk path: $_filePath');
        try {
          bytes = await platform.readFileBytes(_filePath!);
          debugPrint('[Home] Read ${bytes.length} bytes from disk');
        } on Object catch (e) {
          // Web platform doesn't support file reading - use stored bytes.
          if (e is! UnsupportedError) {
            rethrow;
          }
          if (_fileBytes != null) {
            debugPrint('[Home] File reading not supported, using stored bytes');
            bytes = _fileBytes!;
          } else {
            throw Exception('No file data available for refresh');
          }
        }
      }
      // Priority 3: Fallback to stored bytes (no disk reload)
      else if (_fileBytes != null) {
        debugPrint(
          '[Home] Reloading from memory (no file handle or path available)',
        );
        bytes = _fileBytes!;
      } else {
        throw Exception('No file data available for refresh');
      }

      final api = repository.api;

      // ── Smart reload: preserve signal list, tree, and search state ──
      // Only clear stale waveform data; keep signal metadata cache so
      // the hierarchy tree and module-signals panel stay intact.
      repository.clearAllWaveformData();

      if (api is WellenSignalWaveformApi) {
        await api.loadBytes(bytes, fileName: _fileName);
      } else {
        final newApi = WellenSignalWaveformApi();
        await newApi.loadBytes(bytes, fileName: _fileName);
        repository.setSignalWaveformApi(newApi);
      }

      if (mounted) {
        // Re-read hierarchy & metadata (e.g. new endTime) while
        // keeping the same selected module and tree expansion.
        context.read<RohdModuleBloc>().add(const RohdModuleRefresh());

        // Re-fetch waveform data for every signal in the monitor list
        // so traces update to the new file contents.
        context.read<SignalBloc>().add(SignalRefreshEvent());
      }
    } on Object catch (e, stackTrace) {
      debugPrint('[Home] Error refreshing: $e');
      debugPrint('[Home] Stack trace: $stackTrace');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error refreshing file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingFile = false);
      }
    }
  }

  // ─────────────── SignalOccurrence list save / restore ───────────────

  /// Save the current monitored signal list to a JSON file.
  ///
  /// The file contains an ordered list of full signal paths so the exact set
  /// can be restored later across sessions, machines, or waveform reloads.
  ///
  /// Uses the same File System Access API as VCD loading (Chrome/Edge),
  /// falling back to FilePicker on other browsers/platforms.
  Future<void> _saveSignalList() async {
    final signalState = context.read<SignalBloc>().state;
    if (signalState.monitorSignalsList.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No signals to save')));
      }
      return;
    }

    // Build ordered row records. Version 3 also preserves each row's display
    // format, allowing duplicate logical signals to have independent formats.
    final signalEntries = signalState.monitorSignalsList
        .map(
          (waveform) => SignalListEntry(
            id: waveform.signalId,
            width: waveform.overrideWidth,
            displayName: waveform.overrideName,
            valueFormat: waveform.valueFormat,
            monitorGroup: waveform.monitorGroup,
          ),
        )
        .toList();

    final waveformState = context.read<WaveformModuleBloc>().state;
    final json = SignalListPersistence.encode(
      entries: signalEntries,
      session: SignalListSessionState(
        showInternalSignals: signalState.showInternalSignals,
        filterText: signalState.filterText,
        cursorTimePs:
            waveformState is UpdatedCursor ? waveformState.timePs : null,
        measurementMarkerTimePs: _measurementMarkerNotifier.value,
        rowScale: context.read<WaveformScaleCubit>().state,
        themeMode: context.read<WaveViewerThemeCubit>().state,
        hierarchyPinned: _hierarchyPinned,
        appBarPinned: _appBarPinned,
        pinnedPanelWidth: _pinnedPanelWidth,
        viewport: SignalListViewportState(
          zoomLevel: _viewportNotifier.value.zoomLevel,
          scrollFraction: _viewportNotifier.value.scrollFraction,
        ),
      ),
    );

    final bytes = Uint8List.fromList(utf8.encode(json));

    try {
      // In extension mode, delegate to the VS Code extension host which
      // shows a native vscode.window.showSaveDialog.
      debugPrint('[Home] _isVscodeWebview=$_isVscodeWebview');
      if (_isVscodeWebview) {
        debugPrint('[Home] Calling requestExtensionSaveSignalList');
        vscode.requestExtensionSaveSignalList(json);
        debugPrint('[Home] requestExtensionSaveSignalList returned');
        return;
      }

      // Try File System Access API first (Chrome/Edge standalone).
      if (platform.isFileSystemAccessSupported) {
        final saved = await platform.showSaveFilePickerNative(
          bytes: bytes,
          extensions: ['json'],
        );
        if (saved) {
          return;
        }
        // User cancelled — don't fall through, respect the cancellation
        return;
      }

      // Fall back to file_selector (native Linux/macOS/Windows).
      const typeGroup = XTypeGroup(
        label: 'JSON files',
        extensions: <String>['json'],
      );
      final location = await getSaveLocation(
        acceptedTypeGroups: <XTypeGroup>[typeGroup],
        suggestedName: 'signals.json',
      );
      if (location != null) {
        final file = XFile.fromData(bytes, name: 'signals.json');
        await file.saveTo(location.path);
      }
    } on Object catch (e) {
      debugPrint('[Home] Error saving signal list: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving signal list: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Load a signal list from a JSON file and append to the current monitor
  /// list (duplicates are skipped).
  ///
  /// Uses the same File System Access API as VCD loading (Chrome/Edge),
  /// falling back to FilePicker on other browsers/platforms.
  Future<void> _loadSignalList() async {
    try {
      String? content;

      // In extension mode, delegate to the VS Code extension host which
      // shows a native vscode.window.showOpenDialog on the container FS.
      if (_isVscodeWebview) {
        content = await vscode.requestExtensionLoadSignalList();
      }

      if (content == null && !_isVscodeWebview) {
        List<int>? bytes;

        // Try File System Access API first (same mechanism as VCD loading)
        if (platform.isFileSystemAccessSupported) {
          final handle = await platform.showOpenFilePickerNative(
            extensions: ['json'],
          );
          if (handle != null) {
            bytes = await handle.readBytes();
          }
        }

        // Fall back to file_selector if FSAA not available or user cancelled
        if (bytes == null) {
          const typeGroup = XTypeGroup(
            label: 'JSON files',
            extensions: <String>['json'],
          );
          final xfile = await openFile(
            acceptedTypeGroups: <XTypeGroup>[typeGroup],
          );
          if (xfile != null) {
            bytes = await xfile.readAsBytes();
          }
        }

        if (bytes != null) {
          content = utf8.decode(bytes);
        }
      }

      if (content == null) {
        return;
      }
      if (!mounted) {
        return;
      }

      final moduleStructure =
          context.read<RohdModuleBloc>().state.moduleStructure;
      final restorePlan = SignalListPersistence.decodeAndResolve(
        content: content,
        structure: moduleStructure,
      );

      if (restorePlan.skippedPaths.isNotEmpty) {
        debugPrint(
          '[Home] Skipped ${restorePlan.skippedPaths.length} '
          'unresolved signals: '
          '${restorePlan.skippedPaths.take(5).join(", ")}',
        );
      }

      if (restorePlan.entries.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No matching signals found in current hierarchy'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final events = <SignalEvent>[
        SignalRestoreMonitoredEvent(
          restorePlan.signalPaths,
          metadata: restorePlan.metadata,
          valueFormats: restorePlan.valueFormats,
          monitorGroups: restorePlan.monitorGroups,
        ),
      ];
      final session = restorePlan.session;
      if (session != null) {
        if (session.showInternalSignals != null) {
          events.add(
            SignalToggleInternalSignalsEvent(
              enable: session.showInternalSignals!,
            ),
          );
        }
        if (session.filterText != null) {
          events.add(SignalFilterEvent(session.filterText!));
        }
        if (session.cursorTimePs != null) {
          context
              .read<WaveformModuleBloc>()
              .add(WaveformModuleOnTap(session.cursorTimePs!));
        }
        if (session.measurementMarkerTimePs != null) {
          _measurementMarkerNotifier.value = session.measurementMarkerTimePs;
        }
        if (session.rowScale != null) {
          context.read<WaveformScaleCubit>().setScale(session.rowScale!);
        }
        if (session.themeMode != null) {
          context.read<WaveViewerThemeCubit>().setTheme(session.themeMode!);
        }
        if (session.hierarchyPinned != null ||
            session.appBarPinned != null ||
            session.pinnedPanelWidth != null) {
          setState(() {
            if (session.hierarchyPinned != null) {
              _hierarchyPinned = session.hierarchyPinned!;
            }
            if (session.appBarPinned != null) {
              _appBarPinned = session.appBarPinned!;
            }
            if (session.pinnedPanelWidth != null) {
              _pinnedPanelWidth = session.pinnedPanelWidth!.clamp(
                _minSelectedSignalsWidth,
                600.0,
              );
            }
          });
        }
        if (session.viewport != null) {
          _viewportNotifier.value = WaveformViewport(
            zoomLevel: session.viewport!.zoomLevel,
            scrollFraction: session.viewport!.scrollFraction,
          );
        }
      }
      final signalBloc = context.read<SignalBloc>();
      events.forEach(signalBloc.add);

      if (mounted) {
        final msg = restorePlan.skippedPaths.isEmpty
            ? 'Appended ${restorePlan.entries.length} signals'
            : 'Appended ${restorePlan.entries.length} signals '
                '(${restorePlan.skippedPaths.length} not found)';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
        );
      }
    } on Object catch (e) {
      debugPrint('[Home] Error loading signal list: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading signal list: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Scroll all three vertical controllers so the signal at [index] is visible.
  void _scrollToSignalIndex(int index) {
    // Wait for the next frame so the ListViews have laid out the new item.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final rh = context.read<WaveformScaleCubit>().scaledRowHeight;
      final targetOffset = index * rh;
      for (final controller in [
        _selectedSignalsScrollController,
        _signalValueScrollController,
        _waveformVerticalScrollController,
      ]) {
        if (controller.hasClients) {
          final maxExtent = controller.position.maxScrollExtent;
          final viewportHeight = controller.position.viewportDimension;
          final currentOffset = controller.offset;
          final itemTop = targetOffset;
          final itemBottom = targetOffset + rh;
          if (itemBottom > currentOffset + viewportHeight ||
              itemTop < currentOffset) {
            // Jump (no animation) so there's no visible scroll-up-then-down.
            final desired = (itemBottom - viewportHeight).clamp(0.0, maxExtent);
            controller.jumpTo(desired);
          } else {
            // Item already visible — nudge the scrollbar to re-read metrics
            // (handles the case where content grew but scroll offset didn't
            // change).
            controller.position.notifyListeners();
          }
        }
      }
    });
  }

  @override
  Widget build(
    BuildContext context,
  ) =>
      BlocListener<WaveformScaleCubit, double>(
        listener: (context, scale) {
          _dragController.rowHeight = baseSignalRowHeight * scale;
        },
        child: BlocListener<SignalBloc, SignalState>(
          listenWhen: (prev, curr) =>
              curr is SignalLoaded &&
              (curr.monitorSignalsList.length != _lastMonitorCount ||
                  curr.scrollToIndex != null),
          listener: (context, state) {
            if (state is SignalLoaded) {
              final newCount = state.monitorSignalsList.length;
              if (state.scrollToIndex != null) {
                // Scroll to the requested signal index (e.g. duplicate
                // selection).
                _scrollToSignalIndex(state.scrollToIndex!);
              } else if (newCount > _lastMonitorCount) {
                // A signal was added — scroll to it (last item).
                _scrollToSignalIndex(newCount - 1);
              }
              _lastMonitorCount = newCount;
            }
          },
          child: Scaffold(
            body: AppBarOverlay(
              autoHide:
                  !_appBarPinned && _hasWaveformsLoaded && !_isLoadingFile,
              appBar: AppBar(
                toolbarHeight: 38,
                leadingWidth: 40,
                leading: Tooltip(
                  message: _appBarPinned ? 'Unpin top bar' : 'Pin top bar',
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 16,
                    icon: LayoutDockIcon(
                      edge: LayoutDockEdge.top,
                      locked: _appBarPinned,
                      color: _appBarPinned
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).brightness == Brightness.dark
                              ? Colors.white54
                              : Colors.black54,
                    ),
                    onPressed: () {
                      setState(() => _appBarPinned = !_appBarPinned);
                    },
                  ),
                ),
                title: Row(
                  children: [
                    platformIcon(
                      Icons.waves,
                      '🌊',
                      size: 24,
                      hasColorEmoji: _hasColorEmoji,
                    ),
                    const SizedBox(width: 12),
                    const Text('ROHD Wave Viewer'),
                    if (_fileName != null) ...[
                      const SizedBox(width: 16),
                      Text(
                        '- $_fileName',
                        style: const TextStyle(
                            fontSize: 14, color: Colors.white70),
                      ),
                    ],
                  ],
                ),
                actions: [
                  // Only show file picker in standalone mode, not in extension
                  // mode
                  if (!_isExtensionMode)
                    IconButton(
                      icon: const WaveformFileOpenIcon(),
                      tooltip: 'Load waveform file',
                      onPressed: _isLoadingFile ? null : _loadVcdFile,
                    ),
                  // Reload button: show in VS Code webview (reload from disk
                  // via extension host) and in standalone (reload from file
                  // handle). Hide when embedded in DevTools — the parent
                  // controls loading.
                  if (_isVscodeWebview || !_isExtensionMode)
                    IconButton(
                      icon: platformIcon(
                        Icons.refresh,
                        '🔄',
                        hasColorEmoji: _hasColorEmoji,
                      ),
                      tooltip: _isVscodeWebview
                          ? 'Reload file from disk'
                          : 'Reload waveform',
                      // In VS Code webview, always enabled; in standalone, need
                      // a file loaded
                      onPressed: _isVscodeWebview || _fileName != null
                          ? _refreshWaveform
                          : null,
                    ),
                  BlocBuilder<SignalBloc, SignalState>(
                    builder: (context, _) {
                      final signalBloc = context.read<SignalBloc>();
                      return IconButton(
                        icon: const Icon(Icons.undo),
                        tooltip: 'Undo monitor list edit',
                        onPressed: signalBloc.canUndoMonitorEdit
                            ? () => signalBloc.add(SignalUndoMonitorEvent())
                            : null,
                      );
                    },
                  ),
                  BlocBuilder<SignalBloc, SignalState>(
                    builder: (context, _) {
                      final signalBloc = context.read<SignalBloc>();
                      return IconButton(
                        icon: const Icon(Icons.redo),
                        tooltip: 'Redo monitor list edit',
                        onPressed: signalBloc.canRedoMonitorEdit
                            ? () => signalBloc.add(SignalRedoMonitorEvent())
                            : null,
                      );
                    },
                  ),
                  // Save / restore monitored signal list
                  IconButton(
                    icon: platformIcon(
                      Icons.save,
                      '💾',
                      hasColorEmoji: _hasColorEmoji,
                    ),
                    tooltip: 'Save signal list',
                    onPressed: _saveSignalList,
                  ),
                  IconButton(
                    icon: platformIcon(
                      Icons.folder_open,
                      '📂',
                      hasColorEmoji: _hasColorEmoji,
                    ),
                    tooltip: 'Load signal list',
                    onPressed: _loadSignalList,
                  ),
                  // Snapshot button - captures all signal values at current
                  // marker. Only shown when embedded in another application
                  // (not standalone or VS Code webview) where a VM service can
                  // provide the callback.
                  if (widget._isExtensionMode)
                    BlocBuilder<WaveformModuleBloc, WaveformModuleState>(
                      buildWhen: (prev, curr) => prev.timePs != curr.timePs,
                      builder: (context, waveformState) {
                        // Use canSnapshotNotifier reactively when available,
                        // otherwise fall back to checking onSnapshotRequested.
                        // ignore: avoid_positional_boolean_parameters
                        Widget buildSnapshotButton(bool canSnapshot) {
                          final hasMarker = waveformState.timePs > 0;
                          final isVideo = widget._isVideoMode;
                          // Camera button is disabled in video mode (marker is
                          // irrelevant — values track the live simulation end).
                          final enabled = canSnapshot && hasMarker && !isVideo;
                          final lastTime = widget._lastSnapshotTimePs;

                          // Build a descriptive tooltip
                          String tooltip;
                          if (!canSnapshot) {
                            tooltip = lastTime != null
                                ? 'Snapshot unavailable (VM ended)\n'
                                    'Last snapshot: $lastTime ps'
                                : 'Snapshot unavailable (VM ended)';
                          } else if (!hasMarker) {
                            tooltip = lastTime != null
                                ? 'Place marker first to take snapshot\n'
                                    'Last snapshot: $lastTime ps'
                                : 'Place marker first to take snapshot';
                          } else {
                            tooltip = lastTime != null
                                ? 'Snapshot all signals at marker '
                                    '(${waveformState.timePs} ps)\n'
                                    'Last snapshot: $lastTime ps'
                                : 'Snapshot all signals at marker '
                                    '(${waveformState.timePs} ps)';
                          }

                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: platformIcon(
                                  Icons.camera_alt,
                                  '📸',
                                  hasColorEmoji: _hasColorEmoji,
                                  color: enabled ? null : Colors.white38,
                                ),
                                tooltip: tooltip,
                                onPressed: enabled
                                    ? () => widget._onSnapshotRequested!(
                                          waveformState.timePs,
                                        )
                                    : null,
                              ),
                              // Video mode toggle — switches between one-shot
                              // (camera) and live-tracking (videocam)
                              // snapshots.
                              if (widget._onVideoModeToggled != null)
                                Opacity(
                                  opacity: isVideo ? 1.0 : 0.38,
                                  child: IconButton(
                                    icon: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        platformIcon(
                                          Icons.videocam,
                                          '🎥',
                                          hasColorEmoji: _hasColorEmoji,
                                        ),
                                        if (isVideo)
                                          const Text(
                                            '🔴',
                                            style: TextStyle(fontSize: 8),
                                          ),
                                      ],
                                    ),
                                    tooltip: isVideo
                                        ? 'Live tracking ON — auto-snapshots '
                                            'at latest time.\nClick to switch '
                                            'to '
                                            'manual '
                                            'marker mode.'
                                        : 'Manual mode — snapshots at marker.\n'
                                            'Click to enable live tracking.',
                                    onPressed: canSnapshot
                                        ? widget._onVideoModeToggled
                                        : null,
                                  ),
                                ),
                            ],
                          );
                        }

                        if (widget._canSnapshotNotifier != null) {
                          return ValueListenableBuilder<bool>(
                            valueListenable: widget._canSnapshotNotifier!,
                            builder: (context, canSnapshot, _) =>
                                buildSnapshotButton(canSnapshot),
                          );
                        }
                        return buildSnapshotButton(
                          widget._onSnapshotRequested != null,
                        );
                      },
                    ),
                  BlocBuilder<SignalBloc, SignalState>(
                    buildWhen: (prev, curr) =>
                        prev.showInternalSignals != curr.showInternalSignals,
                    builder: (context, state) {
                      final active = state.showInternalSignals;
                      return IconButton(
                        icon: platformIcon(
                          active ? Icons.visibility : Icons.visibility_off,
                          active ? '👁' : '🚫',
                          color: active ? Colors.white : Colors.white38,
                          hasColorEmoji: _hasColorEmoji,
                        ),
                        tooltip: active
                            ? 'Hide internal signals'
                            : 'Show internal signals',
                        onPressed: () {
                          context.read<SignalBloc>().add(
                                SignalToggleInternalSignalsEvent(
                                    enable: !active),
                              );
                        },
                      );
                    },
                  ),
                  if (widget._crossProbeService != null)
                    CrossProbeButton(service: widget._crossProbeService!),
                  const VerticalDivider(width: 1, color: Colors.white24),
                  // Waveform row height scale controls
                  BlocBuilder<WaveformScaleCubit, double>(
                    builder: (context, scale) => SizedBox(
                      width: 28,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 24,
                            height: 18,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              iconSize: 14,
                              icon: Icon(
                                Icons.arrow_drop_up,
                                size: 20,
                                color: scale < WaveformScaleCubit.maxScale
                                    ? Colors.redAccent
                                    : Colors.white24,
                              ),
                              tooltip: 'Increase row height '
                                  '(${(scale * 100).round()}%)',
                              onPressed: scale < WaveformScaleCubit.maxScale
                                  ? () => context
                                      .read<WaveformScaleCubit>()
                                      .scaleUp()
                                  : null,
                            ),
                          ),
                          SizedBox(
                            width: 24,
                            height: 18,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              iconSize: 14,
                              icon: Icon(
                                Icons.arrow_drop_down,
                                size: 20,
                                color: scale > WaveformScaleCubit.minScale
                                    ? Colors.lightBlueAccent
                                    : Colors.white24,
                              ),
                              tooltip: 'Decrease row height '
                                  '(${(scale * 100).round()}%)',
                              onPressed: scale > WaveformScaleCubit.minScale
                                  ? () => context
                                      .read<WaveformScaleCubit>()
                                      .scaleDown()
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 1, color: Colors.white24),
                  BlocBuilder<WaveViewerThemeCubit, WaveViewerThemeMode>(
                    buildWhen: (prev, curr) => prev != curr,
                    builder: (context, themeMode) {
                      final isDark = themeMode == WaveViewerThemeMode.dark;
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Hide internal help button when embedded in devtools
                          // (the tab navbar provides the help button instead).
                          if (_isVscodeWebview || !_isExtensionMode)
                            WaveViewerHelpButton(
                              isDark: isDark,
                              hasColorEmoji: _hasColorEmoji,
                              isEmbedded: false,
                            ),
                          Tooltip(
                            message: isDark
                                ? 'Switch to light theme'
                                : 'Switch to dark theme',
                            child: IconButton(
                              icon: platformIcon(
                                isDark ? Icons.light_mode : Icons.dark_mode,
                                isDark ? '☀️' : '🌙',
                                hasColorEmoji: _hasColorEmoji,
                              ),
                              onPressed: () {
                                context
                                    .read<WaveViewerThemeCubit>()
                                    .toggleTheme();
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              body: Focus(
                // Top-level key handler for shortcuts that should work across
                // all panels.  When an EditableText (TextField) has focus, it
                // consumes character keys before they bubble up here, so the
                // shortcut only fires when the user is NOT typing.
                canRequestFocus: false,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent || _isTextInputFocused()) {
                    return KeyEventResult.ignored;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.keyF) {
                    _fitCommandNotifier.value++;
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.delete ||
                      event.logicalKey == LogicalKeyboardKey.backspace) {
                    final signalBloc = context.read<SignalBloc>();
                    final focusedSignals = signalBloc.state.focusedSignals;
                    if (focusedSignals.isEmpty) {
                      return KeyEventResult.ignored;
                    }
                    signalBloc.add(
                      SignalRemoveManyEvent(
                        focusedSignals.map((waveform) => waveform.monitorId),
                      ),
                    );
                    return KeyEventResult.handled;
                  }
                  final hasCommandModifier =
                      HardwareKeyboard.instance.isControlPressed ||
                          HardwareKeyboard.instance.isMetaPressed;
                  if (!hasCommandModifier) {
                    return KeyEventResult.ignored;
                  }
                  final signalBloc = context.read<SignalBloc>();
                  final isRedo = event.logicalKey == LogicalKeyboardKey.keyY ||
                      (event.logicalKey == LogicalKeyboardKey.keyZ &&
                          HardwareKeyboard.instance.isShiftPressed);
                  if (isRedo && signalBloc.canRedoMonitorEdit) {
                    signalBloc.add(SignalRedoMonitorEvent());
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.keyZ &&
                      signalBloc.canUndoMonitorEdit) {
                    signalBloc.add(SignalUndoMonitorEvent());
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: BlocListener<RohdModuleBloc, RohdModuleState>(
                  // Always-mounted listener that bridges module selection →
                  // signal loading.  Previously this lived inside
                  // ModuleTreePanel (in the overlay), so it wasn't mounted when
                  // the file first loaded and the overlay was hidden.
                  listener: (context, state) {
                    if (state is ModuleSelected) {
                      _refreshModuleInfoForModule(state.singleModule);
                      context.read<SignalBloc>().add(
                            SignalUpdateEvent(state.singleModule),
                          );
                    }
                    if (state is Rendered &&
                        state.moduleStructure.modules.isNotEmpty) {
                      _refreshModuleInfoForModule(
                        state.moduleStructure.modules.first,
                        force: true,
                      );
                      context.read<SignalBloc>().add(
                            SignalUpdateEvent(
                                state.moduleStructure.modules.first),
                          );
                      if (!_hasWaveformsLoaded) {
                        setState(() => _hasWaveformsLoaded = true);
                      }
                    }
                    if (state is WaveformUpdated) {
                      context.read<SignalBloc>().add(
                            SignalRefreshEvent(cacheOnly: true),
                          );
                      if (!_hasWaveformsLoaded) {
                        setState(() => _hasWaveformsLoaded = true);
                      }
                    }
                  },
                  child: _buildBodyLayout(context),
                ), // BlocListener (module→signal bridge)
              ), // Focus
            ), // AppBarOverlay
          ), // Scaffold
        ), // BlocListener (SignalBloc)
      );

  /// The hierarchy [HierarchyWidget] shared between pinned and overlay modes.
  /// Extracted so the same instance is used regardless of pin state, keeping
  /// BLoC providers in the parent context intact.
  Widget _buildHierarchyChild(BuildContext context) => HierarchyWidget(
        repository: context.read<RohdModuleBloc>().repository,
        isEmbedded: widget._isExtensionMode,
        onSendSignals: _effectiveSendSignals,
        onGoToSource: _effectiveGoToSource,
        availableSourceFormats: _availableSourceFormats,
      );

  /// Compute the ideal pinned-panel width from the widest signal name
  /// currently available in the module signals (not just selected ones).
  ///
  /// This ensures the pinned module tree/selection pane is wide enough to
  /// display any signal in the current module without truncation.
  double _computePinnedPanelWidth() {
    final signalState = context.read<SignalBloc>().state;
    if (signalState is! SignalLoaded || signalState.signals.isEmpty) {
      return _selectedSignalsWidth.clamp(180.0, 600.0);
    }

    final textStyle = DefaultTextStyle.of(context).style;

    double maxWidth = 0;
    for (final signal in signalState.signals) {
      final displayName = formatSignalNameWithWidth(signal.name, signal.width);
      final tp = TextPainter(
        text: TextSpan(text: displayName, style: textStyle),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      if (tp.width > maxWidth) {
        maxWidth = tp.width;
      }
      tp.dispose();
    }

    // Add padding for row insets, check icon, scrollbar, etc.
    return (maxWidth + 80).clamp(180.0, 600.0);
  }

  /// Draggable vertical divider between the pinned hierarchy panel and
  /// the Selected Signals pane.  Resizes only the hierarchy panel.
  Widget _buildPinnedDivider(bool isDark) => MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: GestureDetector(
          onHorizontalDragUpdate: (details) {
            setState(() {
              _pinnedPanelWidth = (_pinnedPanelWidth + details.delta.dx).clamp(
                _minSelectedSignalsWidth,
                600.0,
              );
            });
          },
          child: Container(
            width: 6,
            color: isDark ? DarkThemeColors.divider : LightThemeColors.divider,
          ),
        ),
      );

  /// Build the main body layout.
  ///
  /// When the hierarchy is **pinned**, the layout is:
  ///   `Row` → [ HierarchyOverlay | Divider | SplitPane (SelectedSignals
  ///            + Value + Waveform) ]
  ///
  /// When **unpinned** (default), the layout is:
  ///   `Stack` → [ SplitPane (3 cols) ] + [ HierarchyOverlay (sliding) ]
  Widget _buildBodyLayout(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // ── Selected Signals pane wrapped in LayoutBuilder to track width ──
    final selectedSignalsPane = LayoutBuilder(
      builder: (context, constraints) {
        // Post-frame callback to avoid setState during build.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && constraints.maxWidth != _selectedSignalsWidth) {
            setState(() {
              _selectedSignalsWidth = constraints.maxWidth;
            });
          }
        });
        return DecoratedBox(
          decoration: panelDecoration(
            isDark: isDark,
            backgroundColor: isDark
                ? DarkThemeColors.panelBackground
                : LightThemeColors.panelBackground,
          ),
          child: SelectedSignalsPanel(
            scrollController: _selectedSignalsScrollController,
            dragController: _dragController,
            onSendSignals: _effectiveSendSignals,
            onGoToSource: _effectiveGoToSource,
            availableSourceFormats: _availableSourceFormats,
          ),
        );
      },
    );

    final signalValuePane = DecoratedBox(
      decoration: panelDecoration(
        isDark: isDark,
        backgroundColor: isDark
            ? DarkThemeColors.panelBackground
            : LightThemeColors.panelBackground,
      ),
      child: SignalValuePanel(
        scrollController: _signalValueScrollController,
        dragController: _dragController,
        isVideoMode: widget._isVideoMode,
      ),
    );

    final waveformPane = DecoratedBox(
      decoration: panelDecoration(
        isDark: isDark,
        backgroundColor: isDark
            ? DarkThemeColors.panelBackground
            : LightThemeColors.panelBackground,
      ),
      child: WaveformPanel(
        verticalScrollController: _waveformVerticalScrollController,
        fitNotifier: _fitCommandNotifier,
        dragController: _dragController,
        isVideoMode: widget._isVideoMode,
        viewportNotifier: _viewportNotifier,
        measurementMarkerNotifier: _measurementMarkerNotifier,
      ),
    );

    // ── SplitPane configuration ──
    // When pinned, all three panes (SelectedSignals, Value, Waveform) go
    // into a single SplitPane so the divider handles are visually consistent.
    final Widget splitPane;
    if (_hierarchyPinned) {
      splitPane = IgnorePointer(
        ignoring: _isLoadingFile,
        child: SplitPane(
          key: const ValueKey('pinned_svw'),
          axis: Axis.horizontal,
          initialFractions: const [0.20, 0.15, 0.65],
          minSizes: const [_minSelectedSignalsWidth, 50, 200],
          children: [selectedSignalsPane, signalValuePane, waveformPane],
        ),
      );
    } else {
      splitPane = IgnorePointer(
        ignoring: _isLoadingFile,
        child: SplitPane(
          key: const ValueKey('unpinned_svw'),
          axis: Axis.horizontal,
          initialFractions: const [0.20, 0.18, 0.62],
          minSizes: const [_minSelectedSignalsWidth, 50, 200],
          children: [selectedSignalsPane, signalValuePane, waveformPane],
        ),
      );
    }

    final hierarchyOverlay = HierarchyOverlay(
      panelWidth: _hierarchyPinned
          ? _pinnedPanelWidth
          : _selectedSignalsWidth.clamp(180, 600),
      isPinned: _hierarchyPinned,
      onPinChanged: (pinned) {
        setState(() {
          _hierarchyPinned = pinned;
          if (pinned) {
            // When pinning: compute width from widest signal in module signals
            // This ensures the pinned panel can display any signal without
            // truncation
            _pinnedPanelWidth = _computePinnedPanelWidth().clamp(
              _minSelectedSignalsWidth,
              600.0,
            );
            // Keep SelectedSignals width in sync so un-pinning picks
            // up the most recent value.
            _selectedSignalsWidth = _pinnedPanelWidth;
          }
          // When unpinning: size is not changed; the overlay reverts to
          // tracking the selected signals pane width
        });
      },
      child: _buildHierarchyChild(context),
    );

    final loadingOverlay = _isLoadingFile
        ? Positioned.fill(
            child: ColoredBox(
              color: isDark ? Colors.black54 : Colors.white54,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: CircularProgressIndicator(
                        color: isDark ? Colors.white : Colors.black87,
                        strokeWidth: 4,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Loading${_fileName != null ? " $_fileName" : ""}...',
                      style: TextStyle(
                        fontSize: 16,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        : null;

    // ── Pinned mode: hierarchy is a real pane beside the SplitPane ──
    if (_hierarchyPinned) {
      return Stack(
        children: [
          Row(
            children: [
              // Hierarchy panel as a normal pane
              hierarchyOverlay,
              // Draggable divider — resizes hierarchy + SelectedSignals
              // together
              _buildPinnedDivider(isDark),
              // SelectedSignals (same width) + Value/Waveform SplitPane
              Expanded(
                child: RepaintBoundary(
                  key: _exportBoundaryKey,
                  child: splitPane,
                ),
              ),
            ],
          ),
          if (loadingOverlay != null) loadingOverlay,
          ValueListenableBuilder<bool>(
            valueListenable: _snapshotModeNotifier,
            builder: (_, isSnapshot, child) =>
                isSnapshot ? const SizedBox.shrink() : child!,
            child: Positioned(
              right: 8,
              bottom: 8,
              child: ExportPngButton(
                onPressed: _exportToPng,
                tooltip: 'Export waveform as PNG',
              ),
            ),
          ),
        ],
      );
    }

    // ── Unpinned mode: overlay on top of the SplitPane ──
    return Stack(
      children: [
        RepaintBoundary(key: _exportBoundaryKey, child: splitPane),
        // Auto-hiding hierarchy overlay (slides in from left edge)
        Positioned.fill(child: hierarchyOverlay),
        if (loadingOverlay != null) loadingOverlay,
        ValueListenableBuilder<bool>(
          valueListenable: _snapshotModeNotifier,
          builder: (_, isSnapshot, child) =>
              isSnapshot ? const SizedBox.shrink() : child!,
          child: Positioned(
            right: 8,
            bottom: 8,
            child: ExportPngButton(
              onPressed: _exportToPng,
              tooltip: 'Export waveform as PNG',
            ),
          ),
        ),
      ],
    );
  }
}
