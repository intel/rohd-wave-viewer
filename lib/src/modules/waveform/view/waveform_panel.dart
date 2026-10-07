// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// waveform_panel.dart
// The waveform panel.
//
// 2024 April
// Author(s): Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
//            Yao Jing Quek <yao.jing.quek@intel.com>

import 'dart:convert';

import 'package:flutter/foundation.dart'
    show
        DiagnosticPropertiesBuilder,
        EnumProperty,
        ObjectFlagProperty,
        setEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_wave_viewer/src/const/const.dart';
import 'package:rohd_wave_viewer/src/cubit/waveform_scale_cubit.dart';
import 'package:rohd_wave_viewer/src/modules/rohd_module/bloc/rohd_module_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/shared/widgets/widgets.dart';
import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/bloc/waveform_module_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/view/widgets/painters/waveform.dart'
    as wfp;
import 'package:rohd_wave_viewer/src/modules/waveform/view/widgets/timescale.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/view/widgets/waveform_background.dart';
import 'package:rohd_wave_viewer/src/platform/platform.dart' as plat;
import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';
// Conditional import: use web implementation on web, no-op on native platforms

void _callJsForceRepaint() {
  try {
    plat.jsRohdForceRepaint();
  } on Object catch (_) {
    debugPrint('[WaveformPanel] JS force repaint error');
  }
}

/// Persistable horizontal waveform viewport state.
class WaveformViewport {
  /// Zoom multiplier applied to the waveform canvas.
  final double zoomLevel;

  /// Horizontal scroll position normalized to the current scroll extent.
  final double scrollFraction;

  /// Creates a viewport state.
  const WaveformViewport({this.zoomLevel = 1, this.scrollFraction = 0});
}

/// Panel that renders timescale, waveforms, and cursor interactions.
class WaveformPanel extends StatefulWidget {
  /// Optional vertical scroll controller shared with sibling panels.
  final ScrollController? _verticalScrollController;

  /// Notifier that triggers a fit-to-viewport action each time its value
  /// changes.  Allows parent widgets to invoke fit from any panel.
  final ValueNotifier<int>? _fitNotifier;

  /// Cross-panel drag-reorder controller.
  final DragReorderController? _dragController;

  /// When true, marker placement is disabled (video/live-tracking mode).
  final bool _isVideoMode;

  /// Font used for waveform values and overlay labels.
  final ValueFont valueFont;

  /// Synchronizes normalized viewport state with a session owner.
  final ValueNotifier<WaveformViewport>? _viewportNotifier;

  /// Optional local measurement marker. It never changes the primary cursor.
  final ValueNotifier<int?>? _measurementMarkerNotifier;

  /// Creates the waveform panel.
  const WaveformPanel({
    super.key,
    ScrollController? verticalScrollController,
    ValueNotifier<int>? fitNotifier,
    DragReorderController? dragController,
    bool isVideoMode = false,
    this.valueFont = ValueFont.robotoMono,
    ValueNotifier<WaveformViewport>? viewportNotifier,
    ValueNotifier<int?>? measurementMarkerNotifier,
  })  : _verticalScrollController = verticalScrollController,
        _fitNotifier = fitNotifier,
        _dragController = dragController,
        _isVideoMode = isVideoMode,
        _viewportNotifier = viewportNotifier,
        _measurementMarkerNotifier = measurementMarkerNotifier;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(EnumProperty<ValueFont>('valueFont', valueFont));
  }

  @override
  State<WaveformPanel> createState() => _WaveformPanelState();
}

class _WaveformPanelState extends State<WaveformPanel>
    with SingleTickerProviderStateMixin {
  // Key to access the WaveformBackgroundState so we can force repaints
  final GlobalKey _backgroundKey = GlobalKey();
  // Key to access the GestureDetector's RenderBox for coordinate conversion
  final GlobalKey _gestureDetectorKey = GlobalKey();

  double _zoomLevel = 1;
  double? _lastActualWidth;
  final ScrollController _horizontalScrollController = ScrollController();
  // Dedicated controller for the Layer 3 scrollbar strip so that
  // _horizontalScrollController is attached to exactly ONE scroll view
  // (Layer 1 SingleChildScrollView). The two are kept in sync.
  final ScrollController _scrollbarController = ScrollController();
  bool _syncingScroll = false; // guard against re-entrant sync
  late final ScrollController _verticalScrollController;
  final FocusNode _focusNode = FocusNode();
  final Set<LogicalKeyboardKey> _pressedKeys = {};
  double _trackedScrollOffset = 0; // Track scroll offset for zoom calculations
  // Guard to prevent scroll listener from overwriting _trackedScrollOffset
  // during zoom
  bool _zoomInProgress = false;

  // Guard against re-entrant navigation calls when key is held down
  bool _navigationInProgress = false;

  bool _restoringViewport = false;
  bool _publishingViewport = false;

  // Track the last navigation target time (for when BLoC updates are async)
  // Use null to indicate we haven't navigated yet
  int? _lastNavigationTargetTime;

  WaveformSearchCriterion _searchCriterion = WaveformSearchCriterion.risingEdge;

  // Counter to force multiple frame repaints after zoom (helps with embedded
  // webviews)
  int _forceRepaintFrames = 0;

  // Drag-reorder state: true when a plain (non-Ctrl) drag is reordering rows
  bool _isDragReorder = false;
  static const double _dragAutoScrollEdgePx = 24;
  static const double _dragAutoScrollStepPx = baseSignalRowHeight;

  // Zoom-to-region state
  int? _zoomRegionStartTime;
  int? _zoomRegionEndTime;
  bool _isSelectingZoomRegion = false;
  DateTime? _lastZoomRegionUpdate;

  // Cache the current timescale from the build method so handlers can use it
  // This ensures handlers use the same value (with fallback) as the UI
  int _currentTimescale = 20;

  // Use ValueNotifier to avoid full widget rebuilds during drag
  final ValueNotifier<({int? startTime, int? endTime, bool isSelecting})>
      _zoomRegionNotifier = ValueNotifier((
    startTime: null,
    endTime: null,
    isSelecting: false,
  ));

  // Hover tooltip state — shown only when the label in the hovered interval
  // is clipped or fully hidden.  Uses a ValueNotifier so updates bypass
  // setState and never interfere with scroll performance.
  final ValueNotifier<({String text, Offset position})?> _hoverTooltipNotifier =
      ValueNotifier(null);

  // Throttle hover tooltip updates to at most once per ~60 ms (≈16 fps).
  // This prevents _updateHoverTooltip from running at the full 60–120 Hz
  // mouse-move rate, which was the main contributor to the 7 ms avg
  // HandleInputEvent cost seen in the profiler trace.
  int _lastHoverUpdateUs = 0;
  static const int _hoverThrottleUs = 60000; // 60 ms in microseconds

  @override
  void initState() {
    super.initState();
    _verticalScrollController =
        widget._verticalScrollController ?? ScrollController();
    // Add listener to update timescale when scrolling
    _horizontalScrollController
      ..addListener(_onHorizontalScroll)
      // Keep the scrollbar strip controller in sync with the primary one.
      ..addListener(_syncPrimaryToScrollbar);
    _scrollbarController.addListener(_syncScrollbarToPrimary);
    // Keep focus listener silent in production
    _focusNode.addListener(() {});
    // Listen for fit-to-viewport commands from the global key handler.
    widget._fitNotifier?.addListener(_fitToViewport);
    widget._viewportNotifier?.addListener(_restoreViewport);
    // Ensure this panel receives keyboard focus when first shown so arrow
    // keys and other shortcuts work immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });

    // Listen for messages posted by the hosting page (index.html). We expect
    // messages with `{ type: 'shift_wheel', deltaY }` when the page detects a
    // Shift+wheel. This is a reliable fallback when Flutter's RawKeyboard state
    // is not reporting modifiers inside VS Code WebView.
    try {
      plat.addWindowMessageListener(_onWindowMessage);
    } on Object catch (_) {
      // ignore on non-web platforms
    }
  }

  void _onWindowMessage(dynamic rawData) {
    try {
      if (rawData == null) {
        return;
      }

      Map<String, dynamic>? data;

      if (rawData is String) {
        try {
          data = json.decode(rawData) as Map<String, dynamic>?;
        } on Object catch (_) {
          return;
        }
      } else if (rawData is Map) {
        data = Map<String, dynamic>.from(rawData);
      } else {
        // Unknown type - try to convert via toString/JSON
        try {
          final s = rawData.toString();
          data = json.decode(s) as Map<String, dynamic>?;
        } on Object catch (_) {
          return;
        }
      }

      if (data == null) {
        return;
      }

      final source = data['source']?.toString();
      final mtype = data['type']?.toString();

      // Lightweight debug: log unexpected messages to help diagnose host noise
      if (source == null || mtype == null) {
        debugPrint(
          '[WaveformPanel] host message ignored (no source/type): ${data.runtimeType}',
        );
        return;
      }

      if (source == 'rohd_wave_viewer' && mtype == 'shift_wheel') {
        // Extract deltaY and clientX from the Map
        num deltaY = 0;
        num? clientX;
        try {
          deltaY = (data['deltaY'] is num) ? data['deltaY'] as num : 0;
          clientX = (data['clientX'] is num) ? data['clientX'] as num : null;
        } on Object catch (_) {}

        // Immediately call JS force repaint before processing
        _callJsForceRepaint();

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }

          // Ensure focus is restored - focus can be lost when modifier keys are
          // used
          if (!_focusNode.hasFocus) {
            _focusNode.requestFocus();
          }

          final box = context.findRenderObject()! as RenderBox;
          final focalX = (clientX != null)
              ? box.globalToLocal(Offset(clientX.toDouble(), 0)).dx
              : box.size.width / 2.0;
          if (deltaY > 0) {
            _zoomWithPreservedPosition(1.0 / 1.5, focalViewportX: focalX);
          } else if (deltaY < 0) {
            _zoomWithPreservedPosition(1.5, focalViewportX: focalX);
          }

          // Force repaint after zoom
          _callJsForceRepaint();
        });
      } else {
        // ignore other message types
      }
    } on Object catch (_) {
      // ignore parsing errors
    }
  }

  void _onHorizontalScroll() {
    // Update tracked scroll offset synchronously for zoom math and
    // let listeners (e.g., header AnimatedBuilder) rebuild in the same frame.
    // Skip if a zoom operation is in progress to prevent race conditions.
    if (_zoomInProgress) {
      return;
    }
    if (_horizontalScrollController.hasClients) {
      _trackedScrollOffset = _horizontalScrollController.offset;
      _publishViewport();
    }
  }

  void _syncPrimaryToScrollbar() {
    if (_syncingScroll) {
      return;
    }
    if (!_horizontalScrollController.hasClients ||
        !_scrollbarController.hasClients) {
      return;
    }
    _syncingScroll = true;
    try {
      final target = _horizontalScrollController.offset.clamp(
        0.0,
        _scrollbarController.position.maxScrollExtent,
      );
      if ((_scrollbarController.offset - target).abs() > 0.01) {
        _scrollbarController.jumpTo(target);
      }
    } finally {
      _syncingScroll = false;
    }
  }

  void _syncScrollbarToPrimary() {
    if (_syncingScroll) {
      return;
    }
    if (!_horizontalScrollController.hasClients ||
        !_scrollbarController.hasClients) {
      return;
    }
    _syncingScroll = true;
    try {
      final target = _scrollbarController.offset.clamp(
        0.0,
        _horizontalScrollController.position.maxScrollExtent,
      );
      if ((_horizontalScrollController.offset - target).abs() > 0.01) {
        _horizontalScrollController.jumpTo(target);
      }
    } finally {
      _syncingScroll = false;
    }
  }

  @override
  void dispose() {
    widget._fitNotifier?.removeListener(_fitToViewport);
    widget._viewportNotifier?.removeListener(_restoreViewport);
    _horizontalScrollController
      ..removeListener(_onHorizontalScroll)
      ..removeListener(_syncPrimaryToScrollbar)
      ..dispose();
    _scrollbarController
      ..removeListener(_syncScrollbarToPrimary)
      ..dispose();
    _focusNode.dispose();
    _zoomRegionNotifier.dispose();
    _hoverTooltipNotifier.dispose();
    if (widget._verticalScrollController == null) {
      _verticalScrollController.dispose();
    }
    try {
      plat.removeWindowMessageListener(_onWindowMessage);
    } on Object catch (_) {}
    super.dispose();
  }

  /// Reset zoom to 1× and scroll to position 0 so the entire waveform
  /// fits in the viewport.  Callable externally via the fit notifier.
  void _fitToViewport() {
    setState(() {
      _zoomLevel = 1.0;
      try {
        if (_horizontalScrollController.hasClients) {
          _horizontalScrollController.jumpTo(0);
        } else {
          _trackedScrollOffset = 0.0;
        }
      } on Object catch (_) {}
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncPrimaryToScrollbar();
      _publishViewport();
    });
  }

  void _restoreViewport() {
    if (_publishingViewport) {
      return;
    }
    final viewport = widget._viewportNotifier?.value;
    if (viewport == null || !mounted) {
      return;
    }
    _restoringViewport = true;
    setState(() {
      _zoomLevel = viewport.zoomLevel.clamp(1.0, 100000.0);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _restoreScrollFraction(viewport.scrollFraction.clamp(0.0, 1.0));
        _restoringViewport = false;
        _publishViewport();
      }
    });
  }

  void _publishViewport() {
    final notifier = widget._viewportNotifier;
    if (notifier == null || _restoringViewport) {
      return;
    }
    final maxExtent = _horizontalScrollController.hasClients
        ? _horizontalScrollController.position.maxScrollExtent
        : 0.0;
    final scrollFraction = maxExtent > 0
        ? (_trackedScrollOffset / maxExtent).clamp(0.0, 1.0)
        : 0.0;
    final current = notifier.value;
    if ((current.zoomLevel - _zoomLevel).abs() > 0.0001 ||
        (current.scrollFraction - scrollFraction).abs() > 0.0001) {
      _publishingViewport = true;
      try {
        notifier.value = WaveformViewport(
          zoomLevel: _zoomLevel,
          scrollFraction: scrollFraction,
        );
      } finally {
        _publishingViewport = false;
      }
    }
  }

  void _zoomIn() {
    _zoomWithPreservedPosition(1.5);
  }

  void _zoomOut() {
    _zoomWithPreservedPosition(1.0 / 1.5);
  }

  /// Force multiple frame updates to ensure the compositor presents the frame.
  /// This is necessary in embedded webviews where single frame requests may be
  /// deferred. If [onComplete] is provided, it will be called after all frames
  /// are done.
  void _forceMultipleFrameUpdates([int frames = 2, VoidCallback? onComplete]) {
    // Immediately call the JS force repaint before scheduling frames
    _callJsForceRepaint();
    _forceRepaintFrames = frames;
    _forceRepaintOnComplete = onComplete;
    _scheduleNextForceFrame();
  }

  VoidCallback? _forceRepaintOnComplete;

  void _scheduleNextForceFrame() {
    if (_forceRepaintFrames <= 0 || !mounted) {
      // All frames done - call completion callback
      final callback = _forceRepaintOnComplete;
      _forceRepaintOnComplete = null;
      callback?.call();
      return;
    }
    _forceRepaintFrames--;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() {}); // Trigger a rebuild
      // Call JS force repaint on each frame
      _callJsForceRepaint();
      // Note: removed bgState?.forceRepaint call to avoid cascading timer loops
      _scheduleNextForceFrame();
    });
  }

  // Pending scroll offset to apply after layout - used for atomic zoom+scroll
  double? _pendingScrollOffset;

  void _zoomWithPreservedPosition(double factor, {double? focalViewportX}) {
    // Guard against concurrent zoom operations (prevents race conditions)
    if (_zoomInProgress) {
      return;
    }
    _zoomInProgress = true;

    try {
      // Capture ALL state needed for zoom calculations SYNCHRONOUSLY
      // before any async operations, setState, or callbacks.
      final oldZoom = _zoomLevel;
      final currentScrollOffset = _trackedScrollOffset;

      // Determine the new zoom level (clamped)
      final newZoom = (oldZoom * factor).clamp(1.0, 100000.0);
      final scale = newZoom / oldZoom;

      // Get the viewport width from the last known actual width
      final viewportWidth = _lastActualWidth ?? 800.0;

      // Compute max scroll extents using the correct formula:
      // maxScrollExtent = viewportWidth * (zoomLevel - 1)
      // This is because content width = viewportWidth * zoomLevel
      // and maxScroll = contentWidth - viewportWidth
      final oldMaxExtent = viewportWidth * (oldZoom - 1.0);
      final newMaxExtent = viewportWidth * (newZoom - 1.0);

      double targetScrollOffset;

      if (focalViewportX != null) {
        // Focal point zoom: keep the same content position under the cursor
        //
        // oldContentX = currentScrollOffset + focalViewportX
        // After zoom, this content position scales: newContentX =
        //                                                  oldContentX * scale
        // To keep this under the same viewport position:
        // newScrollOffset = newContentX - focalViewportX
        //                 = (currentScrollOffset + focalViewportX) *
        //                   scale - focalViewportX
        //                 = currentScrollOffset * scale + focalViewportX *
        //                   (scale - 1)
        final oldContentX = currentScrollOffset + focalViewportX;
        final newContentX = oldContentX * scale;
        targetScrollOffset = (newContentX - focalViewportX).clamp(
          0.0,
          newMaxExtent,
        );
      } else {
        // No focal point: preserve scroll fraction
        final scrollFraction =
            oldMaxExtent > 0 ? currentScrollOffset / oldMaxExtent : 0.0;
        targetScrollOffset = (scrollFraction * newMaxExtent).clamp(
          0.0,
          newMaxExtent,
        );
      }

      // Store the pending scroll offset - will be applied in build()
      // after layout.
      // This ensures the scroll position is set BEFORE painters run
      _pendingScrollOffset = targetScrollOffset;
      _trackedScrollOffset = targetScrollOffset;

      // Update zoom level - triggers rebuild where we'll apply the scroll
      setState(() {
        _zoomLevel = newZoom;
      });

      // After layout, finalize and force repaint for webviews
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _finalizeZoomScroll(targetScrollOffset, newMaxExtent);
      });
    } on Object catch (_) {
      _zoomInProgress = false;
      rethrow;
    }
  }

  /// Finalize scroll position after zoom layout settles.
  /// This corrects any minor discrepancy from our pre-layout estimate.
  void _finalizeZoomScroll(double targetOffset, double estimatedMaxExtent) {
    if (!_horizontalScrollController.hasClients) {
      _zoomInProgress = false;
      return;
    }

    final actualMaxExtent =
        _horizontalScrollController.position.maxScrollExtent;

    // Determine the final scroll position
    double finalOffset;
    if ((actualMaxExtent - estimatedMaxExtent).abs() < 1.0) {
      // Estimate was good, just clamp to actual extent
      finalOffset = targetOffset.clamp(0.0, actualMaxExtent);
    } else {
      // Estimate was off - recompute proportionally
      finalOffset = estimatedMaxExtent > 0
          ? (targetOffset * actualMaxExtent / estimatedMaxExtent).clamp(
              0.0,
              actualMaxExtent,
            )
          : 0.0;
    }

    // Apply scroll position if needed
    final currentOffset = _horizontalScrollController.offset;
    if ((finalOffset - currentOffset).abs() > 0.5) {
      _trackedScrollOffset = finalOffset;
      _horizontalScrollController.jumpTo(finalOffset);
      // Immediately nudge the JS compositor after applying the pan
      _callJsForceRepaint();
    }

    // Force repaint for embedded webviews.
    // Keep _zoomInProgress true until the frame completes to prevent
    // the scroll listener from interfering during the repaint frame.
    // With direct paint (no raster cache), a single frame is sufficient —
    // the previous 3-frame cascade existed to stagger toImageSync cache
    // rebuilds, which no longer exist.
    _forceMultipleFrameUpdates(1, () {
      _zoomInProgress = false;
      // After zoom is fully settled, sync the scrollbar controller.
      // At this point both scroll views have the new zoomedWidth.
      _syncPrimaryToScrollbar();
      _publishViewport();
    });
  }

  void _restoreScrollFraction(double scrollFraction, {int retries = 10}) {
    if (_horizontalScrollController.hasClients) {
      final newMaxExtent = _horizontalScrollController.position.maxScrollExtent;
      final newOffset = (scrollFraction * newMaxExtent).clamp(
        0.0,
        newMaxExtent,
      );
      // Silent restore
      if (newMaxExtent > 0 || retries <= 0) {
        try {
          _horizontalScrollController.jumpTo(newOffset);
        } on Object catch (_) {
          // ignore
        }
      } else {
        // Wait a frame and retry (gives layout time to settle)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _restoreScrollFraction(scrollFraction, retries: retries - 1);
        });
      }
    } else if (retries > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _restoreScrollFraction(scrollFraction, retries: retries - 1);
      });
    }
  }

  void _panLeft() {
    final offset = _horizontalScrollController.offset;
    final screenWidth = _lastActualWidth ?? MediaQuery.of(context).size.width;
    final panStep = screenWidth * 0.1; // Pan 10% of screen width
    _horizontalScrollController.animateTo(
      (offset - panStep).clamp(
        0.0,
        _horizontalScrollController.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _panRight() {
    final offset = _horizontalScrollController.offset;
    final screenWidth = _lastActualWidth ?? MediaQuery.of(context).size.width;
    final panStep = screenWidth * 0.1;
    _horizontalScrollController.animateTo(
      (offset + panStep).clamp(
        0.0,
        _horizontalScrollController.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  /// Navigate to the next or previous data point across all focused signals.
  /// When multiple signals are focused, finds the nearest edge in the specified
  /// direction. Scrolls horizontally to center the data point and sets the
  /// marker to that time. Re-entrant calls are ignored to prevent hang when key
  /// is held down repeatedly.
  void _navigateToNextDataPoint({required bool isNext}) {
    // Keep the destination marker and viewport in sync across key repeats.
    if (_navigationInProgress) {
      return;
    }

    try {
      _navigationInProgress = true;

      final signalState = context.read<SignalBloc>().state;
      final focusedSignals = signalState.focusedSignals;

      if (focusedSignals.isEmpty) {
        _navigationInProgress = false;
        return;
      }

      // Use the last navigation target time if available (BLoC updates are
      // async), otherwise read from the current BLoC state
      final currentMarkerTime = _lastNavigationTargetTime ??
          context.read<WaveformModuleBloc>().state.timePs;

      // Find the nearest data point across all focused signals
      int? nearestTime;

      for (final signal in focusedSignals) {
        if (signal.data.isEmpty) {
          continue;
        }

        // Get the next or previous data point index from current marker time
        final index = isNext
            ? signal.getNextDataPointIndex(currentMarkerTime)
            : signal.getPreviousDataPointIndex(currentMarkerTime);

        if (index == -1) {
          continue; // No next/previous data point for this signal
        }

        final dataTime = signal.data[index].time;

        if (nearestTime == null) {
          nearestTime = dataTime;
        } else if (isNext) {
          // For next: find the smallest time that is still > currentMarkerTime
          if (dataTime < nearestTime) {
            nearestTime = dataTime;
          }
        } else {
          // For previous: find the largest time that is still <
          // currentMarkerTime
          if (dataTime > nearestTime) {
            nearestTime = dataTime;
          }
        }
      }

      if (nearestTime == null) {
        // When navigating right past the last data point, jump to end of
        // simulation so the user can see the final signal values there.
        if (isNext) {
          final rohdState = context.read<RohdModuleBloc>().state;
          final endTime = rohdState.moduleStructure.metadata.endTime;
          if (endTime > 0 && currentMarkerTime < endTime) {
            nearestTime = endTime;
          }
        }
        if (nearestTime == null) {
          _navigationInProgress = false;
          return; // No next/previous data point found
        }
      }

      // Track the target time locally since BLoC updates are async
      _lastNavigationTargetTime = nearestTime;

      // Move the viewport first so the marker never paints off-screen between
      // the cursor update and the scroll update.
      _scrollToCenterDataPoint(nearestTime);

      context.read<WaveformModuleBloc>().add(WaveformModuleOnTap(nearestTime));
      if (mounted) {
        _focusNode.requestFocus();
      }
    } on Object {
      // Ignore navigation errors so keyboard input remains responsive.
    } finally {
      _navigationInProgress = false;
    }
  }

  Future<void> _showTransitionSearchDialog() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _TransitionSearchDialog(
        initialCriterion: _searchCriterion,
        onCriterionChanged: (criterion) => _searchCriterion = criterion,
        onSearch: _searchFocusedSignals,
      ),
    );
  }

  void _toggleMeasurementMarker() {
    final notifier = widget._measurementMarkerNotifier;
    if (notifier == null) {
      return;
    }
    if (notifier.value != null) {
      notifier.value = null;
      return;
    }
    final primaryTime = context.read<WaveformModuleBloc>().state.timePs;
    if (primaryTime < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Place the primary marker first')),
      );
      return;
    }
    notifier.value = primaryTime;
  }

  void _searchFocusedSignals({required bool isNext, String? value}) {
    final focusedSignals = context.read<SignalBloc>().state.focusedSignals;
    if (focusedSignals.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select one or more monitored signals')),
      );
      return;
    }

    final currentMarkerTime = _lastNavigationTargetTime ??
        context.read<WaveformModuleBloc>().state.timePs;
    int? nearestTime;
    for (final signal in focusedSignals) {
      final index = isNext
          ? signal.getNextMatchingDataPointIndex(
              currentMarkerTime,
              criterion: _searchCriterion,
              value: value,
            )
          : signal.getPreviousMatchingDataPointIndex(
              currentMarkerTime,
              criterion: _searchCriterion,
              value: value,
            );
      if (index == -1) {
        continue;
      }

      final time = signal.data[index].time;
      if (nearestTime == null ||
          (isNext && time < nearestTime) ||
          (!isNext && time > nearestTime)) {
        nearestTime = time;
      }
    }

    if (nearestTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No matching transition found')),
      );
      return;
    }

    _lastNavigationTargetTime = nearestTime;
    _scrollToCenterDataPoint(nearestTime);
    context.read<WaveformModuleBloc>().add(WaveformModuleOnTap(nearestTime));
    _focusNode.requestFocus();
  }

  /// Scrolls horizontally to center a data point at the given time in the
  /// viewport.
  void _scrollToCenterDataPoint(int timePs) {
    if (!_horizontalScrollController.hasClients) {
      return;
    }

    // Get waveform parameters from RohdModuleBloc
    final rohdState = context.read<RohdModuleBloc>().state;
    final endTime = rohdState.moduleStructure.metadata.endTime;
    final timescale = endTime > 0 ? endTime : 20;

    // timescale and timePs used below

    // Use ABSOLUTE time mapping (same as cursor drawing and waveform painters):
    // contentX = leftOffset + (time / timescale) * drawingContentWidth
    // where drawingContentWidth = contentWidth - leftOffset - rightPadding
    //       contentWidth = screenWidth * zoomLevel
    //
    // To center the marker in the viewport:
    // viewportX = contentX - scrollOffset
    // We want viewportX = screenWidth / 2
    // Therefore: scrollOffset = contentX - screenWidth / 2

    // Use the actual viewport width from LayoutBuilder, not MediaQuery
    // MediaQuery includes the full screen, but the actual scrollable area may
    // be narrower
    final screenWidth = _lastActualWidth ?? MediaQuery.of(context).size.width;
    final contentWidth = screenWidth * _zoomLevel;
    const leftOffset = waveformLeftOffset;
    const rightPadding = waveformLeftOffset;
    final drawingContentWidth = contentWidth - leftOffset - rightPadding;

    // Calculate content X position using absolute mapping
    final contentX = leftOffset +
        (timePs.toDouble() / timescale.toDouble()) * drawingContentWidth;

    // Calculate scroll offset to center the marker at screenWidth / 2
    final desiredScrollOffset = contentX - (screenWidth / 2.0);

    final maxScrollExtent =
        _horizontalScrollController.position.maxScrollExtent;
    final clampedOffset = desiredScrollOffset.clamp(0.0, maxScrollExtent);

    _trackedScrollOffset = clampedOffset;
    _horizontalScrollController.jumpTo(clampedOffset);
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      _pressedKeys.add(event.logicalKey);
    } else if (event is KeyUpEvent) {
      _pressedKeys.remove(event.logicalKey);
      return; // nothing else to do on key-up
    }

    // Process actions on both KeyDownEvent and KeyRepeatEvent so that
    // holding a key produces continuous scrolling / zooming.
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      // Check if Shift is pressed for zoom operations
      final shiftPressed =
          _pressedKeys.contains(LogicalKeyboardKey.shiftLeft) ||
              _pressedKeys.contains(LogicalKeyboardKey.shiftRight);

      // Check if any signals are focused for data-point navigation
      final signalState = context.read<SignalBloc>().state;
      final hasFocused = signalState.hasFocusedSignals;

      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        if (hasFocused) {
          _navigateToNextDataPoint(isNext: false);
        } else {
          _panLeft();
        }
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        if (hasFocused) {
          _navigateToNextDataPoint(isNext: true);
        } else {
          _panRight();
        }
      } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        if (shiftPressed) {
          // Shift+Up = zoom in
          _zoomIn();
        } else {
          // Up = scroll up
          _scrollUp();
        }
      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        if (shiftPressed) {
          // Shift+Down = zoom out
          _zoomOut();
        } else {
          // Down = scroll down
          _scrollDown();
        }
      } else if (event.logicalKey == LogicalKeyboardKey.delete) {
        // DEL key: remove all focused signals from the monitor list
        if (hasFocused) {
          for (final waveform in signalState.focusedSignals) {
            context.read<SignalBloc>().add(SignalRemoveEvent(waveform));
          }
        }
      }
      // 'F' key fit-to-viewport is handled by the global key handler
      // in home.dart so it works regardless of which panel has focus.
    }
  }

  void _scrollUp() {
    try {
      if (_verticalScrollController.hasClients) {
        final scrollStep = context.read<WaveformScaleCubit>().scaledRowHeight;
        final offset = _verticalScrollController.offset;
        final maxExtent = _verticalScrollController.position.maxScrollExtent;
        final newOffset = (offset - scrollStep).clamp(0.0, maxExtent);
        _verticalScrollController.jumpTo(newOffset);
        // Re-assert focus after the frame settles so that deferred
        // scroll-activity callbacks from synced ClampingScrollPhysics
        // panels on Linux/GTK can't steal it.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_focusNode.hasFocus) {
            _focusNode.requestFocus();
          }
        });
      }
    } on Object catch (_) {
      // ignore errors silently in scrollUp
    }
  }

  void _scrollDown() {
    try {
      if (_verticalScrollController.hasClients) {
        final scrollStep = context.read<WaveformScaleCubit>().scaledRowHeight;
        final offset = _verticalScrollController.offset;
        final maxExtent = _verticalScrollController.position.maxScrollExtent;
        final newOffset = (offset + scrollStep).clamp(0.0, maxExtent);
        _verticalScrollController.jumpTo(newOffset);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_focusNode.hasFocus) {
            _focusNode.requestFocus();
          }
        });
      }
    } on Object catch (_) {
      // ignore errors silently in scrollDown
    }
  }

  void _handleScroll(PointerSignalEvent event, BuildContext context) {
    if (event is PointerScrollEvent) {
      // Modifier-based dispatch:
      //   Shift+wheel → zoom in/out (focal point at cursor)
      //   plain wheel → horizontal pan
      // NOTE: Ctrl+wheel is intercepted by the browser (native page zoom)
      // before Flutter receives the event, so we use Shift instead.
      final shiftPressed = _isShiftPressed();

      final scrollDelta = event.scrollDelta.dy;

      // Determine mouse position relative to viewport (used for zoom focal
      // point)
      final box = context.findRenderObject()! as RenderBox;
      final local = box.globalToLocal(event.position);
      final focalX = local.dx; // viewport-local X

      if (shiftPressed) {
        // Shift+wheel = zoom in/out centered on cursor.
        // 1.5× factor for snappy, responsive zoom per wheel notch.
        const zoomFactor = 1.5;
        if (scrollDelta > 0) {
          _zoomWithPreservedPosition(1.0 / zoomFactor, focalViewportX: focalX);
        } else if (scrollDelta < 0) {
          _zoomWithPreservedPosition(zoomFactor, focalViewportX: focalX);
        }
      } else {
        // Plain wheel → horizontal pan. Use a pan fraction so
        // the amount is intuitive regardless of viewport size.
        try {
          if (!_horizontalScrollController.hasClients) {
            return;
          }
          final viewportWidth = _lastActualWidth ?? box.size.width;
          // Pan by 10% of viewport width per wheel notch; direction: up -> left
          final panStep = viewportWidth * 0.10;
          final currentOffset = _horizontalScrollController.offset;
          final maxExtent =
              _horizontalScrollController.position.maxScrollExtent;

          // PointerScrollEvent dy is typically positive when scrolling down
          final scrollDown = scrollDelta > 0;
          final newOffset = (currentOffset + (scrollDown ? panStep : -panStep))
              .clamp(0.0, maxExtent);
          _horizontalScrollController.jumpTo(newOffset);
          // Update tracked offset as well
          _trackedScrollOffset = newOffset;
        } on Object catch (_) {
          // ignore
        }
      }

      // Dismiss the hover tooltip during scroll so it doesn't cover
      // content or trigger unnecessary rebuilds of the tooltip subtree.
      if (_hoverTooltipNotifier.value != null) {
        _hoverTooltipNotifier.value = null;
      }
    }
  }

  /// Returns true if either Shift key is currently pressed according to
  /// the platform keyboard state. This is more reliable for pointer event
  /// handling than local KeyDown/KeyUp tracking which can miss events.
  bool _isShiftPressed() {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final rawHas = keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
    if (rawHas) {
      return true;
    }

    // Fallback: consult JS tracker if available (useful inside VS Code WebView
    // where modifier key events may sometimes be intercepted by the host).
    try {
      return plat.isShiftDownFromJs();
    } on Object catch (_) {
      return false;
    }
  }

  /// Returns true if either Control key is currently pressed.
  bool _isControlPressed() {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final rawHas = keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight);
    if (rawHas) {
      return true;
    }

    // Fallback: consult JS tracker if available (useful inside VS Code WebView
    // where modifier key events may sometimes be intercepted by the host).
    try {
      return plat.isControlDownFromJs();
    } on Object catch (_) {
      return false;
    }
  }

  bool _isAltPressed() {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.altLeft) ||
        keys.contains(LogicalKeyboardKey.altRight);
  }

  /// Handle mouse down for zoom-to-region: record the start time.
  /// Only active when Control is pressed and Shift is NOT pressed.
  /// [globalPosition] is the global screen position from the gesture.
  void _onZoomRegionMouseDown(Offset globalPosition) {
    if (!_isControlPressed()) {
      return; // Only active with Control key
    }
    if (!_horizontalScrollController.hasClients) {
      return; // Ensure scroll controller is ready
    }
    if (_isShiftPressed()) {
      return; // Skip if Shift is pressed
    }

    // The GestureDetector is now a viewport-sized overlay (outside the
    // SingleChildScrollView), so globalToLocal gives viewport coordinates.
    // Add scroll offset to convert to content coordinates.
    final box =
        _gestureDetectorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }

    final localPos = box.globalToLocal(globalPosition);
    final scrollOffset = _horizontalScrollController.hasClients
        ? _horizontalScrollController.offset
        : _trackedScrollOffset;
    final contentX = localPos.dx + scrollOffset;

    final viewportWidth = _lastActualWidth ?? 800.0;

    final timeAtClick = _contentXToTime(
      contentX,
      _currentTimescale.toDouble(),
      viewportWidth,
      _zoomLevel,
    );

    _zoomRegionStartTime = timeAtClick;
    _zoomRegionEndTime = timeAtClick;
    _isSelectingZoomRegion = true;

    _zoomRegionNotifier.value = (
      startTime: timeAtClick,
      endTime: timeAtClick,
      isSelecting: true,
    );
  }

  /// Handle mouse drag for zoom-to-region: update the end time to show the
  /// selection overlay. Only active when Control is pressed and Shift is NOT
  /// pressed. Throttled to reduce setState calls and improve performance.
  /// [globalPosition] is the global screen position from the gesture.
  void _onZoomRegionMouseDrag(Offset globalPosition) {
    if (!_isControlPressed()) {
      return; // Only active with Control key
    }
    if (!_horizontalScrollController.hasClients) {
      return; // Ensure scroll controller is ready
    }
    if (_isShiftPressed()) {
      return; // Skip if Shift is pressed
    }
    if (!_isSelectingZoomRegion || _zoomRegionStartTime == null) {
      return;
    }

    // Throttle updates to max 60fps (16ms between updates)
    final now = DateTime.now();
    if (_lastZoomRegionUpdate != null &&
        now.difference(_lastZoomRegionUpdate!).inMilliseconds < 16) {
      return;
    }
    _lastZoomRegionUpdate = now;

    // Viewport-space → content-space conversion (same as mouseDown).
    final box =
        _gestureDetectorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }

    final localPos = box.globalToLocal(globalPosition);
    final scrollOffset = _horizontalScrollController.hasClients
        ? _horizontalScrollController.offset
        : _trackedScrollOffset;
    final contentX = localPos.dx + scrollOffset;

    final viewportWidth = _lastActualWidth ?? 800.0;

    final timeAtDrag = _contentXToTime(
      contentX,
      _currentTimescale.toDouble(),
      viewportWidth,
      _zoomLevel,
    );

    _zoomRegionEndTime = timeAtDrag;

    _zoomRegionNotifier.value = (
      startTime: _zoomRegionStartTime,
      endTime: timeAtDrag,
      isSelecting: _isSelectingZoomRegion,
    );
  }

  /// Handle mouse up for zoom-to-region: finalize the region and zoom. Called
  /// when the pan gesture ends. We use _isSelectingZoomRegion to determine if a
  /// zoom selection was in progress, rather than checking Control key state
  /// (which may not be reliably tracked in embedded WebViews).
  void _onZoomRegionMouseUp() {
    // Don't check _isControlPressed() here - in embedded WebViews the key state
    // may not be reliably tracked when the gesture ends. Instead, rely on
    // _isSelectingZoomRegion which was set when the gesture started.

    // Reset throttle timer
    _lastZoomRegionUpdate = null;

    if (!_isSelectingZoomRegion ||
        _zoomRegionStartTime == null ||
        _zoomRegionEndTime == null) {
      _isSelectingZoomRegion = false;
      _zoomRegionStartTime = null;
      _zoomRegionEndTime = null;

      _zoomRegionNotifier.value = (
        startTime: null,
        endTime: null,
        isSelecting: false,
      );
      return;
    }

    final start = _zoomRegionStartTime!;
    final end = _zoomRegionEndTime!;

    // Determine drag direction for zoom in/out
    // Dragging forward (start < end): zoom in
    // Dragging backward (end < start): zoom out
    final isDraggingForward = end >= start;

    // Normalize so minTime < maxTime
    final minTime = start < end ? start : end;
    final maxTime = start < end ? end : start;
    final regionSize = maxTime - minTime;
    // Require a minimum drag distance to avoid accidental tiny zooms
    if (regionSize < 10) {
      _isSelectingZoomRegion = false;
      _zoomRegionStartTime = null;
      _zoomRegionEndTime = null;

      _zoomRegionNotifier.value = (
        startTime: null,
        endTime: null,
        isSelecting: false,
      );
      return;
    }

    // Calculate zoom factor: we want regionSize to fit in the viewport
    final viewportWidth = _lastActualWidth ?? 800.0;

    // Use _currentTimescale which is set during build with proper fallback
    final timescale = _currentTimescale;

    if (timescale <= 0 || regionSize <= 0) {
      _isSelectingZoomRegion = false;
      _zoomRegionStartTime = null;
      _zoomRegionEndTime = null;

      _zoomRegionNotifier.value = (
        startTime: null,
        endTime: null,
        isSelecting: false,
      );
      return;
    }

    // Calculate zoom change
    double newZoom;
    int focusTime; // The time to keep centered/visible

    // Maximum zoom level - same as used in _zoomWithPreservedPosition
    const maxZoom = 100000.0;

    if (isDraggingForward) {
      // Zoom IN: make regionSize fit in viewport (timescale / regionSize)
      newZoom = (timescale / regionSize).clamp(1.0, maxZoom);
      focusTime = minTime; // Focus on the start of the selected region
    } else {
      // Zoom OUT: use viewport pixel distance in CURRENT zoomed view
      final pxPerTimeInCurrentView = (viewportWidth * _zoomLevel) / timescale;
      final dragDistanceInCurrentView = regionSize * pxPerTimeInCurrentView;

      // dragFraction = what fraction of viewport was dragged
      final dragFraction = dragDistanceInCurrentView / viewportWidth;

      // Zoom out by the reciprocal of the drag fraction
      // If dragFraction = 0.25 (1/4 of view), newZoom = currentZoom * 0.25
      newZoom = (_zoomLevel * dragFraction).clamp(1.0, maxZoom);
      focusTime = start; // Focus on where the drag started
    }

    // Calculate the target scroll offset BEFORE setState, using the new zoom
    // level This ensures we use the correct geometry even before layout settles
    final targetScrollOffset = _scrollOffsetForTime(
      focusTime,
      timescale.toDouble(),
      viewportWidth,
      newZoom,
    );

    // Estimate max scroll extent with new zoom
    final newMaxExtent = viewportWidth * (newZoom - 1.0);
    final clampedOffset = targetScrollOffset.clamp(0.0, newMaxExtent);

    // Store pending scroll offset to apply after layout
    _pendingScrollOffset = clampedOffset;
    _trackedScrollOffset = clampedOffset;

    // Clear zoom region state
    _isSelectingZoomRegion = false;
    _zoomRegionStartTime = null;
    _zoomRegionEndTime = null;

    _zoomRegionNotifier.value = (
      startTime: null,
      endTime: null,
      isSelecting: false,
    );

    setState(() {
      _zoomLevel = newZoom;
    });

    // After layout, apply the scroll position
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _finalizeZoomScroll(clampedOffset, newMaxExtent);
    });

    _callJsForceRepaint();
  }

  /// Commit the current drag-reorder by emitting a [SignalReorderEvent].
  void _commitDrag(BuildContext context) {
    final result = widget._dragController?.endDrag();
    if (result != null) {
      if (result.groupOldIndices != null) {
        context.read<SignalBloc>().add(
              SignalGroupReorderEvent(
                oldIndices: result.groupOldIndices!,
                anchorOldIndex: result.oldIndex,
                anchorNewIndex: result.newIndex,
              ),
            );
      } else {
        context.read<SignalBloc>().add(
              SignalReorderEvent(
                oldIndex: result.oldIndex,
                newIndex: result.newIndex,
              ),
            );
      }
    }
  }

  // Custom scroll behavior that disables mouse wheel scrolling
  ScrollBehavior _buildCustomScrollBehavior(BuildContext context) =>
      _NoMouseWheelScrollBehavior();

  /// Calculate content X position from time using absolute time mapping.
  /// Formula: contentX = leftOffset + (time / timescale) * drawingContentWidth
  /// where drawingContentWidth = contentWidth - leftOffset - rightPadding
  ///       contentWidth = viewportWidth * zoomLevel
  double _timeToContentX(
    int time,
    double timescale,
    double viewportWidth,
    double zoomLevel,
  ) {
    const leftOffset = waveformLeftOffset;
    const rightPadding = waveformLeftOffset;
    final contentWidth = viewportWidth * zoomLevel;
    final drawingContentWidth = contentWidth - leftOffset - rightPadding;

    if (drawingContentWidth <= 0 || timescale <= 0) {
      return leftOffset;
    }

    return leftOffset + (time / timescale) * drawingContentWidth;
  }

  /// Calculate time from content X position using inverse of absolute time
  /// mapping. Formula: time = ((contentX - leftOffset) / drawingContentWidth) *
  /// timescale
  int _contentXToTime(
    double contentX,
    double timescale,
    double viewportWidth,
    double zoomLevel,
  ) {
    const leftOffset = waveformLeftOffset;
    const rightPadding = waveformLeftOffset;
    final contentWidth = viewportWidth * zoomLevel;
    final drawingContentWidth = contentWidth - leftOffset - rightPadding;

    if (drawingContentWidth <= 0 || timescale <= 0) {
      return 0;
    }

    final rel = ((contentX - leftOffset) / drawingContentWidth).clamp(0.0, 1.0);
    return (rel * timescale).toInt();
  }

  /// Calculate scroll offset to show a specific time at the left edge of
  /// viewport.
  double _scrollOffsetForTime(
    int time,
    double timescale,
    double viewportWidth,
    double zoomLevel,
  ) {
    const leftOffset = waveformLeftOffset;
    final contentX = _timeToContentX(time, timescale, viewportWidth, zoomLevel);
    return (contentX - leftOffset).clamp(0.0, double.infinity);
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<RohdModuleBloc, RohdModuleState>(
        builder: (context, state) {
          final endTime = state.moduleStructure.metadata.endTime;
          final timescale = endTime > 0 ? endTime : 20;
          _currentTimescale = timescale;

          // Extract dataEndTime from WaveformUpdated states.
          final dataEndTime =
              state is WaveformUpdated ? state.dataEndTime : null;

          return MultiBlocListener(
            listeners: [
              BlocListener<WaveformModuleBloc, WaveformModuleState>(
                listenWhen: (prev, curr) => curr.timePs != prev.timePs,
                listener: (context, wfState) {
                  if (_lastNavigationTargetTime != null &&
                      wfState.timePs != _lastNavigationTargetTime) {
                    _lastNavigationTargetTime = null;
                  }
                },
              ),
              BlocListener<SignalBloc, SignalState>(
                listenWhen: (previous, current) => !setEquals(
                  previous.focusedSignalIds,
                  current.focusedSignalIds,
                ),
                listener: (context, state) {
                  _lastNavigationTargetTime = null;
                  _focusNode.requestFocus();
                },
              ),
            ],
            child: KeyboardListener(
              focusNode: _focusNode,
              autofocus: true,
              onKeyEvent: _handleKeyEvent,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final actualWidth = constraints.maxWidth;
                  final zoomedWidth = actualWidth * _zoomLevel;

                  _trackWidthChange(actualWidth);
                  _applyPendingScroll(
                    zoomedWidth: zoomedWidth,
                    actualWidth: actualWidth,
                  );

                  return _buildWaveformBody(
                    context,
                    actualWidth: actualWidth,
                    zoomedWidth: zoomedWidth,
                    timescale: timescale,
                    endTime: endTime,
                    dataEndTime: dataEndTime,
                  );
                },
              ),
            ),
          );
        },
      );

  /// Detect viewport width changes (window resize) and schedule scroll
  /// fraction restoration so the same content stays visible.
  void _trackWidthChange(double actualWidth) {
    if (_lastActualWidth == null) {
      _lastActualWidth = actualWidth;
    } else if (_lastActualWidth != actualWidth) {
      final oldActual = _lastActualWidth!;
      final oldZoomedWidth = oldActual * _zoomLevel;
      final oldMaxScrollExtent = (oldZoomedWidth - oldActual).clamp(
        0.0,
        double.infinity,
      );
      final scrollFraction =
          (oldMaxScrollExtent > 0 && _horizontalScrollController.hasClients)
              ? (_horizontalScrollController.offset / oldMaxScrollExtent)
              : 0.0;
      _lastActualWidth = actualWidth;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _restoreScrollFraction(scrollFraction);
      });
    }
  }

  /// Apply a pending scroll offset from a zoom operation. Called during
  /// build so the scroll position is correct before painters run.
  void _applyPendingScroll({
    required double zoomedWidth,
    required double actualWidth,
  }) {
    if (_pendingScrollOffset == null ||
        !_horizontalScrollController.hasClients) {
      return;
    }
    final pending = _pendingScrollOffset!;
    _pendingScrollOffset = null;

    final position = _horizontalScrollController.position;
    final maxExtent = (zoomedWidth - actualWidth).clamp(0.0, double.infinity);
    final clampedOffset = pending.clamp(0.0, maxExtent);
    position.correctPixels(clampedOffset);
    _trackedScrollOffset = clampedOffset;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _callJsForceRepaint();
    });
  }

  /// Main waveform body: timescale header + layered waveform/gesture/scroll
  /// content with zoom overlay.
  Widget _buildWaveformBody(
    BuildContext context, {
    required double actualWidth,
    required double zoomedWidth,
    required int timescale,
    required int endTime,
    int? dataEndTime,
  }) {
    final waveformColors = WaveformColors.of(context);

    return ColoredBox(
      color: waveformColors.background,
      child: Column(
        children: [
          _buildTimescaleHeader(
            actualWidth: actualWidth,
            timescale: timescale,
            waveformColors: waveformColors,
            endTime: endTime,
          ),
          Expanded(
            child: ClipRect(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Truncate viewport height to a whole number of signal
                  // rows so that maxScrollExtent matches the Selected
                  // Signals and Value panels exactly.  Without this the
                  // raw Expanded height can be up to 29 px taller,
                  // giving the waveform a smaller maxScrollExtent and
                  // causing scroll-sync drift on platforms (like Linux)
                  // where window chrome leaves a non-zero remainder.
                  //
                  // Reserve 12px at the bottom for the horizontal scrollbar
                  // strip so it hugs the window edge regardless of row
                  // truncation remainder.
                  const scrollbarHeight = 12.0;
                  final available = constraints.maxHeight - scrollbarHeight;
                  final rh =
                      context.watch<WaveformScaleCubit>().scaledRowHeight;
                  final fullRows = (available / rh).floor();
                  final effectiveHeight = fullRows * rh;
                  return Column(
                    children: [
                      SizedBox(
                        height: effectiveHeight,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Stack(
                              children: [
                                _buildWaveformContentLayer(
                                  context,
                                  actualWidth: actualWidth,
                                  zoomedWidth: zoomedWidth,
                                  timescale: timescale,
                                  dataEndTime: dataEndTime,
                                ),
                                _buildGestureOverlay(
                                  context,
                                  actualWidth: actualWidth,
                                  timescale: timescale,
                                ),
                              ],
                            ),
                            _buildZoomOverlay(
                              actualWidth: actualWidth,
                              timescale: timescale,
                            ),
                            _buildMeasurementMarkerOverlay(
                              actualWidth: actualWidth,
                              timescale: timescale,
                            ),
                            _buildHoverTooltip(context),
                          ],
                        ),
                      ),
                      // Fill any remainder from row truncation, then the
                      // scrollbar strip at the very bottom.
                      const Spacer(),
                      SizedBox(
                        height: scrollbarHeight,
                        child: _buildScrollbarStripInline(
                          context,
                          zoomedWidth: zoomedWidth,
                        ),
                      ),
                    ],
                  );
                },
              ), // LayoutBuilder
            ), // ClipRect
          ), // Expanded
        ],
      ),
    );
  }

  /// Fixed timescale header that rebuilds in sync with horizontal scroll.
  /// Includes a cursor time label drawn at the bottom of the header.
  Widget _buildTimescaleHeader({
    required double actualWidth,
    required int timescale,
    required WaveformColors waveformColors,
    required int endTime,
  }) =>
      SizedBox(
        height: 38,
        width: actualWidth,
        child: AnimatedBuilder(
          animation: _horizontalScrollController,
          builder: (context, _) {
            final scrollOffset = _horizontalScrollController.hasClients
                ? _horizontalScrollController.offset
                : _trackedScrollOffset;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: widget._isVideoMode
                  ? null
                  : (details) {
                      final contentX = details.localPosition.dx + scrollOffset;
                      final timeAtTap = _contentXToTime(
                        contentX,
                        timescale.toDouble(),
                        actualWidth,
                        _zoomLevel,
                      );
                      context.read<WaveformModuleBloc>().add(
                            WaveformModuleOnTap(timeAtTap),
                          );
                    },
              child: Stack(
                children: [
                  TimescaleWidget(
                    zoomLevel: _zoomLevel,
                    finalTime: timescale.toDouble(),
                    viewportWidth: actualWidth,
                    scrollOffset: scrollOffset,
                    lineColor: waveformColors.timescale,
                    backgroundColor: waveformColors.timescaleBackground,
                  ),
                  if (widget._measurementMarkerNotifier != null)
                    Positioned(
                      top: 2,
                      right: 38,
                      child: ValueListenableBuilder<int?>(
                        valueListenable: widget._measurementMarkerNotifier!,
                        builder: (context, measurementTime, _) => IconButton(
                          constraints: const BoxConstraints.tightFor(
                            width: 34,
                            height: 34,
                          ),
                          padding: EdgeInsets.zero,
                          iconSize: 18,
                          icon: Icon(
                            measurementTime == null
                                ? Icons.straighten
                                : Icons.close,
                          ),
                          tooltip: measurementTime == null
                              ? 'Set measurement marker at primary cursor'
                              : 'Clear measurement marker',
                          onPressed: _toggleMeasurementMarker,
                        ),
                      ),
                    ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: IconButton(
                      constraints: const BoxConstraints.tightFor(
                        width: 34,
                        height: 34,
                      ),
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      icon: const Icon(Icons.search),
                      tooltip: 'Find value or edge in focused signals',
                      onPressed: _showTransitionSearchDialog,
                    ),
                  ),
                  // Cursor time label at the bottom of the timescale header
                  if (endTime > 0)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: BlocBuilder<WaveformModuleBloc,
                            WaveformModuleState>(
                          buildWhen: (prev, curr) => prev.timePs != curr.timePs,
                          builder: (context, wfState) {
                            final t = wfState.timePs;
                            if (t < 0 || timescale <= 0) {
                              return const SizedBox.shrink();
                            }
                            // Use the SAME coordinate math as
                            // _LiveCursorPainter
                            const leftOff = waveformLeftOffset;
                            const rightPad = waveformLeftOffset;
                            final contentWidth = actualWidth * _zoomLevel;
                            final drawingW = contentWidth - leftOff - rightPad;
                            if (drawingW <= 0) {
                              return const SizedBox.shrink();
                            }

                            final cursorContentX = leftOff +
                                (t.toDouble() / timescale.toDouble()) *
                                    drawingW;
                            final cursorViewportX =
                                cursorContentX - scrollOffset;

                            if (cursorViewportX < 0 ||
                                cursorViewportX > actualWidth) {
                              return const SizedBox.shrink();
                            }

                            final label = formatCursorTimeLabel(t);

                            return CustomPaint(
                              painter: _CursorTimeLabelPainter(
                                label: label,
                                cursorViewportX: cursorViewportX,
                                viewportWidth: actualWidth,
                                labelColor: waveformColors.cursor,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      );

  /// Layer 1: Waveform content (visual only, no hitTest).
  /// IgnorePointer blocks ALL hit-testing into the waveform subtree,
  /// eliminating the O(N) hitTest traversal.
  Widget _buildWaveformContentLayer(
    BuildContext context, {
    required double actualWidth,
    required double zoomedWidth,
    required int timescale,
    int? dataEndTime,
  }) =>
      IgnorePointer(
        child: ScrollConfiguration(
          behavior: _buildCustomScrollBehavior(context),
          child: SingleChildScrollView(
            key: const ValueKey('waveform-horizontal-scroll-view'),
            controller: _horizontalScrollController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: zoomedWidth,
              child: AnimatedBuilder(
                animation: _horizontalScrollController,
                builder: (context, child) {
                  final scrollOff = _horizontalScrollController.hasClients
                      ? _horizontalScrollController.offset
                      : _trackedScrollOffset;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: scrollOff,
                        top: 0,
                        bottom: 0,
                        width: actualWidth,
                        child: child!,
                      ),
                    ],
                  );
                },
                child: WaveformBackground(
                  key: _backgroundKey,
                  valueFont: widget.valueFont,
                  timescale: timescale,
                  dataEndTime: dataEndTime,
                  verticalScrollController: _verticalScrollController,
                  zoomLevel: _zoomLevel,
                  horizontalScrollController: _horizontalScrollController,
                  screenWidth: actualWidth,
                  dragController: widget._dragController,
                  isVideoMode: widget._isVideoMode,
                ),
              ),
            ),
          ),
        ),
      );

  /// A flat Positioned overlay that handles pointer interaction EXCEPT for
  /// the scrollbar area at the bottom. hitTest is O(1).
  Widget _buildGestureOverlay(
    BuildContext context, {
    required double actualWidth,
    required int timescale,
  }) =>
      Positioned(
        left: 0,
        right: 0,
        top: 0,
        bottom: 12,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerSignal: (event) {
            _handleScroll(event, context);
          },
          child: MouseRegion(
            onHover: (event) {
              _updateHoverTooltip(
                event.localPosition,
                timescale: timescale,
                actualWidth: actualWidth,
                context: context,
              );
            },
            onExit: (_) {
              if (_hoverTooltipNotifier.value != null) {
                _hoverTooltipNotifier.value = null;
              }
            },
            child: GestureDetector(
              key: _gestureDetectorKey,
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                _focusNode.requestFocus();
                // Clear stale navigation target so next arrow key starts from
                // this tap position
                _lastNavigationTargetTime = null;
                if (!widget._isVideoMode && !_isControlPressed()) {
                  final scrollOffset = _horizontalScrollController.hasClients
                      ? _horizontalScrollController.offset
                      : 0.0;
                  final contentX = details.localPosition.dx + scrollOffset;
                  final timeAtTap = _contentXToTime(
                    contentX,
                    timescale.toDouble(),
                    actualWidth,
                    _zoomLevel,
                  );
                  if (_isAltPressed()) {
                    widget._measurementMarkerNotifier?.value = timeAtTap;
                  } else {
                    context.read<WaveformModuleBloc>().add(
                          WaveformModuleOnTap(timeAtTap),
                        );
                  }
                }
              },
              onPanStart: (details) {
                _focusNode.requestFocus();
                if (_isControlPressed() && !_isShiftPressed()) {
                  _onZoomRegionMouseDown(details.globalPosition);
                } else if (!_isControlPressed()) {
                  // Drag-reorder: determine which row the pointer is on.
                  final scrollOffsetV = _verticalScrollController.hasClients
                      ? _verticalScrollController.offset
                      : 0.0;
                  final localY = details.localPosition.dy + scrollOffsetV;
                  final rh = context.read<WaveformScaleCubit>().scaledRowHeight;
                  final rowIndex = (localY / rh).floor();
                  debugPrint(
                    '[WaveformDrag] onPanStart: '
                    'localPosition.dy='
                    '${details.localPosition.dy.toStringAsFixed(1)}, '
                    'scrollOffsetV=${scrollOffsetV.toStringAsFixed(1)}, '
                    'localY=${localY.toStringAsFixed(1)}, '
                    'rowIndex=$rowIndex, '
                    'rowHeight=$rh',
                  );
                  final signalState = context.read<SignalBloc>().state;
                  if (signalState is SignalLoaded) {
                    final count = signalState.monitorSignalsList.length;
                    final previewNames = signalState.monitorSignalsList
                        .take(5)
                        .map((s) => s.signalId)
                        .join(', ');
                    debugPrint(
                      '[WaveformDrag] signalCount=$count, '
                      'names=[$previewNames...]',
                    );
                    if (rowIndex >= 0 && rowIndex < count) {
                      _isDragReorder = true;
                      List<int>? groupIndices;
                      final focused = signalState.focusedSignalIds;
                      final mList = signalState.monitorSignalsList;
                      if (focused.length > 1 &&
                          rowIndex < mList.length &&
                          focused.contains(mList[rowIndex].monitorId)) {
                        groupIndices = <int>[];
                        for (var i = 0; i < mList.length; i++) {
                          if (focused.contains(mList[i].monitorId)) {
                            groupIndices.add(i);
                          }
                        }
                      }
                      widget._dragController?.startDrag(
                        rowIndex,
                        count,
                        groupIndices: groupIndices,
                      );
                    } else {
                      debugPrint('[WaveformDrag] rowIndex OUT OF RANGE!');
                    }
                  }
                }
              },
              onPanUpdate: (details) {
                if (_isDragReorder) {
                  _autoScrollWhileDragging(details.globalPosition);
                  widget._dragController?.updateDrag(details.delta.dy);
                } else if (_isControlPressed() && !_isShiftPressed()) {
                  _onZoomRegionMouseDrag(details.globalPosition);
                }
              },
              onPanEnd: (details) {
                if (_isDragReorder) {
                  _isDragReorder = false;
                  _commitDrag(context);
                } else {
                  _onZoomRegionMouseUp();
                }
              },
              onPanCancel: () {
                if (_isDragReorder) {
                  _isDragReorder = false;
                  widget._dragController?.cancelDrag();
                } else {
                  _onZoomRegionMouseUp();
                }
              },
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );

  void _autoScrollWhileDragging(Offset globalPosition) {
    final ctrl = widget._dragController;
    if (ctrl == null || !ctrl.isDragging) {
      return;
    }
    if (!_verticalScrollController.hasClients) {
      return;
    }

    final box =
        _gestureDetectorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }

    final viewportY = box.globalToLocal(globalPosition).dy;
    final viewportH = box.size.height;

    var desiredDelta = 0.0;
    if (viewportY < _dragAutoScrollEdgePx) {
      desiredDelta = -_dragAutoScrollStepPx;
    } else if (viewportY > viewportH - _dragAutoScrollEdgePx) {
      desiredDelta = _dragAutoScrollStepPx;
    }
    if (desiredDelta == 0.0) {
      return;
    }

    final oldOffset = _verticalScrollController.offset;
    final newOffset = (oldOffset + desiredDelta).clamp(
      0.0,
      _verticalScrollController.position.maxScrollExtent,
    );
    final appliedDelta = newOffset - oldOffset;
    if (appliedDelta.abs() <= 0.01) {
      return;
    }

    _verticalScrollController.jumpTo(newOffset);
    ctrl.updateDrag(appliedDelta);
  }

  /// Computes the signal value under the pointer and shows a tooltip only
  /// when the label in that interval is clipped or fully hidden.
  ///
  /// Uses [_hoverTooltipNotifier] (ValueNotifier) so updates never call
  /// setState, avoiding interference with scroll performance.
  ///
  /// Throttled to fire at most once per [_hoverThrottleUs] (~60 ms) to
  /// avoid burning CPU on the 68 Hz mouse-move stream.
  void _updateHoverTooltip(
    Offset localPosition, {
    required int timescale,
    required double actualWidth,
    required BuildContext context,
  }) {
    // ── Throttle: skip if called within the throttle window ──
    final nowUs = DateTime.now().microsecondsSinceEpoch;
    if (nowUs - _lastHoverUpdateUs < _hoverThrottleUs) {
      return;
    }
    _lastHoverUpdateUs = nowUs;

    // ── Suppress tooltip while either scroll controller is active ──
    try {
      final hScrolling = _horizontalScrollController.hasClients &&
          _horizontalScrollController.position.isScrollingNotifier.value;
      final vScrolling = _verticalScrollController.hasClients &&
          _verticalScrollController.position.isScrollingNotifier.value;
      if (hScrolling || vScrolling) {
        if (_hoverTooltipNotifier.value != null) {
          _hoverTooltipNotifier.value = null;
        }
        return;
      }
    } on Object catch (_) {
      // position may not be attached yet; continue
    }

    final scrollOffsetH = _horizontalScrollController.hasClients
        ? _horizontalScrollController.offset
        : 0.0;
    final scrollOffsetV = _verticalScrollController.hasClients
        ? _verticalScrollController.offset
        : 0.0;

    final contentX = localPosition.dx + scrollOffsetH;
    final contentY = localPosition.dy + scrollOffsetV;

    final rowIndex =
        (contentY / context.read<WaveformScaleCubit>().scaledRowHeight).floor();
    final signalState = context.read<SignalBloc>().state;
    final signals = signalState.monitorSignalsList;

    if (rowIndex < 0 || rowIndex >= signals.length) {
      _hoverTooltipNotifier.value = null;
      return;
    }

    final signal = signals[rowIndex];
    if (signal.data.isEmpty) {
      _hoverTooltipNotifier.value = null;
      return;
    }

    final time = _contentXToTime(
      contentX,
      timescale.toDouble(),
      actualWidth,
      _zoomLevel,
    );

    final rawValue = signal.getValueByTime(time);
    if (rawValue.isEmpty) {
      _hoverTooltipNotifier.value = null;
      return;
    }

    // ── Check whether the label is clipped in this segment ──────────
    // Replicate the same metric the painters use:
    //   available = railWidth - 2 px padding
    //   railWidth = segmentWidth - 2 * halfConn  (ramp insets)
    // A label is clipped when the full-text TextPainter is wider than
    // `available`, or when `available < 10` (label skipped entirely).

    // Find the segment boundaries: the transition at/before `time` and
    // the next transition after it.
    final data = signal.data;
    var segStart = data.first.time;
    var segEnd = timescale; // default: extends to end
    // Binary search for the transition at or before `time`.
    var lo = 0;
    var hi = data.length - 1;
    var foundIdx = 0;
    while (lo <= hi) {
      final mid = lo + (hi - lo) ~/ 2;
      if (data[mid].time <= time) {
        foundIdx = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    segStart = data[foundIdx].time;
    if (foundIdx + 1 < data.length) {
      segEnd = data[foundIdx + 1].time;
    }

    // Pixel width of the segment using the same formula as the painters.
    const leftOff = waveformLeftOffset;
    const rightPad = waveformLeftOffset;
    final contentWidth = actualWidth * _zoomLevel;
    final drawingWidth = contentWidth - leftOff - rightPad;
    final pxPerTime =
        (timescale > 0 && drawingWidth > 0) ? drawingWidth / timescale : 0.0;
    final segPx = (segEnd - segStart) * pxPerTime;

    // Rail inset used by both hex and binary painters.
    const halfConn = 3; // connPx / 2
    final available = segPx - 2 * halfConn - 2.0; // 1 px pad each side

    // For single-bit signals the raw value is '0'/'1' — always fits.
    if (signal.width <= 1) {
      _hoverTooltipNotifier.value = null;
      return;
    }

    // Format the full label the same way the painters do.
    final formatted = wfp.Waveform.formatHexValue(
      rawValue,
      width: signal.width,
    );

    // Measure the full label using the painter cache (fontSize 12).
    final tp = wfp.Waveform.getCachedLabel(
      formatted,
      12,
      Colors.white,
      valueFont: widget.valueFont,
    ); // colour doesn't affect width
    final isClipped = available < 10.0 || tp.width > available;

    if (!isClipped) {
      _hoverTooltipNotifier.value = null;
      return;
    }

    _hoverTooltipNotifier.value = (text: formatted, position: localPosition);
  }

  /// Builds the positioned hover-tooltip overlay shown when the cursor
  /// is over a waveform interval whose label is clipped.
  ///
  /// Wrapped in [ValueListenableBuilder] so that hover moves update only
  /// this subtree — no setState, no scroll interference.
  Widget _buildHoverTooltip(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ValueListenableBuilder<({String text, Offset position})?>(
      valueListenable: _hoverTooltipNotifier,
      builder: (context, hover, _) {
        if (hover == null) {
          return const SizedBox.shrink();
        }

        // Position tooltip slightly below and to the right of the cursor.
        const offsetX = 12;
        const offsetY = 18;

        return Positioned(
          left: hover.position.dx + offsetX,
          top: hover.position.dy + offsetY,
          child: IgnorePointer(
            // This tooltip contains one value, so wheel input belongs to the
            // waveform canvas rather than the overlay.
            child: Material(
              key: const ValueKey('waveform-hover-tooltip'),
              elevation: 4,
              borderRadius: BorderRadius.circular(4),
              color: isDark ? const Color(0xFF2D2D30) : const Color(0xFFF5F5F5),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  hover.text,
                  style: wfp.Waveform.valueTextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white : Colors.black87,
                    valueFont: widget.valueFont,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Horizontal scrollbar strip widget (non-positioned, for use in Column).
  Widget _buildScrollbarStripInline(
    BuildContext context, {
    required double zoomedWidth,
  }) =>
      Theme(
        data: Theme.of(context).copyWith(
          scrollbarTheme: ScrollbarThemeData(
            thumbColor: WidgetStateProperty.all(Colors.white),
          ),
        ),
        child: Scrollbar(
          interactive: true,
          thumbVisibility: true,
          controller: _scrollbarController,
          child: SingleChildScrollView(
            controller: _scrollbarController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: zoomedWidth, height: 12),
          ),
        ),
      );

  /// Zoom-to-region selection overlay (paint-only, no widget rebuild).
  /// RepaintBoundary isolates dirty marks so only this layer is
  /// re-rasterized during drag; the waveform layer stays cached.
  Widget _buildZoomOverlay({
    required double actualWidth,
    required int timescale,
  }) =>
      Positioned.fill(
        child: RepaintBoundary(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _ZoomRegionPainter(
                zoomRegionNotifier: _zoomRegionNotifier,
                timeToViewportX: (time) {
                  final contentX = _timeToContentX(
                    time,
                    timescale.toDouble(),
                    actualWidth,
                    _zoomLevel,
                  );
                  final scrollOffset = _horizontalScrollController.hasClients
                      ? _horizontalScrollController.offset
                      : 0.0;
                  return contentX - scrollOffset;
                },
              ),
            ),
          ),
        ),
      );

  Widget _buildMeasurementMarkerOverlay({
    required double actualWidth,
    required int timescale,
  }) {
    final measurementNotifier = widget._measurementMarkerNotifier;
    if (measurementNotifier == null) {
      return const SizedBox.shrink();
    }
    return Positioned.fill(
      child: IgnorePointer(
        child: BlocBuilder<WaveformModuleBloc, WaveformModuleState>(
          buildWhen: (previous, current) => previous.timePs != current.timePs,
          builder: (context, primaryState) => AnimatedBuilder(
            animation: Listenable.merge([
              _horizontalScrollController,
              measurementNotifier,
            ]),
            builder: (context, _) => CustomPaint(
              painter: _MeasurementMarkerPainter(
                primaryTimePs: primaryState.timePs,
                measurementTimePs: measurementNotifier.value,
                scrollOffset: _horizontalScrollController.hasClients
                    ? _horizontalScrollController.offset
                    : _trackedScrollOffset,
                contentWidth: actualWidth * _zoomLevel,
                viewportWidth: actualWidth,
                timescale: timescale,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TransitionSearchDialog extends StatefulWidget {
  final WaveformSearchCriterion initialCriterion;
  final ValueChanged<WaveformSearchCriterion> onCriterionChanged;
  final void Function({required bool isNext, String? value}) onSearch;

  const _TransitionSearchDialog({
    required this.initialCriterion,
    required this.onCriterionChanged,
    required this.onSearch,
  });

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(
        EnumProperty<WaveformSearchCriterion>(
          'initialCriterion',
          initialCriterion,
        ),
      )
      ..add(
        ObjectFlagProperty<ValueChanged<WaveformSearchCriterion>>.has(
          'onCriterionChanged',
          onCriterionChanged,
        ),
      )
      ..add(
        ObjectFlagProperty<
            void Function({required bool isNext, String? value})>.has(
          'onSearch',
          onSearch,
        ),
      );
  }

  @override
  State<_TransitionSearchDialog> createState() =>
      _TransitionSearchDialogState();
}

class _TransitionSearchDialogState extends State<_TransitionSearchDialog> {
  late WaveformSearchCriterion _criterion = widget.initialCriterion;
  final _valueController = TextEditingController();

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  void _search({required bool isNext}) {
    Navigator.pop(context);
    widget.onSearch(isNext: isNext, value: _valueController.text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Find transition'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<WaveformSearchCriterion>(
              initialValue: _criterion,
              decoration: const InputDecoration(labelText: 'Match'),
              items: const [
                DropdownMenuItem(
                  value: WaveformSearchCriterion.value,
                  child: Text('Value'),
                ),
                DropdownMenuItem(
                  value: WaveformSearchCriterion.risingEdge,
                  child: Text('Rising edge'),
                ),
                DropdownMenuItem(
                  value: WaveformSearchCriterion.fallingEdge,
                  child: Text('Falling edge'),
                ),
              ],
              onChanged: (criterion) {
                if (criterion != null) {
                  setState(() => _criterion = criterion);
                  widget.onCriterionChanged(criterion);
                }
              },
            ),
            if (_criterion == WaveformSearchCriterion.value)
              TextField(
                controller: _valueController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Value'),
                onSubmitted: (_) => widget.onSearch(
                  isNext: true,
                  value: _valueController.text,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Find previous match',
            onPressed: () => _search(isNext: false),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward),
            tooltip: 'Find next match',
            onPressed: () => _search(isNext: true),
          ),
        ],
      );
}

// Custom scroll behavior that disables mouse wheel but allows drag
class _NoMouseWheelScrollBehavior extends ScrollBehavior {
  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      child;

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
      };
}

/// Lightweight painter that draws the cursor time label at the bottom of the
/// timescale header. Coordinates are pre-computed by the caller so this painter
/// has no coordinate math of its own — avoiding the regression risk.
class _CursorTimeLabelPainter extends CustomPainter {
  final String label;
  final double cursorViewportX;
  final double viewportWidth;
  final Color labelColor;

  // Cached TextPainter
  static TextPainter? _cachedPainter;
  static String _cachedLabel = '';
  static Color _cachedColor = Colors.red;

  _CursorTimeLabelPainter({
    required this.label,
    required this.cursorViewportX,
    required this.viewportWidth,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (label.isEmpty) {
      return;
    }

    // Build or reuse cached TextPainter
    if (_cachedPainter == null ||
        _cachedLabel != label ||
        _cachedColor != labelColor) {
      _cachedPainter?.dispose();
      _cachedPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: labelColor,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      _cachedLabel = label;
      _cachedColor = labelColor;
    }

    final tp = _cachedPainter!;
    // Position at the bottom of the 50px header
    final labelY = size.height - tp.height - 1.0;
    const pad = 2.0;
    var labelX = cursorViewportX - tp.width / 2;
    if (labelX < pad) {
      labelX = pad;
    }
    if (labelX + tp.width > viewportWidth - pad) {
      labelX = viewportWidth - pad - tp.width;
    }
    tp.paint(canvas, Offset(labelX, labelY));
  }

  @override
  bool shouldRepaint(covariant _CursorTimeLabelPainter oldDelegate) =>
      label != oldDelegate.label ||
      cursorViewportX != oldDelegate.cursorViewportX ||
      viewportWidth != oldDelegate.viewportWidth ||
      labelColor != oldDelegate.labelColor;
}

/// Paints the waveform-local measurement marker and primary-marker delta.
class _MeasurementMarkerPainter extends CustomPainter {
  final int primaryTimePs;
  final int? measurementTimePs;
  final double scrollOffset;
  final double contentWidth;
  final double viewportWidth;
  final int timescale;

  _MeasurementMarkerPainter({
    required this.primaryTimePs,
    required this.measurementTimePs,
    required this.scrollOffset,
    required this.contentWidth,
    required this.viewportWidth,
    required this.timescale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final measurementTime = measurementTimePs;
    if (measurementTime == null || timescale <= 0) {
      return;
    }
    const leftOffset = waveformLeftOffset;
    const rightPadding = waveformLeftOffset;
    final drawingWidth = contentWidth - leftOffset - rightPadding;
    if (drawingWidth <= 0) {
      return;
    }

    final contentX = leftOffset +
        (measurementTime.toDouble() / timescale.toDouble()) * drawingWidth;
    final markerX = contentX - scrollOffset;
    if (markerX < 0 || markerX > viewportWidth) {
      return;
    }

    final paint = Paint()
      ..color = Colors.cyanAccent
      ..strokeWidth = 1.5;
    const dashHeight = 6.0;
    const dashGap = 4.0;
    for (var y = 0.0; y < size.height; y += dashHeight + dashGap) {
      canvas.drawLine(
          Offset(markerX, y), Offset(markerX, y + dashHeight), paint);
    }

    if (primaryTimePs < 0) {
      return;
    }
    final deltaPs = measurementTime - primaryTimePs;
    final deltaText = formatCursorTimeLabel(deltaPs.abs());
    final frequencyText = _formatFrequency(deltaPs.abs());
    final label = deltaPs < 0
        ? 'dt: -$deltaText  f: $frequencyText'
        : 'dt: $deltaText  f: $frequencyText';
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.cyanAccent,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: viewportWidth - 8);
    final labelX =
        (markerX + 4).clamp(4.0, viewportWidth - textPainter.width - 4);
    textPainter
      ..paint(canvas, Offset(labelX, 4))
      ..dispose();
  }

  static String _formatFrequency(int deltaPs) {
    if (deltaPs == 0) {
      return 'infinite';
    }
    final hertz = 1e12 / deltaPs;
    if (hertz >= 1e9) {
      return '${(hertz / 1e9).toStringAsFixed(3)} GHz';
    }
    if (hertz >= 1e6) {
      return '${(hertz / 1e6).toStringAsFixed(3)} MHz';
    }
    if (hertz >= 1e3) {
      return '${(hertz / 1e3).toStringAsFixed(3)} kHz';
    }
    return '${hertz.toStringAsFixed(3)} Hz';
  }

  @override
  bool shouldRepaint(covariant _MeasurementMarkerPainter oldDelegate) =>
      primaryTimePs != oldDelegate.primaryTimePs ||
      measurementTimePs != oldDelegate.measurementTimePs ||
      scrollOffset != oldDelegate.scrollOffset ||
      contentWidth != oldDelegate.contentWidth ||
      viewportWidth != oldDelegate.viewportWidth ||
      timescale != oldDelegate.timescale;
}

/// Uses the repaint listenable to update during drag WITHOUT triggering
/// widget rebuild. This avoids the expensive BUILD→LAYOUT→full-Scene-
/// rebuild path that caused 200ms+ COMPOSITING per frame.
class _ZoomRegionPainter extends CustomPainter {
  final ValueNotifier<({int? startTime, int? endTime, bool isSelecting})>
      zoomRegionNotifier;
  final double Function(int time) timeToViewportX;

  _ZoomRegionPainter({
    required this.zoomRegionNotifier,
    required this.timeToViewportX,
  }) : super(repaint: zoomRegionNotifier);

  @override
  void paint(Canvas canvas, Size size) {
    final zoomRegion = zoomRegionNotifier.value;
    if (!zoomRegion.isSelecting ||
        zoomRegion.startTime == null ||
        zoomRegion.endTime == null) {
      return; // Nothing to draw
    }

    final start = zoomRegion.startTime!;
    final end = zoomRegion.endTime!;
    final minTime = start < end ? start : end;
    final maxTime = start < end ? end : start;

    final startX = timeToViewportX(minTime);
    final endX = timeToViewportX(maxTime);

    // Only draw if at least partially visible
    if (startX > size.width && endX > size.width) {
      return;
    }
    if (startX < 0 && endX < 0) {
      return;
    }

    final clampedStartX = startX.clamp(0.0, size.width);
    final clampedEndX = endX.clamp(0.0, size.width);
    if (clampedStartX >= clampedEndX) {
      return;
    }

    // Semi-transparent filled rectangle
    final paint = Paint()
      ..color = const Color(0x4D4A90E2)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTRB(clampedStartX, 0, clampedEndX, size.height),
      paint,
    );

    // Vertical boundary lines
    final linePaint = Paint()
      ..color = const Color(0xFF4A90E2)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas
      ..drawLine(
        Offset(clampedStartX, 0),
        Offset(clampedStartX, size.height),
        linePaint,
      )
      ..drawLine(
        Offset(clampedEndX, 0),
        Offset(clampedEndX, size.height),
        linePaint,
      );
  }

  // The repaint listenable handles updates; only repaint if the
  // conversion function identity changed (zoom/scroll change).
  @override
  bool shouldRepaint(covariant _ZoomRegionPainter oldDelegate) =>
      timeToViewportX != oldDelegate.timeToViewportX;
}
