// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// wave_viewer_app.dart
// Internal application shell for the ROHD Wave Viewer.
//
// 2024 April
// Author(s): Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
//            Yao Jing Quek <yao.jing.quek@intel.com>

import 'dart:async' show unawaited;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart'
    show
        CrossProbeService,
        GoToSourceCallback,
        RohdExtensionClient,
        RohdSourceFormat,
        SignalValueFormatPreference,
        SignalValueFormatRegistry;
import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_wave_viewer/src/const/app_theme.dart';
import 'package:rohd_wave_viewer/src/cubit/wave_viewer_theme_cubit.dart';
import 'package:rohd_wave_viewer/src/cubit/waveform_scale_cubit.dart';
import 'package:rohd_wave_viewer/src/modules/home/view/home.dart';
import 'package:rohd_wave_viewer/src/modules/rohd_module/bloc/rohd_module_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/bloc/waveform_module_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/view/widgets/painters/waveform.dart';
import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';

/// Helper function to create a text theme with emoji support
// Apply Roboto font family and ensure emoji falls back to system fonts
TextTheme _buildEmojiSupportedTextTheme(TextTheme baseTheme) =>
    baseTheme.apply(fontFamily: 'Roboto');

/// Root widget for the ROHD wave viewer application.
class App extends StatefulWidget {
  /// Creates the ROHD wave viewer application widget.
  const App({
    required SignalWaveformRepository signalWaveformRepository,
    super.key,
    WaveViewerThemeMode? initialThemeMode,
    String title = 'ROHD Wave Viewer',
    HierarchyService? externalHierarchy,
    HierarchyOccurrence? selectedModule,
    Stream<WaveformUpdateEvent>? liveUpdates,
    bool isExtensionMode = false,
    String? initialWaveformSource,
    List<String>? initialMonitoredSignalPaths,
    void Function(int timePs)? onSnapshotRequested,
    ValueChanged<List<String>>? onMonitoredSignalsChanged,
    ValueNotifier<bool>? canSnapshotNotifier,
    int? lastSnapshotTimePs,
    bool isVideoMode = false,
    VoidCallback? onVideoModeToggled,
    void Function(List<String> signalPaths)? onSendSignals,
    GoToSourceCallback? onGoToSource,
    ValueNotifier<List<String>?>? incomingSignalPaths,
    CrossProbeService? crossProbeService,
    RohdExtensionClient? extensionClient,
    Stream<void>? apiReloads,
    Stream<String>? apiReloadErrors,
  })  : _signalWaveformRepository = signalWaveformRepository,
        _initialThemeMode = initialThemeMode,
        _title = title,
        _externalHierarchy = externalHierarchy,
        _selectedModule = selectedModule,
        _liveUpdates = liveUpdates,
        _isExtensionMode = isExtensionMode,
        _initialWaveformSource = initialWaveformSource,
        _initialMonitoredSignalPaths = initialMonitoredSignalPaths,
        _onSnapshotRequested = onSnapshotRequested,
        _onMonitoredSignalsChanged = onMonitoredSignalsChanged,
        _canSnapshotNotifier = canSnapshotNotifier,
        _lastSnapshotTimePs = lastSnapshotTimePs,
        _isVideoMode = isVideoMode,
        _onVideoModeToggled = onVideoModeToggled,
        _onSendSignals = onSendSignals,
        _onGoToSource = onGoToSource,
        _incomingSignalPaths = incomingSignalPaths,
        _crossProbeService = crossProbeService,
        _extensionClient = extensionClient,
        _apiReloads = apiReloads,
        _apiReloadErrors = apiReloadErrors;

  /// Repository used to fetch and cache waveform data.
  final SignalWaveformRepository _signalWaveformRepository;

  /// The initial theme mode for the wave viewer.
  /// If provided, the wave viewer will start with this theme.
  /// If null, defaults to dark theme.
  final WaveViewerThemeMode? _initialThemeMode;

  /// The title for the MaterialApp.
  /// When embedded in another app, the parent can set this to match its title.
  final String _title;

  /// External hierarchy service from the parent application.
  /// When provided, the wave viewer uses this hierarchy for module selection
  /// instead of loading its own from VCD data.

  /// External hierarchy service from the parent application.
  /// When provided, the wave viewer uses this hierarchy for module selection
  /// instead of loading its own from VCD data.
  final HierarchyService? _externalHierarchy;

  /// Optional stream of live waveform updates from VM service or other source.
  /// When provided, the wave viewer will listen for incremental waveform data.
  final Stream<WaveformUpdateEvent>? _liveUpdates;

  /// Whether running in extension mode (embedded in another app).
  /// When true, hides file picker and other standalone-only UI elements.
  final bool _isExtensionMode;

  /// URL, native file path, or Flutter asset loaded when the viewer starts.
  final String? _initialWaveformSource;

  /// SignalOccurrence hierarchy paths to restore after the new hierarchy loads.
  ///
  /// Saved before a full reconnect so the SignalBloc can attempt to
  /// re-add each signal to the monitor list once a module is selected.
  final List<String>? _initialMonitoredSignalPaths;

  /// Callback invoked when the user requests a snapshot of all signal values
  /// at the current marker time. The argument is the marker time in
  /// picoseconds.
  final void Function(int timePs)? _onSnapshotRequested;

  /// Called whenever the monitored signal list changes.
  ///
  /// The parent uses this to keep a live copy of the currently
  /// monitored signal paths so they can be saved/restored when
  /// switching between designs.
  final ValueChanged<List<String>>? _onMonitoredSignalsChanged;

  /// Live notifier for snapshot availability.
  ///
  /// When provided, the wave viewer's snapshot button reactively listens
  /// to this notifier via [ValueListenableBuilder] instead of deriving
  /// availability from `onSnapshotRequested` being non-null.
  final ValueNotifier<bool>? _canSnapshotNotifier;

  /// The time (in picoseconds) of the most recent snapshot, if any.
  /// Displayed in the snapshot button tooltip so the user knows when the
  /// last snapshot was taken — even when the button is disabled.
  final int? _lastSnapshotTimePs;

  /// Whether the snapshot system is in video (live tracking) mode.
  ///
  /// When `true`, the snapshot icon shows a video camera and the system
  /// automatically captures signal values on each waveform update.
  /// When `false` (default), shows a camera icon for manual snapshots.
  final bool _isVideoMode;

  /// Called when the user toggles between camera and video mode.
  ///
  /// The parent should update its state and pass the new `isVideoMode`
  /// value back.  If `null`, mode toggling is disabled.
  final VoidCallback? _onVideoModeToggled;

  /// Callback when user wants to send selected signals to other viewers.
  final void Function(List<String> signalPaths)? _onSendSignals;

  /// Callback when user wants to navigate to a signal's source for a chosen
  /// [RohdSourceFormat].
  final GoToSourceCallback? _onGoToSource;

  /// Notifier for incoming signal paths from other viewers (cross-probing).
  final ValueNotifier<List<String>?>? _incomingSignalPaths;

  /// Optional cross-probe service for communicating between viewers.
  final CrossProbeService? _crossProbeService;

  /// Optional ROHD extension client for source-format handshaking.
  final RohdExtensionClient? _extensionClient;

  /// Events emitted after the VS Code host successfully reloads waveform data.
  final Stream<void>? _apiReloads;

  /// Errors emitted when the VS Code host cannot reload waveform data.
  final Stream<String>? _apiReloadErrors;

  /// The currently selected module from the parent application.
  /// When this changes, the wave viewer will switch to display this module.
  final HierarchyOccurrence? _selectedModule;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final WaveViewerThemeCubit _themeCubit;
  late final WaveformScaleCubit _scaleCubit;
  late final SignalDataService _signalDataService;
  late final RohdModuleBloc _rohdModuleBloc;
  late final SignalBloc _signalBloc;

  // Pre-built ThemeData objects — avoids expensive ThemeData.dark().copyWith(),
  // ColorScheme.fromSeed() and the text theme setup on every theme
  // switch rebuild.  These are immutable so we build them once in initState().
  late final ThemeData _darkTheme;
  late final ThemeData _lightTheme;

  @override
  void initState() {
    super.initState();
    // Labels are re-enabled — strip-based tile cache keeps steady-state
    // frames within budget even with label rendering.
    Waveform.debugSuppressLabels = false;
    _themeCubit = WaveViewerThemeCubit(
      widget._initialThemeMode ?? WaveViewerThemeMode.dark,
    );
    _scaleCubit = WaveformScaleCubit();
    _signalDataService = RepositorySignalDataService(
      widget._signalWaveformRepository,
    );
    _rohdModuleBloc = RohdModuleBloc(
      signalWaveformRepository: widget._signalWaveformRepository,
      liveUpdates: widget._liveUpdates,
      expectsExternalHierarchy: widget._externalHierarchy != null,
    );
    _signalBloc = SignalBloc(
      widget._signalWaveformRepository,
      initialMonitoredSignalPaths: widget._initialMonitoredSignalPaths,
    );
    SignalValueFormatRegistry.changes.addListener(_applyExternalSignalFormats);

    // Build themes once — the heavy-lift calls (ColorScheme.fromSeed,
    // ThemeData.dark() now runs only at startup.
    _darkTheme = ThemeData.dark().copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.cyan,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: DarkThemeColors.scaffoldBackground,
      cardColor: DarkThemeColors.cardBackground,
      dividerColor: DarkThemeColors.divider,
      cardTheme: const CardThemeData(
        elevation: 0,
        shadowColor: Colors.transparent,
      ),
      appBarTheme: AppBarThemes.dark,
      popupMenuTheme: PopupMenuThemeData(
        color: const Color(0xFF3C3C3C).withValues(alpha: 0.85),
        elevation: 8,
        shadowColor: Colors.black54,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 13),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: const Color(0xFF3C3C3C).withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(4),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF2D2D30).withValues(alpha: 0.90),
        elevation: 16,
        shadowColor: Colors.black54,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: const TextStyle(color: Colors.white70, fontSize: 14),
      ),
      textTheme:
          _buildEmojiSupportedTextTheme(ThemeData.dark().textTheme).apply(
        bodyColor: DarkThemeColors.text,
        displayColor: DarkThemeColors.text,
      ),
    );
    _lightTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.white),
      scaffoldBackgroundColor: LightThemeColors.scaffoldBackground,
      cardColor: LightThemeColors.cardBackground,
      dividerColor: LightThemeColors.divider,
      cardTheme: const CardThemeData(
        elevation: 0,
        shadowColor: Colors.transparent,
      ),
      appBarTheme: AppBarThemes.light,
      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white.withValues(alpha: 0.97),
        elevation: 8,
        shadowColor: Colors.black26,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: Colors.black.withValues(alpha: 0.12)),
        ),
        textStyle: const TextStyle(color: Colors.black87, fontSize: 13),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: Colors.grey.shade700.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(4),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        elevation: 16,
        shadowColor: Colors.black26,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.black.withValues(alpha: 0.1)),
        ),
        titleTextStyle: const TextStyle(
          color: Colors.black87,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: const TextStyle(color: Colors.black54, fontSize: 14),
      ),
      textTheme:
          _buildEmojiSupportedTextTheme(ThemeData.light().textTheme).apply(
        bodyColor: LightThemeColors.text,
        displayColor: LightThemeColors.text,
      ),
    );

    // If external hierarchy is provided at init, use it
    if (widget._externalHierarchy != null) {
      _rohdModuleBloc.add(
        RohdModuleSetExternalHierarchy(
          widget._externalHierarchy!,
          selectedModule: widget._selectedModule,
        ),
      );
    }
  }

  @override
  void didUpdateWidget(covariant App oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync theme cubit when initialThemeMode changes
    if (widget._initialThemeMode != oldWidget._initialThemeMode &&
        widget._initialThemeMode != null) {
      _themeCubit.setTheme(widget._initialThemeMode!);
    }

    // Sync external hierarchy when it changes
    final externalHierarchyChanged =
        widget._externalHierarchy != oldWidget._externalHierarchy &&
            widget._externalHierarchy != null;
    if (externalHierarchyChanged) {
      debugPrint(
        '[App] didUpdateWidget: externalHierarchy changed, '
        'root=${widget._externalHierarchy!.root.name}, '
        'firing RohdModuleSetExternalHierarchy',
      );
      _rohdModuleBloc.add(
        RohdModuleSetExternalHierarchy(
          widget._externalHierarchy!,
          selectedModule: widget._selectedModule,
        ),
      );
    }

    // Re-subscribe to liveUpdates when the stream changes (e.g. VM
    // reconnect creates a new data source with a new broadcast stream).
    if (widget._liveUpdates != oldWidget._liveUpdates) {
      _rohdModuleBloc.updateLiveUpdates(widget._liveUpdates);
    }

    // Sync selected module when it changes
    if (!externalHierarchyChanged &&
        widget._selectedModule != oldWidget._selectedModule &&
        widget._selectedModule != null) {
      _selectModule(widget._selectedModule!);
    }
  }

  /// Select a module in the wave viewer.
  /// Uses the current module structure from the bloc state.
  void _selectModule(HierarchyOccurrence module) {
    final currentState = _rohdModuleBloc.state;
    // Get module structure from current state
    final moduleStructure = currentState.moduleStructure;
    _rohdModuleBloc.add(RohdModuleSelect(moduleStructure, module));
  }

  @override
  void dispose() {
    SignalValueFormatRegistry.changes.removeListener(
      _applyExternalSignalFormats,
    );
    unawaited(_themeCubit.close());
    unawaited(_scaleCubit.close());
    unawaited(_rohdModuleBloc.close());
    unawaited(_signalBloc.close());
    super.dispose();
  }

  void _applyExternalSignalFormats() {
    final pathsByFormat = <MonitorValueFormat, Set<String>>{};
    for (final waveform in _signalBloc.state.monitorSignalsList) {
      final path = waveform.fullPath ?? waveform.signalId;
      final address = waveform.signal?.address;
      final requestedFormat = SignalValueFormatRegistry.formatForAny([
        address,
      ]);
      if (address == null ||
          SignalValueFormatRegistry.formatToString(requestedFormat) ==
              waveform.valueFormat.name) {
        continue;
      }
      final waveformFormats = MonitorValueFormat.values.where(
        (format) =>
            format.name ==
            SignalValueFormatRegistry.formatToString(requestedFormat),
      );
      if (waveformFormats.isEmpty) {
        continue;
      }
      pathsByFormat
          .putIfAbsent(waveformFormats.first, () => <String>{})
          .add(path);
    }
    for (final entry in pathsByFormat.entries) {
      _signalBloc.add(
        SignalSetOccurrenceValueFormatEvent(
          signalPaths: entry.value,
          valueFormat: entry.key,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
        providers: [
          BlocProvider.value(value: _themeCubit),
          BlocProvider.value(value: _scaleCubit),
        ],
        child: BlocBuilder<WaveViewerThemeCubit, WaveViewerThemeMode>(
          builder: (context, themeMode) => MultiRepositoryProvider(
            providers: [
              RepositoryProvider<SignalWaveformRepository>.value(
                value: widget._signalWaveformRepository,
              ),
              RepositoryProvider<SignalDataService>.value(
                value: _signalDataService,
              ),
            ],
            child: MultiBlocProvider(
              providers: [
                BlocProvider<RohdModuleBloc>.value(value: _rohdModuleBloc),
                BlocProvider<SignalBloc>.value(value: _signalBloc),
                BlocProvider<WaveformModuleBloc>(
                  create: (context) => WaveformModuleBloc(
                    signalWaveformRepository: widget._signalWaveformRepository,
                  ),
                ),
              ],
              child: BlocListener<SignalBloc, SignalState>(
                listenWhen: (prev, curr) =>
                    prev.monitorSignalsList != curr.monitorSignalsList,
                listener: (context, state) {
                  // Same extraction as _saveSignalList — signalId is the
                  // hierarchy path used by save/load signal list JSON.
                  widget._onMonitoredSignalsChanged?.call(
                    state.monitorSignalsList.map((w) => w.signalId).toList(),
                  );
                  SignalValueFormatRegistry.update([
                    for (final waveform in state.monitorSignalsList)
                      if (waveform.signal?.address != null)
                        SignalValueFormatPreference(
                          waveform.signal!.address!,
                          SignalValueFormatRegistry.formatFromString(
                            waveform.valueFormat.name,
                          )!,
                        ),
                  ]);
                },
                child: MaterialApp(
                  title: widget._title,
                  themeMode: themeMode == WaveViewerThemeMode.dark
                      ? ThemeMode.dark
                      : ThemeMode.light,
                  darkTheme: _darkTheme,
                  theme: _lightTheme,
                  initialRoute: '/',
                  routes: {
                    '/': (_) => WaveFormViewerPage(
                          isExtensionMode: widget._isExtensionMode,
                          initialWaveformSource: widget._initialWaveformSource,
                          onSnapshotRequested: widget._onSnapshotRequested,
                          canSnapshotNotifier: widget._canSnapshotNotifier,
                          lastSnapshotTimePs: widget._lastSnapshotTimePs,
                          isVideoMode: widget._isVideoMode,
                          onVideoModeToggled: widget._onVideoModeToggled,
                          onSendSignals: widget._onSendSignals,
                          onGoToSource: widget._onGoToSource,
                          incomingSignalPaths: widget._incomingSignalPaths,
                          crossProbeService: widget._crossProbeService,
                          extensionClient: widget._extensionClient,
                          apiReloads: widget._apiReloads,
                          apiReloadErrors: widget._apiReloadErrors,
                        ),
                  },
                ),
              ),
            ),
          ),
        ),
      );
}
