// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// embedded_wave_viewer.dart
// Stable embeddable API for the ROHD Wave Viewer.
//
// 2026 September 29
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/foundation.dart'
    show
        DiagnosticPropertiesBuilder,
        EnumProperty,
        FlagProperty,
        IntProperty,
        IterableProperty,
        ObjectFlagProperty,
        StringProperty;
import 'package:material_ui/material_ui.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart'
    show CrossProbeService, GoToSourceCallback, RohdExtensionClient;
import 'package:rohd_hierarchy/rohd_hierarchy.dart'
    show HierarchyOccurrence, HierarchyService;
import 'package:rohd_wave_viewer/src/cubit/wave_viewer_theme_cubit.dart';
import 'package:rohd_wave_viewer/src/ui/wave_viewer_app.dart';
import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart'
    show SignalWaveformRepository;
import 'package:rohd_waveform/rohd_waveform.dart'
    show SignalWaveformApi, WaveformUpdateEvent;

/// An embeddable waveform viewer backed by a semantic waveform API.
///
/// The widget owns its repository and state-management implementation.
/// Embedders provide waveform data and controlled integration properties
/// without depending on the viewer's internal BLoCs or repositories.
class EmbeddedWaveViewer extends StatefulWidget {
  /// Creates an embedded waveform viewer.
  const EmbeddedWaveViewer({
    required this.waveformApi,
    super.key,
    this.apiReady,
    this.themeMode = WaveViewerThemeMode.dark,
    this.title = 'ROHD Wave Viewer',
    this.externalHierarchy,
    this.selectedModule,
    this.liveUpdates,
    this.isExtensionMode = false,
    this.initialMonitoredSignalPaths,
    this.onSnapshotRequested,
    this.onMonitoredSignalsChanged,
    this.canSnapshotNotifier,
    this.lastSnapshotTimePs,
    this.isVideoMode = false,
    this.onVideoModeToggled,
    this.onGoToSource,
    this.crossProbeService,
    this.extensionClient,
    this.apiReloads,
  });

  /// Waveform data source, or `null` while the host has no data available.
  final SignalWaveformApi? waveformApi;

  /// Completes when [waveformApi] is ready to serve data.
  final Future<void>? apiReady;

  /// Theme controlled by the embedding application.
  final WaveViewerThemeMode themeMode;

  /// Title used by the viewer's application shell.
  final String title;

  /// Optional hierarchy shared with another host surface.
  final HierarchyService? externalHierarchy;

  /// Module selected by the embedding application.
  final HierarchyOccurrence? selectedModule;

  /// Incremental waveform update stream.
  final Stream<WaveformUpdateEvent>? liveUpdates;

  /// Whether standalone-only controls should be hidden.
  final bool isExtensionMode;

  /// Signal paths restored when the viewer first loads a hierarchy.
  final List<String>? initialMonitoredSignalPaths;

  /// Called when a snapshot is requested at a time in picoseconds.
  final void Function(int timePs)? onSnapshotRequested;

  /// Called whenever the monitored signal paths change.
  final ValueChanged<List<String>>? onMonitoredSignalsChanged;

  /// Controls whether snapshot capture is currently available.
  final ValueNotifier<bool>? canSnapshotNotifier;

  /// Time of the most recent snapshot, in picoseconds.
  final int? lastSnapshotTimePs;

  /// Whether continuous video-style snapshots are enabled.
  final bool isVideoMode;

  /// Called when the user requests a snapshot-mode change.
  final VoidCallback? onVideoModeToggled;

  /// Navigates to source associated with selected signals.
  final GoToSourceCallback? onGoToSource;

  /// Preferred cross-probing integration service.
  final CrossProbeService? crossProbeService;

  /// Optional extension client for source-format discovery.
  final RohdExtensionClient? extensionClient;

  /// Events emitted after the host reloads waveform data.
  final Stream<void>? apiReloads;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(
        ObjectFlagProperty<SignalWaveformApi?>(
          'waveformApi',
          waveformApi,
          ifNull: 'no waveform data',
        ),
      )
      ..add(ObjectFlagProperty<Future<void>?>('apiReady', apiReady))
      ..add(EnumProperty<WaveViewerThemeMode>('themeMode', themeMode))
      ..add(StringProperty('title', title))
      ..add(
        ObjectFlagProperty<HierarchyService?>(
          'externalHierarchy',
          externalHierarchy,
        ),
      )
      ..add(
        ObjectFlagProperty<HierarchyOccurrence?>(
          'selectedModule',
          selectedModule,
        ),
      )
      ..add(ObjectFlagProperty<Stream<WaveformUpdateEvent>?>(
        'liveUpdates',
        liveUpdates,
      ))
      ..add(FlagProperty('isExtensionMode', value: isExtensionMode))
      ..add(
        IterableProperty<String>(
          'initialMonitoredSignalPaths',
          initialMonitoredSignalPaths,
        ),
      )
      ..add(
        ObjectFlagProperty<void Function(int)?>(
          'onSnapshotRequested',
          onSnapshotRequested,
        ),
      )
      ..add(
        ObjectFlagProperty<ValueChanged<List<String>>?>(
          'onMonitoredSignalsChanged',
          onMonitoredSignalsChanged,
        ),
      )
      ..add(
        ObjectFlagProperty<ValueNotifier<bool>?>(
          'canSnapshotNotifier',
          canSnapshotNotifier,
        ),
      )
      ..add(IntProperty('lastSnapshotTimePs', lastSnapshotTimePs))
      ..add(FlagProperty('isVideoMode', value: isVideoMode))
      ..add(
        ObjectFlagProperty<VoidCallback?>(
          'onVideoModeToggled',
          onVideoModeToggled,
        ),
      )
      ..add(ObjectFlagProperty<GoToSourceCallback?>(
        'onGoToSource',
        onGoToSource,
      ))
      ..add(ObjectFlagProperty<CrossProbeService?>(
        'crossProbeService',
        crossProbeService,
      ))
      ..add(ObjectFlagProperty<RohdExtensionClient?>(
        'extensionClient',
        extensionClient,
      ))
      ..add(ObjectFlagProperty<Stream<void>?>('apiReloads', apiReloads));
  }

  @override
  State<EmbeddedWaveViewer> createState() => _EmbeddedWaveViewerState();
}

class _EmbeddedWaveViewerState extends State<EmbeddedWaveViewer> {
  SignalWaveformRepository? _repository;
  var _apiGeneration = 0;

  @override
  void initState() {
    super.initState();
    _replaceApi();
  }

  @override
  void didUpdateWidget(covariant EmbeddedWaveViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.waveformApi != oldWidget.waveformApi ||
        widget.apiReady != oldWidget.apiReady) {
      _replaceApi();
    }
  }

  void _replaceApi() {
    _apiGeneration++;
    final api = widget.waveformApi;
    if (api == null) {
      _repository = null;
      return;
    }
    final repository = _repository;
    if (repository == null) {
      _repository = SignalWaveformRepository(
        signalWaveformApi: api,
        apiReady: widget.apiReady,
      );
    } else {
      repository.setSignalWaveformApi(api, apiReady: widget.apiReady);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = _repository;
    if (repository == null) {
      return MaterialApp(
        title: widget.title,
        themeMode: widget.themeMode == WaveViewerThemeMode.dark
            ? ThemeMode.dark
            : ThemeMode.light,
        darkTheme: ThemeData.dark(),
        theme: ThemeData.light(),
        home: const Scaffold(
          body: Center(child: Text('No waveform data available')),
        ),
      );
    }
    return App(
      key: ValueKey(_apiGeneration),
      signalWaveformRepository: repository,
      initialThemeMode: widget.themeMode,
      title: widget.title,
      externalHierarchy: widget.externalHierarchy,
      selectedModule: widget.selectedModule,
      liveUpdates: widget.liveUpdates,
      isExtensionMode: widget.isExtensionMode,
      initialMonitoredSignalPaths: widget.initialMonitoredSignalPaths,
      onSnapshotRequested: widget.onSnapshotRequested,
      onMonitoredSignalsChanged: widget.onMonitoredSignalsChanged,
      canSnapshotNotifier: widget.canSnapshotNotifier,
      lastSnapshotTimePs: widget.lastSnapshotTimePs,
      isVideoMode: widget.isVideoMode,
      onVideoModeToggled: widget.onVideoModeToggled,
      onGoToSource: widget.onGoToSource,
      crossProbeService: widget.crossProbeService,
      extensionClient: widget.extensionClient,
      apiReloads: widget.apiReloads,
    );
  }
}
