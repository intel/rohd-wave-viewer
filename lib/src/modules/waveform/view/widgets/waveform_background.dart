// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// waveform_background.dart
// The waveform background widget.
//
// 2024 April
// Author(s): Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
//            Yao Jing Quek <yao.jing.quek@intel.com>

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_wave_viewer/src/const/const.dart';
import 'package:rohd_wave_viewer/src/cubit/waveform_scale_cubit.dart';
import 'package:rohd_wave_viewer/src/modules/rohd_module/bloc/rohd_module_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/shared/widgets/widgets.dart';
import 'package:rohd_wave_viewer/src/modules/signal/bloc/signal_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/bloc/waveform_module_bloc.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/view/widgets/painters/painters.dart';
import 'package:rohd_wave_viewer/src/platform/platform.dart' as plat;
import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';

// Use platform-specific JS bindings: web implementation calls into JS,
// native implementation is a no-op.

/// Rendering modes for signal waveforms.
enum SignalType {
  /// Binary signal rendering.
  binary,

  /// Hexadecimal or bus-value rendering.
  hexadecimal,
}

/// Format a time value (in ps) into a human-readable label with units.
/// Public so the timescale header cursor label can reuse it.
String formatCursorTimeLabel(int value) =>
    _LiveCursorPainter._formatTimeLabel(value);

/// A wrapper CustomPainter that lets the inner painter think it is drawing on
/// a
/// full-width (zoomed) canvas, while the actual backing buffer is only
/// viewport-wide.  This prevents CanvasKit from allocating enormous pixel
/// buffers at high zoom levels (which caused OOM browser crashes).
///
/// It works by:
///   1. Clipping the canvas to `(0, 0, viewportWidth, height)`
///   2. Translating by `-scrollOffset` so content-space X maps to
///      viewport-space
///   3. Calling the inner painter with a virtual size of
///      `contentWidth × height`
///   4. Restoring the canvas state
///
/// ## Direct-paint strategy
///
/// For typical waveform content (~24 signal rows × ~10 visible intervals),
/// painting directly to the screen canvas is trivially fast (~1-3ms total
/// for all rows).  The previous approach of caching each row as a GPU
/// texture via `toImageSync()` introduced catastrophic overhead on
/// CanvasKit Web: each call creates a WASM SkSurface, replays the picture
/// through WebGL, and synchronously flushes the GPU pipeline.  With 24
/// rows, that's 24 surface create+flush+destroy cycles costing 700-1350ms
/// per frame during cache rebuilds (zoom transitions, theme changes, scroll
/// margin misses).
///
/// Direct paint eliminates all of that.  The inner painter's culling
/// already limits drawing to visible intervals, so the per-frame cost is
/// proportional to visible content — not total signal count or zoom level.
class _ViewportPainter extends CustomPainter {
  final CustomPainter inner;
  final ScrollController scrollController;
  final double contentWidth;

  /// When non-null and its value is `true`, the inner painter skips label
  /// rendering to halve the CanvasKit command volume during active scroll.
  /// Read live during [paint()] so the repaint-notifier path picks up
  /// scroll state changes without a widget rebuild.
  final ValueNotifier<bool>? scrollingNotifier;

  _ViewportPainter({
    required this.inner,
    required this.scrollController,
    required this.contentWidth,
    this.scrollingNotifier,
    ValueNotifier<int>? repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final scrollOffset =
        scrollController.hasClients ? scrollController.offset : 0.0;
    final scrolling = scrollingNotifier?.value ?? false;

    // ── Direct paint ──────────────────────────────────────────────────
    // Set culling bounds so the inner painter only draws visible content.
    if (inner is Waveform) {
      inner as Waveform
        ..liveScrollOffset = scrollOffset
        ..liveViewportWidth = size.width
        ..viewportCenterLabels = true // actual user viewport
        // Skip labels during active scroll to halve CanvasKit replay cost.
        // Labels are added back when the scroll settles (80ms debounce).
        // When debugSuppressLabels is on, labels are always suppressed.
        ..skipLabels = scrolling || Waveform.debugSuppressLabels
        ..clearStoredLabels();
    }

    // Clip to viewport, translate to content-space, paint.
    canvas
      ..save()
      ..clipRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..translate(-scrollOffset, 0);
    inner.paint(canvas, Size(contentWidth, size.height));
    canvas.restore();

    // Reset overrides.
    if (inner is Waveform) {
      inner as Waveform
        ..liveScrollOffset = double.nan
        ..liveViewportWidth = double.nan
        ..viewportCenterLabels = false;
    }
  }

  @override
  bool shouldRepaint(covariant _ViewportPainter oldDelegate) {
    final innerChanged = inner.shouldRepaint(oldDelegate.inner);
    return innerChanged || contentWidth != oldDelegate.contentWidth;
  }
}

// ─────────────────────────────────────────────────────────────────────
// Strip-based tile cache for combined waveform painting
// ─────────────────────────────────────────────────────────────────────

/// Shallow set equality check (no dependency on `collection` package).
bool _setEquals<T>(Set<T> a, Set<T> b) {
  if (a.length != b.length) {
    return false;
  }
  for (final e in a) {
    if (!b.contains(e)) {
      return false;
    }
  }
  return true;
}

/// Lightweight descriptor for one signal's rendering state.
class _SignalPaintInfo {
  final CustomPainter painter;
  final bool isFocused;
  const _SignalPaintInfo({required this.painter, required this.isFocused});
}

/// One cached GPU texture strip covering a fixed content-space X range.
///
/// Each strip is `stripWidth` pixels wide in content-space and covers
/// the full signal height.  Strips contain geometry only — labels are
/// painted in a separate pass directly to the screen canvas.
class _Strip {
  ui.Image? image;

  /// Content-space X where this strip begins.
  double startX;

  /// Content-space width of this strip.
  double width;

  /// Pixel height of the cached image.
  double height;

  _Strip()
      : startX = 0,
        width = 0,
        height = 0;

  bool get hasImage => image != null;

  void dispose() {
    image?.dispose();
    image = null;
  }
}

/// Manages a set of cached [_Strip] tiles that cover the viewport and
/// its immediate neighbourhood.
///
/// Instead of one giant 3× viewport tile (3.6M pixels, 1050ms to
/// rasterize), the content is divided into strips each ~1× viewport
/// width.  On cache miss, only the 1-2 strips entering the viewport
/// are rendered — capping the per-miss cost at ~1/3 of the old
/// monolithic tile (~175-350ms).
///
/// Strip boundaries are aligned to multiples of `stripWidth` so that
/// scrolling never partially invalidates a strip.
class _StripTileCache {
  /// Cached strips indexed by strip number (startX / stripWidth).
  final Map<int, _Strip> _strips = {};

  /// Configuration state — when any of these change, all strips
  /// are invalidated.  Note: scrolling state is NOT tracked here
  /// because labels are always painted in a separate pass (never
  /// baked into strip tiles).
  double _contentWidth = -1;
  int _signalCount = -1;
  bool _deferLabelsWhileScrolling = false;
  double _rowHeight = -1;

  /// Identity hash of the signal list (order-sensitive).  Changes on
  /// reorder even when the count stays the same.
  int _signalIdentity = 0;

  /// Check whether the cache has valid strips covering the given viewport.
  bool coversViewport(
    double scrollOffset,
    double viewportWidth,
    double stripWidth,
    double contentWidth,
    int signalCount,
  ) {
    if (_contentWidth != contentWidth) {
      return false;
    }
    if (_signalCount != signalCount) {
      return false;
    }

    final firstStrip = (scrollOffset / stripWidth).floor();
    final lastStrip = ((scrollOffset + viewportWidth) / stripWidth).floor();
    for (var s = firstStrip; s <= lastStrip; s++) {
      final strip = _strips[s];
      if (strip == null || !strip.hasImage) {
        return false;
      }
    }
    return true;
  }

  /// Return existing strip or null.
  _Strip? getStrip(int index) => _strips[index];

  /// Store a rendered strip.
  void putStrip(int index, _Strip strip) {
    _strips[index]?.dispose();
    _strips[index] = strip;
  }

  /// Update configuration tracking.
  void setConfig(
    double contentWidth,
    int signalCount, {
    int signalIdentity = 0,
    bool deferLabelsWhileScrolling = false,
    double rowHeight = 30.0,
  }) {
    _contentWidth = contentWidth;
    _signalCount = signalCount;
    _deferLabelsWhileScrolling = deferLabelsWhileScrolling;
    _signalIdentity = signalIdentity;
    _rowHeight = rowHeight;
  }

  /// Discard all cached strips and fully reset config state.
  void invalidate() {
    for (final s in _strips.values) {
      s.dispose();
    }
    _strips.clear();
    _contentWidth = -1;
    _signalCount = -1;
    _deferLabelsWhileScrolling = false;
    _signalIdentity = 0;
    _rowHeight = -1;
  }

  /// Evict strips that are far from the current viewport to bound memory.
  /// Keeps strips within [keep] indices of [firstVisible]..[lastVisible].
  void evictDistant(int firstVisible, int lastVisible, {int keep = 3}) {
    _strips.removeWhere((idx, strip) {
      if (idx < firstVisible - keep || idx > lastVisible + keep) {
        strip.dispose();
        return true;
      }
      return false;
    });
  }

  void dispose() {
    for (final s in _strips.values) {
      s.dispose();
    }
    _strips.clear();
  }
}

// ─────────────────────────────────────────────────────────────────────
// Label overlay GPU texture cache
// ─────────────────────────────────────────────────────────────────────

/// Caches the text-label overlay as a single GPU texture covering
/// viewport ± `_marginPx`. On cache-hit frames the overlay is a
/// single `Canvas.drawImage` blit — zero per-frame Dart CPU for
/// label collection/painting. Only one `toImageSync` call on miss
/// (not per-signal), so no "24 surface" overhead.
///
/// Invalidated when contentWidth, signalCount, or signalIdentity
/// changes (same triggers as the strip tile cache).
class _LabelOverlayCache {
  ui.Image? _image;

  /// Content-space X range covered by the cached image.
  double _minScroll = 0;
  double _maxScroll = 0;

  /// Pixel height of the cached image.
  double _height = 0;

  /// Configuration when the cache was built.
  double _contentWidth = -1;
  int _signalCount = -1;
  int _signalIdentity = 0;

  /// Device pixel ratio used when rendering the cached image.
  double _dpr = 1;

  static const double _marginPx = 500;

  /// Pre-allocated Paint for blit operations.  Uses bilinear filtering
  /// so text stays smooth on non-integer DPR displays (e.g. 1.25×, 1.5×).
  static final Paint _blitPaint = Paint()..filterQuality = ui.FilterQuality.low;

  /// Check if the cached image covers the current viewport.
  bool covers(
    double scrollOffset,
    double viewportWidth,
    double contentWidth,
    int signalCount,
    int signalIdentity,
    double height,
    double dpr,
  ) =>
      _image != null &&
      _contentWidth == contentWidth &&
      _signalCount == signalCount &&
      _signalIdentity == signalIdentity &&
      _height == height &&
      _dpr == dpr &&
      scrollOffset >= _minScroll &&
      (scrollOffset + viewportWidth) <= _maxScroll;

  /// Store a freshly rendered label overlay image.
  void store(
    ui.Image image,
    double minScroll,
    double maxScroll,
    double height,
    double contentWidth,
    int signalCount,
    int signalIdentity,
    double dpr,
  ) {
    _image?.dispose();
    _image = image;
    _minScroll = minScroll;
    _maxScroll = maxScroll;
    _height = height;
    _contentWidth = contentWidth;
    _signalCount = signalCount;
    _signalIdentity = signalIdentity;
    _dpr = dpr;
  }

  /// Blit the cached label overlay onto [canvas].
  /// Image x=0 corresponds to content-x=`_minScroll`.
  ///
  /// The image was rasterized at `_dpr`× physical resolution for crisp
  /// text on HiDPI displays. `drawImageRect` maps the full physical
  /// source onto the logical destination so CanvasKit samples 1:1.
  void blit(
    Canvas canvas,
    double scrollOffset,
    double viewportWidth,
    double canvasHeight,
  ) {
    if (_image == null) {
      return;
    }
    final imgW = _image!.width.toDouble();
    final imgH = _image!.height.toDouble();
    // Logical size = physical size / dpr
    final logW = imgW / _dpr;
    final logH = imgH / _dpr;
    final offsetX = (_minScroll - scrollOffset).roundToDouble();
    canvas
      ..save()
      ..clipRect(Rect.fromLTWH(0, 0, viewportWidth, canvasHeight))
      ..drawImageRect(
        _image!,
        Rect.fromLTWH(0, 0, imgW, imgH),
        Rect.fromLTWH(offsetX, 0, logW, logH),
        _blitPaint,
      )
      ..restore();
  }

  void invalidate() {
    _image?.dispose();
    _image = null;
    _contentWidth = -1;
    _signalCount = -1;
    _signalIdentity = 0;
  }

  void dispose() {
    _image?.dispose();
    _image = null;
  }
}

/// Paints ALL waveform signals via strip-based tile caching.
///
/// On cache-hit frames (95%+ of scroll frames), visible strips are
/// blitted via `Canvas.drawImageRect` — typically 1-2 calls at ~0.1ms
/// each.
///
/// On cache-miss frames, only the missing strip(s) are rendered via
/// `Picture.toImageSync`. Each strip covers ~1× viewport width, so
/// the miss cost is ~1/3 of the old monolithic 3× tile.
///
/// Strip width is set to 1× viewport width.  The painter pre-renders
/// 1 strip of margin on each side of the viewport (3 strips visible
/// total at any time), giving smooth scroll without frequent misses.
class _CombinedWaveformPainter extends CustomPainter {
  final List<_SignalPaintInfo> signals;
  final ScrollController scrollController;
  final double contentWidth;
  final ValueNotifier<bool>? scrollingNotifier;
  final bool deferLabelsWhileScrolling;
  final Color backgroundColor;
  final _StripTileCache stripCache;
  final _LabelOverlayCache labelCache;
  final double rowHeight;
  final DragReorderController? dragController;

  /// Order-sensitive identity of the signal list.  Changes on reorder
  /// even when the count stays the same, triggering strip invalidation.
  final int signalIdentity;

  /// Maximum strips to rasterize via toImageSync() per paint frame.
  /// Remaining strips are painted directly (uncached) and queued for
  /// rasterization in subsequent frames.
  static const int _maxStripsPerFrame = 1;

  // ── Pre-allocated Paint objects (avoid per-paint() allocations) ──
  late final Paint _bgPaint = Paint()..color = backgroundColor;
  late final Paint _focusedRowPaint = Paint()..color = const Color(0x59448AFF);
  late final Paint _blitPaint = Paint()..filterQuality = FilterQuality.none;
  late final Paint _dragHighlightPaint = Paint()
    ..color = const Color(0x59FFEB3B);
  late final Paint _dragInsertPaint = Paint()..color = const Color(0xFFFFEB3B);

  /// Notifier used to schedule follow-up repaints when progressive
  /// strip rasterization has deferred strips to the next frame.
  final ValueNotifier<int>? progressiveRepaintNotifier;

  _CombinedWaveformPainter({
    required this.signals,
    required this.scrollController,
    required this.contentWidth,
    required this.stripCache,
    required this.labelCache,
    required this.backgroundColor,
    required this.rowHeight,
    required this.signalIdentity,
    this.deferLabelsWhileScrolling = false,
    this.scrollingNotifier,
    this.dragController,
    this.progressiveRepaintNotifier,
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scrollOffset =
        scrollController.hasClients ? scrollController.offset : 0.0;
    final signalCount = signals.length;
    if (signalCount == 0) {
      return;
    }

    final totalHeight = signalCount * rowHeight;
    // Strip width = 1× viewport width (tunable).
    final stripWidth = size.width;
    if (stripWidth <= 0) {
      return;
    }

    // Check if configuration changed — invalidate all strips.
    // Note: scrolling state is NOT checked here — strips always contain
    // geometry only (labels are a separate overlay pass).
    // signalIdentity detects reorder (same count, different order).
    if (stripCache._contentWidth != contentWidth ||
        stripCache._signalCount != signalCount ||
        stripCache._deferLabelsWhileScrolling != deferLabelsWhileScrolling ||
        stripCache._signalIdentity != signalIdentity ||
        stripCache._rowHeight != rowHeight) {
      stripCache
        ..invalidate()
        ..setConfig(
          contentWidth,
          signalCount,
          signalIdentity: signalIdentity,
          deferLabelsWhileScrolling: deferLabelsWhileScrolling,
          rowHeight: rowHeight,
        );
    }

    // Determine which strips are needed: viewport + 1 margin each side.
    final firstVisible = (scrollOffset / stripWidth).floor();
    final lastVisible = ((scrollOffset + size.width) / stripWidth).floor();
    final firstNeeded = (firstVisible - 1).clamp(0, 999999);
    final lastNeeded = lastVisible + 1;

    // Collect strips that need rasterization.
    final missingStrips = <int>[];
    for (var s = firstNeeded; s <= lastNeeded; s++) {
      final existing = stripCache.getStrip(s);
      if (existing == null || !existing.hasImage) {
        missingStrips.add(s);
      }
    }

    // Progressive strip rasterization: limit toImageSync() calls to
    // [_maxStripsPerFrame] per paint frame (default 1).  Remaining
    // strips are painted directly to canvas (uncached fallback) so
    // the frame appears immediately, then a repaint is scheduled to
    // rasterize the next batch.  This converts one huge 220-280ms
    // frame into several quick frames.
    var rasterized = 0;
    final directPaintStrips = <int>{};

    // When the total signal height exceeds the WebGL GPU texture size limit
    // (4096 px), calling toImageSync() produces a truncated bitmap: rows
    // below y=4096 are silently dropped or smeared as a solid-colour stripe.
    // Disable the GPU strip cache for such tall content and always use the
    // direct-paint path, which draws straight to the Flutter canvas and has
    // no height restriction.
    final useStripCache = totalHeight.ceil() <= 4096;

    for (final s in missingStrips) {
      if (!useStripCache || rasterized >= _maxStripsPerFrame) {
        // Defer this strip — will be painted directly below.
        directPaintStrips.add(s);
        continue;
      }

      // Compute this strip's content-space bounds.
      final sStartX = s * stripWidth;
      final sEndX = (sStartX + stripWidth).clamp(0.0, contentWidth);
      final sW = sEndX - sStartX;
      if (sW <= 0) {
        continue;
      }

      // Clamp to WebGL max texture size.
      const maxDim = 4096;
      final pixelW = sW.ceil().clamp(1, maxDim);
      final pixelH = totalHeight.ceil().clamp(1, maxDim);

      final recorder = ui.PictureRecorder();
      final rc = Canvas(
        recorder,
        Rect.fromLTWH(0, 0, pixelW.toDouble(), pixelH.toDouble()),
      )
        // Background fill for this strip.
        ..drawRect(
          Rect.fromLTWH(0, 0, pixelW.toDouble(), pixelH.toDouble()),
          _bgPaint,
        );

      // Paint each signal into its vertical slot within this strip.
      for (var i = 0; i < signalCount; i++) {
        final info = signals[i];
        final inner = info.painter;
        final y = i * rowHeight;

        if (inner is Waveform) {
          inner
            ..liveScrollOffset = sStartX
            ..liveViewportWidth = sW
            ..viewportCenterLabels = false
            ..skipLabels = true
            ..clearStoredLabels();
        }

        rc
          ..save()
          ..clipRect(
            Rect.fromLTWH(0, y + 3.0, pixelW.toDouble(), rowHeight - 6.0),
          )
          ..translate(-sStartX, y + 3.0);
        inner.paint(rc, Size(contentWidth, rowHeight - 6.0));
        rc.restore();

        if (inner is Waveform) {
          inner
            ..liveScrollOffset = double.nan
            ..liveViewportWidth = double.nan
            ..viewportCenterLabels = false;
        }
      }

      final picture = recorder.endRecording();
      late final ui.Image tileImage;
      try {
        tileImage = picture.toImageSync(pixelW, pixelH);
      } finally {
        picture.dispose();
      }

      final strip = _Strip()
        ..image = tileImage
        ..startX = sStartX
        ..width = sW
        ..height = totalHeight;
      stripCache.putStrip(s, strip);
      rasterized++;
    }

    // Evict distant strips to bound memory.
    stripCache.evictDistant(firstVisible, lastVisible);

    // ── Blit visible strips to screen ──────────────────────────────
    // During a drag, rows are shifted via getRowTranslateY() so the
    // waveform preview matches the other two panels.
    final ctrl = dragController;
    final dragging = ctrl != null && ctrl.isDragging;

    // Background fill for any uncovered area.
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), _bgPaint);

    if (!dragging) {
      // Fast path: blit whole strips unshifted.
      for (var s = firstVisible; s <= lastVisible; s++) {
        final strip = stripCache.getStrip(s);
        if (strip == null || !strip.hasImage) {
          continue;
        }

        final screenX = strip.startX - scrollOffset;
        final srcW = strip.width;
        final srcH = totalHeight.clamp(0.0, size.height);
        if (srcW <= 0 || srcH <= 0) {
          continue;
        }

        canvas.drawImageRect(
          strip.image!,
          Rect.fromLTWH(0, 0, srcW, srcH),
          Rect.fromLTWH(screenX, 0, srcW, srcH),
          _blitPaint,
        );
      }
    } else {
      // Drag path: blit each row individually with Y translation
      // so the waveform rows shift in lockstep with the other panels.
      for (var i = 0; i < signalCount; i++) {
        final translateY = ctrl.getRowTranslateY(i);
        final srcY = i * rowHeight;
        final dstY = srcY + translateY;

        // Clip destination to canvas.
        if (dstY + rowHeight < 0 || dstY > size.height) {
          continue;
        }

        canvas
          ..save()
          ..clipRect(Rect.fromLTWH(0, dstY, size.width, rowHeight));

        for (var s = firstVisible; s <= lastVisible; s++) {
          final strip = stripCache.getStrip(s);
          if (strip == null || !strip.hasImage) {
            continue;
          }

          final screenX = strip.startX - scrollOffset;
          final srcW = strip.width;
          // Source: the row's vertical slice within the strip image.
          final imgH = strip.height;
          if (srcY >= imgH) {
            continue;
          }
          final sliceH = rowHeight.clamp(0.0, imgH - srcY);

          canvas.drawImageRect(
            strip.image!,
            Rect.fromLTWH(0, srcY, srcW, sliceH),
            Rect.fromLTWH(screenX, dstY, srcW, sliceH),
            _blitPaint,
          );
        }
        canvas.restore();
      }
    }

    // ── Direct-paint fallback for deferred strips ──────────────────
    // Strips not yet rasterized are painted directly to the canvas
    // (no toImageSync overhead), giving immediate visual results while
    // the cache fills progressively over subsequent frames.
    if (directPaintStrips.isNotEmpty) {
      for (final s in directPaintStrips) {
        final sStartX = s * stripWidth;
        final sEndX = (sStartX + stripWidth).clamp(0.0, contentWidth);
        final sW = sEndX - sStartX;
        if (sW <= 0) {
          continue;
        }
        final screenX = sStartX - scrollOffset;
        // Only paint strips that overlap the viewport.
        if (screenX + sW < 0 || screenX > size.width) {
          continue;
        }

        canvas
          ..save()
          ..clipRect(
            Rect.fromLTWH(screenX.clamp(0.0, size.width), 0, sW, size.height),
          );
        for (var i = 0; i < signalCount; i++) {
          final info = signals[i];
          final inner = info.painter;
          final y = i * rowHeight;
          if (inner is Waveform) {
            inner
              ..liveScrollOffset = sStartX
              ..liveViewportWidth = sW
              ..viewportCenterLabels = false
              ..skipLabels = true
              ..clearStoredLabels();
          }
          canvas
            ..save()
            ..clipRect(Rect.fromLTWH(screenX, y + 3.0, sW, rowHeight - 6.0))
            ..translate(-scrollOffset, y + 3.0);
          inner.paint(canvas, Size(contentWidth, rowHeight - 6.0));
          canvas.restore();
          if (inner is Waveform) {
            inner
              ..liveScrollOffset = double.nan
              ..liveViewportWidth = double.nan
              ..viewportCenterLabels = false;
          }
        }
        canvas.restore();
      }

      // Schedule a repaint for next frame to rasterize deferred strips.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final notifier = progressiveRepaintNotifier;
        if (notifier != null) {
          notifier.value++;
        }
      });
    }

    // ── Focused-row highlight (per-frame, not cached) ──────────────
    // Painted after strip blit so it reflects current selection state.
    for (var i = 0; i < signalCount; i++) {
      if (!signals[i].isFocused) {
        continue;
      }
      final y =
          dragging ? i * rowHeight + ctrl.getRowTranslateY(i) : i * rowHeight;
      if (y + rowHeight < 0 || y > size.height) {
        continue;
      }
      canvas.drawRect(
        Rect.fromLTWH(0, y, size.width, rowHeight),
        _focusedRowPaint,
      );
    }

    // ── Label overlay pass (GPU-cached) ────────────────────────────
    // Labels are NEVER baked into strip tiles (skipLabels = true).
    // Instead, we cache all labels as a single GPU texture covering
    // viewport ± margin.  On cache-hit frames (95%+), this is a single
    // drawImage blit — zero per-frame Dart CPU for label iteration.
    // Only on cache miss (scroll exceeds margin or config change) do we
    // run collectLabelsForViewport + paintStoredLabels into a recorder,
    // then toImageSync once for the whole overlay.
    //
    // During drag-reorder, labels fall back to direct paint because
    // each row has a dynamic Y translation.
    final labelScrollSuppressed =
        deferLabelsWhileScrolling && (scrollingNotifier?.value ?? false);
    if (!Waveform.debugSuppressLabels && !labelScrollSuppressed) {
      if (dragging) {
        // Direct paint fallback — rows have dynamic Y offsets.
        _paintLabelsDirectly(canvas, scrollOffset, size, signalCount, ctrl);
      } else if (!useStripCache) {
        // Content is too tall for a GPU label texture (same 4096px limit).
        // Paint labels directly to the Flutter canvas instead.
        _paintLabelsDirectly(canvas, scrollOffset, size, signalCount, null);
      } else {
        // GPU-cached path.
        // Get device pixel ratio so labels are rasterized at native
        // display resolution (crisp text in VS Code WebView at DPR>1).
        final dpr = ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
        final cacheHit = labelCache.covers(
          scrollOffset,
          size.width,
          contentWidth,
          signalCount,
          signalIdentity,
          totalHeight,
          dpr,
        );
        if (cacheHit) {
          labelCache.blit(canvas, scrollOffset, size.width, size.height);
        } else {
          _buildAndBlitLabelCache(
            canvas,
            scrollOffset,
            size,
            signalCount,
            totalHeight,
            dpr,
          );
        }
        // Per-frame edge-label pass: re-centre and abbreviate labels
        // whose segment straddles a viewport edge.  The GPU cache has
        // full-rail centering which is scroll-invariant; this overlay
        // fixes the 1-2 labels per row that touch the screen edge.
        _paintEdgeLabelsOverlay(canvas, scrollOffset, size, signalCount);
      }
    }

    // ── Drag-reorder overlay ─────────────────────────────────────
    // When a signal row is being dragged in any panel, highlight the
    // source row (translated to its drag position) and show an
    // insertion indicator at the target boundary.
    if (dragging) {
      final src = ctrl.sourceIndex!;
      final tgt = ctrl.targetIndex!;

      // Yellow highlight over source rows at their dragged positions.
      if (ctrl.isGroupDrag) {
        for (final gi in ctrl.groupIndices) {
          if (gi >= 0 && gi < signalCount) {
            final ty = ctrl.getRowTranslateY(gi);
            final y = gi * rowHeight + ty;
            canvas.drawRect(
              Rect.fromLTWH(0, y, size.width, rowHeight),
              _dragHighlightPaint,
            );
          }
        }
      } else if (src >= 0 && src < signalCount) {
        final srcTranslateY = ctrl.getRowTranslateY(src);
        final srcY = src * rowHeight + srcTranslateY;
        canvas.drawRect(
          Rect.fromLTWH(0, srcY, size.width, rowHeight),
          _dragHighlightPaint,
        );
      }

      // Insertion indicator: a 2px line at the target boundary.
      if (tgt >= 0 && tgt <= signalCount) {
        if (ctrl.isGroupDrag) {
          final anchorPos = ctrl.groupIndices.indexOf(src);
          final blockFirst = tgt - anchorPos;
          final blockLast = blockFirst + ctrl.groupIndices.length;
          final lineY = (blockFirst <= src)
              ? blockFirst * rowHeight
              : blockLast * rowHeight;
          canvas.drawRect(
            Rect.fromLTWH(0, lineY - 1, size.width, 2),
            _dragInsertPaint,
          );
        } else {
          final lineY = (tgt > src) ? (tgt + 1) * rowHeight : tgt * rowHeight;
          canvas.drawRect(
            Rect.fromLTWH(0, lineY - 1, size.width, 2),
            _dragInsertPaint,
          );
        }
      }
    }
  }

  /// Direct-paint labels for each signal row (used during drag-reorder
  /// when rows have dynamic Y translations).
  void _paintLabelsDirectly(
    Canvas canvas,
    double scrollOffset,
    Size size,
    int signalCount,
    DragReorderController? ctrl,
  ) {
    for (var i = 0; i < signalCount; i++) {
      final info = signals[i];
      final inner = info.painter;
      if (inner is! Waveform) {
        continue;
      }

      final translateY = ctrl?.getRowTranslateY(i) ?? 0.0;
      final y = i * rowHeight + translateY;

      if (y + rowHeight < 0 || y > size.height) {
        continue;
      }

      inner
        ..liveScrollOffset = scrollOffset
        ..liveViewportWidth = size.width
        ..clearStoredLabels()
        ..collectLabelsForViewport(contentWidth, rowHeight - 6.0);

      if (inner.hasStoredLabels) {
        canvas
          ..save()
          ..clipRect(Rect.fromLTWH(0, y + 3.0, size.width, rowHeight - 6.0))
          ..translate(-scrollOffset, y + 3.0);
        inner
          ..paintStoredLabels(canvas, scrollOffset, size.width)
          ..paintEdgeLabels(
            canvas,
            scrollOffset,
            size.width,
            rowHeight: rowHeight,
          );
        canvas.restore();
      }

      inner
        ..liveScrollOffset = double.nan
        ..liveViewportWidth = double.nan;
    }
  }

  /// Per-frame overlay: paint edge-centred labels for segments that
  /// straddle the current viewport edges.  Called after the GPU label
  /// cache blit so the edge fixup reflects the actual scroll position.
  void _paintEdgeLabelsOverlay(
    Canvas canvas,
    double scrollOffset,
    Size size,
    int signalCount,
  ) {
    for (var i = 0; i < signalCount; i++) {
      final info = signals[i];
      final inner = info.painter;
      if (inner is! Waveform) {
        continue;
      }
      if (!inner.hasStoredLabels) {
        continue;
      }

      final y = i * rowHeight;
      if (y + rowHeight < 0 || y > size.height) {
        continue;
      }

      canvas
        ..save()
        ..clipRect(Rect.fromLTWH(0, y + 3.0, size.width, rowHeight - 6.0))
        ..translate(-scrollOffset, y + 3.0);
      inner.paintEdgeLabels(
        canvas,
        scrollOffset,
        size.width,
        rowHeight: rowHeight,
      );
      canvas.restore();
    }
  }

  /// Record all labels into a GPU texture covering viewport ± margin,
  /// store in [labelCache], and blit to [canvas].
  void _buildAndBlitLabelCache(
    Canvas canvas,
    double scrollOffset,
    Size size,
    int signalCount,
    double totalHeight,
    double dpr,
  ) {
    const margin = _LabelOverlayCache._marginPx;
    final recordMin =
        (scrollOffset - margin).clamp(0.0, double.infinity).floorToDouble();
    final recordMax = (scrollOffset + size.width + margin).ceilToDouble();
    final recordWidth = recordMax - recordMin;

    // Rasterize at native display resolution so text is crisp on HiDPI.
    const maxDim = 4096;
    final pixelW = (recordWidth * dpr).ceil().clamp(1, maxDim);
    final pixelH = (totalHeight * dpr).ceil().clamp(1, maxDim);

    final recorder = ui.PictureRecorder();
    final rc = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, pixelW.toDouble(), pixelH.toDouble()),
    )
      // Scale by DPR: all subsequent drawing is in logical coordinates but
      // the output is rasterized at physical pixel resolution.
      ..scale(dpr, dpr);

    // Collect and paint labels for each signal into the recording canvas.
    for (var i = 0; i < signalCount; i++) {
      final info = signals[i];
      final inner = info.painter;
      if (inner is! Waveform) {
        continue;
      }

      final y = i * rowHeight;

      // Set culling bounds to the extended recording range.
      inner
        ..liveScrollOffset = recordMin
        ..liveViewportWidth = recordWidth
        ..clearStoredLabels()
        ..collectLabelsForViewport(contentWidth, rowHeight - 6.0);

      if (inner.hasStoredLabels) {
        rc
          ..save()
          ..clipRect(Rect.fromLTWH(0, y + 3.0, recordWidth, rowHeight - 6.0))
          ..translate(-recordMin, y + 3.0);
        inner.paintStoredLabels(rc, recordMin, recordWidth);
        rc.restore();
      }

      inner
        ..liveScrollOffset = double.nan
        ..liveViewportWidth = double.nan;
    }

    final picture = recorder.endRecording();
    late final ui.Image labelImage;
    try {
      labelImage = picture.toImageSync(pixelW, pixelH);
    } finally {
      picture.dispose();
    }

    labelCache
      ..store(
        labelImage,
        recordMin,
        recordMax,
        totalHeight,
        contentWidth,
        signalCount,
        signalIdentity,
        dpr,
      )
      ..blit(canvas, scrollOffset, size.width, size.height);
  }

  @override
  bool shouldRepaint(covariant _CombinedWaveformPainter oldDelegate) => true;
}

/// CustomPainter that draws the cursor/marker line.
///
/// Unlike the previous BlocBuilder+CursorWidget approach, this painter reads
/// the scroll offset **live during paint()** — exactly like `_ViewportPainter`.
/// It repaints via `_repaintNotifier` (which fires on every scroll frame) and
/// `_cursorTimeNotifier` (which fires when the bloc's timePs changes).
/// This eliminates the stale-scroll-offset bug where the cursor drifted from
/// the waveform edges after _scrollToCenterDataPoint animated the scroll.
class _LiveCursorPainter extends CustomPainter {
  final ValueNotifier<int> cursorTimeNotifier;
  final ScrollController scrollController;
  final double contentWidth;
  final double leftOffset;
  final double rightPadding;
  final double viewportWidth;
  final int timescale;
  final Color cursorColor;
  final bool isVideoMode;

  late final Paint _cursorPaint;

  _LiveCursorPainter({
    required this.cursorTimeNotifier,
    required this.scrollController,
    required this.contentWidth,
    required this.leftOffset,
    required this.rightPadding,
    required this.viewportWidth,
    required this.timescale,
    required Listenable repaint,
    this.cursorColor = Colors.red,
    this.isVideoMode = false,
  }) : super(repaint: Listenable.merge([repaint, cursorTimeNotifier])) {
    _cursorPaint = Paint()
      ..color = cursorColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true
      ..strokeCap = StrokeCap.round;
  }

  /// Format a time value (in ps) into a human-readable label with units.
  static String _formatTimeLabel(int value) {
    if (value == 0) {
      return '0ps';
    }
    final v = value.toDouble();
    String unit;
    double displayVal;
    if (v.abs() >= 1e9) {
      unit = 's';
      displayVal = v / 1e9;
    } else if (v.abs() >= 1e6) {
      unit = 'ms';
      displayVal = v / 1e6;
    } else if (v.abs() >= 1e3) {
      unit = 'ns';
      displayVal = v / 1e3;
    } else {
      unit = 'ps';
      displayVal = v;
    }
    final ax = displayVal.abs();
    String numStr;
    if (ax >= 100) {
      numStr = displayVal.toStringAsFixed(0);
    } else if (ax >= 10) {
      numStr = displayVal.toStringAsFixed(1);
      if (numStr.endsWith('0') && numStr.contains('.')) {
        numStr = numStr.substring(0, numStr.length - 1);
        if (numStr.endsWith('.')) {
          numStr = numStr.substring(0, numStr.length - 1);
        }
      }
    } else {
      numStr = displayVal.toStringAsFixed(2);
      while (numStr.endsWith('0') && numStr.contains('.')) {
        numStr = numStr.substring(0, numStr.length - 1);
      }
      if (numStr.endsWith('.')) {
        numStr = numStr.substring(0, numStr.length - 1);
      }
    }
    return '$numStr$unit';
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = cursorTimeNotifier.value;
    if (t < 0 || timescale <= 0) {
      return;
    }

    final drawingContentWidth = contentWidth - leftOffset - rightPadding;
    if (drawingContentWidth <= 0) {
      return;
    }

    final cursorContentX = leftOffset +
        (t.toDouble() / timescale.toDouble()) * drawingContentWidth;

    // Read scroll offset LIVE — same source as _ViewportPainter
    final liveScrollOff =
        scrollController.hasClients ? scrollController.offset : 0.0;
    final cursorViewportX = cursorContentX - liveScrollOff;

    if (cursorViewportX < 0 || cursorViewportX > viewportWidth) {
      return;
    }

    if (isVideoMode) {
      // Dashed vertical line in video/movie mode.
      const dashLen = 6;
      const gapLen = 4;
      double y = 0;
      while (y < size.height) {
        final end = (y + dashLen).clamp(0.0, size.height);
        canvas.drawLine(
          Offset(cursorViewportX, y),
          Offset(cursorViewportX, end),
          _cursorPaint,
        );
        y += dashLen + gapLen;
      }
    } else {
      canvas.drawLine(
        Offset(cursorViewportX, 0),
        Offset(cursorViewportX, size.height),
        _cursorPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LiveCursorPainter oldDelegate) =>
      contentWidth != oldDelegate.contentWidth ||
      leftOffset != oldDelegate.leftOffset ||
      rightPadding != oldDelegate.rightPadding ||
      viewportWidth != oldDelegate.viewportWidth ||
      timescale != oldDelegate.timescale ||
      cursorColor != oldDelegate.cursorColor ||
      isVideoMode != oldDelegate.isVideoMode;
}

/// Widget that renders the scrolling waveform background and rows.
class WaveformBackground extends StatefulWidget {
  /// Timescale of the currently loaded waveform.
  final int _timescale;

  /// Optional shared vertical scroll controller.
  final ScrollController? _verticalScrollController;

  /// Current horizontal zoom level.
  final double _zoomLevel;

  /// Shared horizontal scroll controller.
  final ScrollController _horizontalScrollController;

  /// Screen width used for viewport calculations.
  final double _screenWidth;

  /// Time up to which waveform data is known to be valid.
  ///
  /// When non-null and less than the current timescale, painters draw a gray
  /// hatched region from this value to the timescale to indicate
  /// that no data has been fetched for that range (paused).
  final int? _dataEndTime;

  /// Cross-panel drag-reorder controller.
  final DragReorderController? _dragController;

  /// When true, marker placement is disabled (video/live-tracking mode).
  final bool _isVideoMode;

  /// Creates a waveform background widget.
  const WaveformBackground({
    required int timescale,
    required double zoomLevel,
    required ScrollController horizontalScrollController,
    required double screenWidth,
    super.key,
    ScrollController? verticalScrollController,
    int? dataEndTime,
    DragReorderController? dragController,
    bool isVideoMode = false,
  })  : _timescale = timescale,
        _zoomLevel = zoomLevel,
        _horizontalScrollController = horizontalScrollController,
        _screenWidth = screenWidth,
        _verticalScrollController = verticalScrollController,
        _dataEndTime = dataEndTime,
        _dragController = dragController,
        _isVideoMode = isVideoMode;

  @override
  State<WaveformBackground> createState() => _WaveformBackgroundState();
}

class _WaveformBackgroundState extends State<WaveformBackground> {
  // Notifier used to trigger CustomPainter repaint when zoom/scroll changes
  final ValueNotifier<int> _repaintNotifier = ValueNotifier<int>(0);
  // Notifier for cursor time changes (driven by BlocListener)
  final ValueNotifier<int> _cursorTimeNotifier = ValueNotifier<int>(-1);

  /// Strip-based GPU tile cache for combined waveform rendering.
  final _StripTileCache _stripCache = _StripTileCache();

  /// GPU texture cache for the label overlay.
  final _LabelOverlayCache _labelCache = _LabelOverlayCache();

  /// Last signal identity hash seen by the BlocBuilder.  When the signal
  /// list changes (add/remove/reorder), this causes eager strip cache
  /// invalidation at build time (before paint runs).
  int _lastSignalIdentity = 0;

  // ── Painter cache (#1 hotspot fix) ──────────────────────────────────
  // Reuse per-signal Waveform painters across BlocBuilder rebuilds so
  // their pre-allocated Paint/Path objects and internal segment caches
  // (_cachedBinSegments, _cachedHexSegments, _cachedMultiSegments,
  // _cachedHasMultiValue) survive zoom/scroll.  This eliminates ~400
  // object allocations per zoom frame (the #1 GC trigger).
  //
  // Safety: the constructor-set fields that change on zoom/scroll
  // (finalTime, startTime, viewportWidth, scrollOffset) are either
  // unused in paint() or overridden by liveScrollOffset/liveViewportWidth
  // before each paint() call.  timescale is constant.
  final Map<String, Waveform> _painterCache = {};
  final Map<String, int> _painterDataIdentity = {};

  /// Track focus state per painter so a focus change triggers cache miss
  /// and painter recreation with the correct label background colour.
  final Map<String, bool> _painterFocusState = {};

  /// Focused signal IDs from the last build — used to detect focus
  /// changes and invalidate the GPU label cache.
  Set<String> _lastFocusedIds = const {};

  /// Track waveform theme colors so the entire painter cache can be
  /// invalidated on theme switch (Paint objects hold baked-in colours).
  Color? _lastCachedSignalHigh;
  Color? _lastCachedHexBus;
  Color? _lastCachedSignalX;
  Color? _lastCachedSignalZ;
  Color? _lastCachedTextColor;
  Color? _lastCachedLabelBg;

  int _waveformContentFingerprint(List<Data> data) {
    if (data.isEmpty) {
      return 0;
    }
    final first = data.first;
    final last = data.last;
    final mid = data[data.length >> 1];
    return Object.hash(
      data.length,
      first.time,
      first.value,
      mid.time,
      mid.value,
      last.time,
      last.value,
    );
  }

  bool _isScalarWaveformValue(String value) {
    final v = value.trim().toLowerCase();
    if (v.isEmpty) {
      return true;
    }
    if (v == '0' || v == '1' || v == 'x' || v == 'z') {
      return true;
    }
    if (v == '0x0' || v == '0x1' || v == '0b0' || v == '0b1') {
      return true;
    }

    final tick = v.indexOf("'");
    if (tick > 0 && tick + 2 < v.length) {
      final width = int.tryParse(v.substring(0, tick));
      if (width != null && width <= 1) {
        return true;
      }
    }
    return false;
  }

  bool _looksScalarWaveform(List<Data> data) {
    if (data.isEmpty) {
      return false;
    }
    for (final d in data) {
      if (!_isScalarWaveformValue(d.value)) {
        return false;
      }
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    // Listen to horizontal scroll changes to update timescale
    widget._horizontalScrollController.addListener(_onScroll);
    // Prime painters to ensure initial paint and to avoid cases where
    // the painter doesn't observe immediate subsequent repaint triggers.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _repaintNotifier.value++;
        // Only show cursor if waveform data is loaded (endTime > 0).
        // When no VCD is loaded the fallback timescale is tiny (20),
        // causing severe quantization that misaligns the marker.
        final endTime = context
            .read<RohdModuleBloc>()
            .state
            .moduleStructure
            .metadata
            .endTime;
        if (endTime > 0) {
          _cursorTimeNotifier.value =
              context.read<WaveformModuleBloc>().state.timePs;
        }
      }
    });
  }

  /// Timer that fires after resize movement settles, at which point we
  /// invalidate the strip cache and render crisp tiles.
  Timer? _resizeSettleTimer;

  @override
  void didUpdateWidget(WaveformBackground oldWidget) {
    super.didUpdateWidget(oldWidget);

    final zoomChanged = oldWidget._zoomLevel != widget._zoomLevel;
    final widthChanged = oldWidget._screenWidth != widget._screenWidth;
    final timescaleChanged = oldWidget._timescale != widget._timescale;
    final dataEndTimeChanged = oldWidget._dataEndTime != widget._dataEndTime;

    // Timescale or dataEndTime change: painters bake these at construction
    // time, so every cached painter must be discarded and rebuilt.
    if (timescaleChanged || dataEndTimeChanged) {
      _painterCache.clear();
      _painterDataIdentity.clear();
      _painterFocusState.clear();
      _stripCache.invalidate();
      _labelCache.invalidate();
    }

    if (zoomChanged || widthChanged) {
      if (zoomChanged) {
        // Zoom: invalidate immediately — the user expects the content to
        // re-grid at the new scale and zoom pauses input anyway.
        _resizeSettleTimer?.cancel();
        _stripCache.invalidate();
        _labelCache.invalidate();
      } else {
        // Resize only (no zoom): defer strip invalidation so the drag
        // movement stays responsive.  Existing strips are blitted
        // (possibly slightly mis-aligned) until the resize settles,
        // then crisp tiles are re-rendered once.
        _resizeSettleTimer?.cancel();
        _resizeSettleTimer = Timer(const Duration(milliseconds: 150), () {
          if (!mounted) {
            return;
          }
          _stripCache.invalidate();
          _labelCache.invalidate();
          _repaintNotifier.value++;
        });
      }

      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _repaintNotifier.value++;
      });
    }

    // If scroll controller changed, update listener
    if (oldWidget._horizontalScrollController !=
        widget._horizontalScrollController) {
      oldWidget._horizontalScrollController.removeListener(_onScroll);
      widget._horizontalScrollController.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    _repaintTimer?.cancel();
    _scrollSettleTimer?.cancel();
    _resizeSettleTimer?.cancel();
    widget._horizontalScrollController.removeListener(_onScroll);
    _stripCache.dispose();
    _labelCache.dispose();
    _repaintNotifier.dispose();
    _scrollingNotifier.dispose();
    _cursorTimeNotifier.dispose();
    _painterCache.clear();
    _painterDataIdentity.clear();
    _painterFocusState.clear();
    super.dispose();
  }

  void _onScroll() {
    if (!Waveform.deferLabelsWhileScrolling) {
      // Default mode: labels are baked into strip tiles and scroll with
      // waveform geometry. No scroll-state notifier/timer bookkeeping.
      _repaintNotifier.value++;
      return;
    }

    // Mark that we're actively scrolling — _ViewportPainter will skip
    // labels during scroll frames to halve the CanvasKit command volume
    // (labels account for ~50% of draw commands when zoomed out with
    // text shortening).
    _scrollingNotifier.value = true;
    _scrollSettleTimer?.cancel();
    if (!Waveform.debugSuppressLabels) {
      _scrollSettleTimer = Timer(const Duration(milliseconds: 80), () {
        // Scroll has settled — repaint with labels.
        _scrollingNotifier.value = false;
        _repaintNotifier.value++;
      });
    }
    // Trigger a repaint so _ViewportPainter reads the fresh scrollOffset from
    // the ScrollController during paint().  No setState / widget rebuild is
    // needed — only the CustomPainter.paint() call runs, which is cheap.
    _repaintNotifier.value++;
  }

  /// Whether the user is actively scrolling.  When true, label rendering
  /// is deferred to reduce per-frame CanvasKit compositing cost.
  /// Uses ValueNotifier so _ViewportPainter reads it live during paint()
  /// without requiring a widget rebuild.
  final ValueNotifier<bool> _scrollingNotifier = ValueNotifier<bool>(false);
  Timer? _scrollSettleTimer;

  Timer? _repaintTimer;

  /// Force a repaint from outside the widget (used by the parent panel during
  /// zoom)
  void forceRepaint() {
    if (!mounted) {
      return;
    }

    // Cancel any pending timer
    _repaintTimer?.cancel();

    // Use a short timer to force a couple of repaints (reduced from 10 to 3)
    // This keeps the compositor active in embedded webviews without spam
    var count = 0;
    _repaintTimer = Timer.periodic(const Duration(milliseconds: 32), (timer) {
      if (!mounted || count >= 3) {
        timer.cancel();
        return;
      }
      count++;
      _repaintNotifier.value++;
      setState(() {});
      SchedulerBinding.instance.scheduleFrame();
      _requestBrowserAnimationFrame();
      _callJsForceRepaint();
    });
  }

  void _callJsForceRepaint() {
    try {
      plat.jsRohdForceRepaint();
    } on Object catch (e) {
      debugPrint('[WaveformBackground] JS force repaint error: $e');
    }
  }

  void _requestBrowserAnimationFrame() {
    try {
      plat.jsRequestAnimationFrame(() {});
    } on Object catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final waveformColors = WaveformColors.of(context);
    return RepaintBoundary(
      child: ColoredBox(
        color: waveformColors.background,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final viewportWidth = widget._screenWidth;
            final contentWidth = viewportWidth * widget._zoomLevel;
            final scrollOffset = widget._horizontalScrollController.hasClients
                ? widget._horizontalScrollController.offset
                : 0.0;

            final visibleTimeRange =
                widget._timescale.toDouble() / widget._zoomLevel;
            final maxScrollExtent = (contentWidth - viewportWidth).clamp(
              0.0,
              double.infinity,
            );
            final scrollFraction =
                (maxScrollExtent > 0) ? (scrollOffset / maxScrollExtent) : 0.0;
            final maxStartTime =
                widget._timescale.toDouble() - visibleTimeRange;
            final visibleStartTime = scrollFraction * maxStartTime;

            const leftOffset = waveformLeftOffset;
            const rightPadding = waveformLeftOffset;

            return Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, innerConstraints) {
                      final rh =
                          context.watch<WaveformScaleCubit>().scaledRowHeight;
                      final fullRows =
                          (innerConstraints.maxHeight / rh).floor();
                      final effectiveHeight = fullRows * rh;
                      return SizedBox(
                        height: effectiveHeight,
                        child: Stack(
                          children: [
                            _buildWaveformLayer(
                              context,
                              waveformColors: waveformColors,
                              viewportWidth: viewportWidth,
                              visibleStartTime: visibleStartTime,
                              visibleTimeRange: visibleTimeRange,
                              leftOffset: leftOffset,
                              scrollOffset: scrollOffset,
                            ),
                            _buildInputOverlay(
                              context,
                              contentWidth: contentWidth,
                              leftOffset: leftOffset,
                              rightPadding: rightPadding,
                            ),
                            _buildCursorOverlay(
                              context,
                              waveformColors: waveformColors,
                              contentWidth: contentWidth,
                              leftOffset: leftOffset,
                              rightPadding: rightPadding,
                              viewportWidth: viewportWidth,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Waveform rendering layer — IgnorePointer + BlocBuilder + ListView.
  /// Wrapped in IgnorePointer so hit-testing during pan never traverses into
  /// the ListView (eliminates O(N) hit-test cost per pointer event).
  Widget _buildWaveformLayer(
    BuildContext context, {
    required WaveformColors waveformColors,
    required double viewportWidth,
    required double visibleStartTime,
    required double visibleTimeRange,
    required double leftOffset,
    required double scrollOffset,
  }) =>
      IgnorePointer(
        child: BlocBuilder<SignalBloc, SignalState>(
          builder: (content, state) {
            if (state is! SignalLoaded) {
              return const SizedBox.shrink();
            }

            // Use the waveformColors passed from build() — avoids a redundant
            // Theme.of(context) lookup that would re-register this subtree as
            // a Theme dependent (the outer build() already depends on Theme).
            final contentWidthForPainter = viewportWidth * widget._zoomLevel;
            final signals = state.monitorSignalsList;

            // Compute an order-sensitive identity hash so the strip cache
            // invalidates on reorder (same count, different order).
            // Use Object.hashAll (bounded hash) instead of a multiplicative
            // rolling hash to avoid precision loss/collisions on Flutter web
            // (JS number semantics) with long duplicate-heavy lists.
            final sigIdentity = Object.hashAll(
              List<int>.generate(
                signals.length,
                (i) =>
                    Object.hash(i, identityHashCode(signals[i]), signals[i].id),
                growable: false,
              ),
            );

            // Eagerly invalidate strip cache when signal list changes.
            // This runs at build time, before paint(), preventing any
            // frame where stale strips are blitted with the new signal
            // order's labels on top (which causes overlapping waveforms).
            if (sigIdentity != _lastSignalIdentity) {
              _lastSignalIdentity = sigIdentity;
              _stripCache.invalidate();
              _labelCache.invalidate();
              // Schedule a repaint after this build frame to guarantee
              // paint() runs with the invalidated cache and new painters,
              // even if shouldRepaint wasn't consulted (e.g. hot-reload
              // of a running session where the old delegate lacks the
              // signalIdentity field).
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _repaintNotifier.value++;
                }
              });
            }

            // ── Painter cache invalidation on theme colour change ──────
            // Paint objects bake in their colour at construction time, so
            // a theme switch requires recreating every painter.
            if (waveformColors.signalHigh != _lastCachedSignalHigh ||
                waveformColors.hexBus != _lastCachedHexBus ||
                waveformColors.signalX != _lastCachedSignalX ||
                waveformColors.signalZ != _lastCachedSignalZ ||
                waveformColors.text != _lastCachedTextColor ||
                waveformColors.background != _lastCachedLabelBg) {
              _painterCache.clear();
              _painterDataIdentity.clear();
              _painterFocusState.clear();
              _labelCache.invalidate();
              _stripCache.invalidate();
              _lastCachedSignalHigh = waveformColors.signalHigh;
              _lastCachedHexBus = waveformColors.hexBus;
              _lastCachedSignalX = waveformColors.signalX;
              _lastCachedSignalZ = waveformColors.signalZ;
              _lastCachedTextColor = waveformColors.text;
              _lastCachedLabelBg = waveformColors.background;
            }

            // ── Focus-change invalidation ──────────────────────────────
            // When a signal gains/loses focus its label background colour
            // changes, so the GPU label cache must be rebuilt.
            final currentFocusedIds = <String>{
              for (final sig in signals)
                if (state.isSignalFocused(sig.monitorId)) sig.monitorId,
            };
            if (!_setEquals(currentFocusedIds, _lastFocusedIds)) {
              _labelCache.invalidate();
              _lastFocusedIds = currentFocusedIds;
            }

            // Build per-signal painter descriptors for the combined painter.
            // Reuse cached painters when the signal data identity hasn't
            // changed, preserving their internal segment caches and ~16
            // pre-allocated Paint/Path objects per instance.
            final activeSignalIds = <String>{};
            final paintInfos =
                List<_SignalPaintInfo>.generate(signals.length, (i) {
              final sig = signals[i];
              activeSignalIds.add(sig.monitorId);
              final dataId = Object.hash(
                identityHashCode(sig.data),
                sig.data.length,
                _waveformContentFingerprint(sig.data),
              );
              final isBinary = sig.width == 1 || _looksScalarWaveform(sig.data);
              final sigType = (sig.type.toLowerCase() == 'bin' ||
                      sig.type.toLowerCase() == 'binary')
                  ? SignalType.binary
                  : SignalType.hexadecimal;
              final needsHex = !isBinary && sigType == SignalType.hexadecimal;

              if (sig.id.contains('uor_mantissa')) {
                debugPrint(
                  '[WaveformBg] ${{
                    'id': sig.id,
                    'width': sig.width,
                    'type': sig.type,
                    'isBinary': isBinary,
                    'needsHex': needsHex,
                    'points': sig.data.length,
                    'preview': sig.data
                        .take(4)
                        .map((d) => '@${d.time}:${d.value}')
                        .join(', ')
                  }}',
                );
              }

              final isFocused = state.isSignalFocused(sig.monitorId);

              // Blend the focus highlight colour into the label
              // background so text labels don't punch dark holes
              // through the blue highlight row.
              final effectiveLabelBg = isFocused
                  ? Color.alphaBlend(
                      Colors.blue.withValues(alpha: 0.35),
                      waveformColors.background,
                    )
                  : waveformColors.background;

              // Try to reuse a cached painter for this signal.
              var cached = _painterCache[sig.monitorId];
              final cacheHit = cached != null &&
                  _painterDataIdentity[sig.monitorId] == dataId &&
                  _painterFocusState[sig.monitorId] == isFocused &&
                  cached.valueFormat == sig.valueFormat &&
                  cached.timescale == widget._timescale &&
                  cached.dataEndTime == widget._dataEndTime &&
                  (needsHex
                      ? cached is WaveformHexaValue
                      : cached is WaveformBinary);
              if (cacheHit) {
                // Cache hit — reuse painter with all its segment caches
                // and pre-allocated Paint/Path objects intact.
              } else {
                // Cache miss — create a new painter.
                cached = isBinary
                    ? WaveformBinary(
                        sig.data,
                        visibleTimeRange.toInt(),
                        visibleStartTime.toInt(),
                        signalWidth: sig.width,
                        valueFormat: sig.valueFormat,
                        leftOffset: leftOffset,
                        viewportWidth: viewportWidth,
                        scrollOffset: scrollOffset,
                        timescale: widget._timescale,
                        dataEndTime: widget._dataEndTime,
                        signalColor: waveformColors.signalHigh,
                        xColor: waveformColors.signalX,
                        zColor: waveformColors.signalZ,
                        textColor: waveformColors.text,
                        labelBackgroundColor: effectiveLabelBg,
                        useBezierCrossings: true,
                      )
                    : (needsHex
                        ? WaveformHexaValue(
                            sig.data,
                            visibleTimeRange.toInt(),
                            visibleStartTime.toInt(),
                            signalWidth: sig.width,
                            valueFormat: sig.valueFormat,
                            leftOffset: leftOffset,
                            viewportWidth: viewportWidth,
                            scrollOffset: scrollOffset,
                            timescale: widget._timescale,
                            dataEndTime: widget._dataEndTime,
                            signalColor: waveformColors.hexBus,
                            xColor: waveformColors.signalX,
                            zColor: waveformColors.signalZ,
                            textColor: waveformColors.text,
                            labelBackgroundColor: effectiveLabelBg,
                          )
                        : WaveformBinary(
                            sig.data,
                            visibleTimeRange.toInt(),
                            visibleStartTime.toInt(),
                            signalWidth: sig.width,
                            valueFormat: sig.valueFormat,
                            leftOffset: leftOffset,
                            viewportWidth: viewportWidth,
                            scrollOffset: scrollOffset,
                            timescale: widget._timescale,
                            dataEndTime: widget._dataEndTime,
                            signalColor: waveformColors.signalHigh,
                            xColor: waveformColors.signalX,
                            zColor: waveformColors.signalZ,
                            textColor: waveformColors.text,
                            labelBackgroundColor: effectiveLabelBg,
                            useBezierCrossings: true,
                          ));
                _painterCache[sig.monitorId] = cached;
                _painterDataIdentity[sig.monitorId] = dataId;
                _painterFocusState[sig.monitorId] = isFocused;
              }

              return _SignalPaintInfo(painter: cached, isFocused: isFocused);
            });

            // Evict stale cache entries for signals no longer monitored.
            if (_painterCache.length > activeSignalIds.length) {
              _painterCache.keys
                  .where((id) => !activeSignalIds.contains(id))
                  .toList()
                  .forEach((id) {
                _painterCache.remove(id);
                _painterDataIdentity.remove(id);
                _painterFocusState.remove(id);
              });
            }

            final rh = context.watch<WaveformScaleCubit>().scaledRowHeight;
            final totalHeight = (signals.length + 1) * rh;

            return ScrollConfiguration(
              behavior:
                  ScrollConfiguration.of(context).copyWith(scrollbars: false),
              child: SingleChildScrollView(
                controller: widget._verticalScrollController,
                physics: const NeverScrollableScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 28),
                  child: SizedBox(
                    height: totalHeight,
                    child: CustomPaint(
                      size: Size(viewportWidth, totalHeight),
                      painter: _CombinedWaveformPainter(
                        signals: paintInfos,
                        scrollController: widget._horizontalScrollController,
                        contentWidth: contentWidthForPainter,
                        stripCache: _stripCache,
                        labelCache: _labelCache,
                        backgroundColor: waveformColors.background,
                        rowHeight: rh,
                        signalIdentity: sigIdentity,
                        deferLabelsWhileScrolling:
                            Waveform.deferLabelsWhileScrolling,
                        scrollingNotifier: _scrollingNotifier,
                        dragController: widget._dragController,
                        progressiveRepaintNotifier: _repaintNotifier,
                        repaint: Listenable.merge([
                          _repaintNotifier,
                          if (widget._dragController != null)
                            widget._dragController!,
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );

  /// Input overlay — handles pointer events for marker placement and blocks
  /// scroll-wheel from reaching the ListView. Hit-testing reaches this thin
  /// overlay in O(1) instead of traversing the full ListView widget tree.
  Widget _buildInputOverlay(
    BuildContext context, {
    required double contentWidth,
    required double leftOffset,
    required double rightPadding,
  }) =>
      Positioned.fill(
        child: Listener(
          onPointerDown: (event) {
            // Skip marker placement in video/live-tracking mode
            if (widget._isVideoMode) {
              return;
            }

            // Skip marker placement when no waveform data is loaded
            final endTime = context
                .read<RohdModuleBloc>()
                .state
                .moduleStructure
                .metadata
                .endTime;
            if (endTime <= 0) {
              return;
            }

            final keys = HardwareKeyboard.instance.logicalKeysPressed;
            final isControlPressed =
                keys.contains(LogicalKeyboardKey.controlLeft) ||
                    keys.contains(LogicalKeyboardKey.controlRight);
            if (isControlPressed) {
              return;
            }

            if ((event.buttons & 0x01) == 0) {
              return;
            }

            final localPos = event.localPosition;
            final liveScrollOffset =
                widget._horizontalScrollController.hasClients
                    ? widget._horizontalScrollController.offset
                    : 0.0;
            final contentX = localPos.dx + liveScrollOffset;

            final drawingContentWidth =
                contentWidth - leftOffset - rightPadding;
            if (drawingContentWidth <= 0 || widget._timescale <= 0) {
              return;
            }

            final rel = ((contentX - leftOffset) / drawingContentWidth).clamp(
              0.0,
              1.0,
            );
            final timeAtTap = (rel * widget._timescale).toInt();

            context
                .read<WaveformModuleBloc>()
                .add(WaveformModuleOnTap(timeAtTap));
          },
          onPointerSignal: (event) {
            // No-op: prevents scroll events from propagating
          },
          child: const SizedBox.expand(),
        ),
      );

  /// Cursor/marker overlay — drawn last (on top). Uses IgnorePointer so taps
  /// pass through to the gesture overlay.
  Widget _buildCursorOverlay(
    BuildContext context, {
    required WaveformColors waveformColors,
    required double contentWidth,
    required double leftOffset,
    required double rightPadding,
    required double viewportWidth,
  }) =>
      Positioned.fill(
        child: IgnorePointer(
          child: BlocListener<WaveformModuleBloc, WaveformModuleState>(
            listenWhen: (prev, curr) => prev.timePs != curr.timePs,
            listener: (context, state) {
              _cursorTimeNotifier.value = state.timePs;
            },
            child: CustomPaint(
              painter: _LiveCursorPainter(
                cursorTimeNotifier: _cursorTimeNotifier,
                scrollController: widget._horizontalScrollController,
                contentWidth: contentWidth,
                leftOffset: leftOffset,
                rightPadding: rightPadding,
                viewportWidth: viewportWidth,
                timescale: widget._timescale,
                repaint: _repaintNotifier,
                cursorColor: waveformColors.cursor,
                isVideoMode: widget._isVideoMode,
              ),
            ),
          ),
        ),
      );

  Offset adjustPropotion(BuildContext context, Offset adjustedOffset) {
    // 1. Get the width of the total canvas
    final canvasWidth = MediaQuery.of(context).size.width;

    // 2. Define the maximum scale value
    final maxScaleValue = widget._timescale.toDouble();

    // 3. Calculate the ratio
    final ratio = maxScaleValue / canvasWidth;

    // 4. Adjust the offset based on the ratio
    final scaledOffset = Offset(
      adjustedOffset.dx * ratio,
      adjustedOffset.dy * ratio,
    );

    return scaledOffset;
  }

  Offset getPosition(BuildContext context, TapDownDetails details) {
    final box = context.findRenderObject()! as RenderBox;
    final localOffset = box.globalToLocal(details.globalPosition);

    // Return raw local offset (viewport coordinates) so callers can map
    // to content/time consistently. Do not apply padding adjustments here.
    return localOffset;
  }

  Widget drawWaveform(
    BuildContext context,
    List<Data> data,
    SignalType sigType,
    double width,
    int startTime,
    int visibleTimeRange,
    double leftOffset,
    double visibleStartTime,
    double viewportWidth,
    double scrollOffset,
    int? signalWidth, {
    bool isFocused = false,
  }) {
    final painterWidth = width;

    // Get theme-aware colors (no LayoutBuilder needed — constraints aren't
    // used and LayoutBuilder forced an extra layout pass per signal row).
    final waveformColors = WaveformColors.of(context);

    // When the signal is focused the row has a blue highlight overlay.
    // Blend that highlight into the label background so repositioned text
    // labels don't leave dark "holes" in the blue background during panning.
    final effectiveLabelBg = isFocused
        ? Color.alphaBlend(
            Colors.blue.withValues(alpha: 0.35),
            waveformColors.background,
          )
        : waveformColors.background;

    // Compute the full zoomed content width for time mapping
    final contentWidthForPainter = viewportWidth * widget._zoomLevel;

    // Create the inner waveform painter
    final CustomPainter innerPainter = (signalWidth != null && signalWidth == 1)
        ? WaveformBinary(
            data,
            visibleTimeRange,
            startTime,
            signalWidth: signalWidth,
            leftOffset: leftOffset,
            viewportWidth: viewportWidth,
            scrollOffset: scrollOffset,
            timescale: widget._timescale,
            dataEndTime: widget._dataEndTime,
            signalColor: waveformColors.signalHigh,
            xColor: waveformColors.signalX,
            zColor: waveformColors.signalZ,
            textColor: waveformColors.text,
            labelBackgroundColor: effectiveLabelBg,
            useBezierCrossings: true,
          )
        : (sigType == SignalType.hexadecimal
            ? WaveformHexaValue(
                data,
                visibleTimeRange,
                startTime,
                signalWidth: signalWidth,
                leftOffset: leftOffset,
                viewportWidth: viewportWidth,
                scrollOffset: scrollOffset,
                timescale: widget._timescale,
                dataEndTime: widget._dataEndTime,
                signalColor: waveformColors.hexBus,
                xColor: waveformColors.signalX,
                zColor: waveformColors.signalZ,
                textColor: waveformColors.text,
                labelBackgroundColor: effectiveLabelBg,
              )
            : WaveformBinary(
                data,
                visibleTimeRange,
                startTime,
                signalWidth: signalWidth,
                leftOffset: leftOffset,
                viewportWidth: viewportWidth,
                scrollOffset: scrollOffset,
                timescale: widget._timescale,
                dataEndTime: widget._dataEndTime,
                signalColor: waveformColors.signalHigh,
                xColor: waveformColors.signalX,
                zColor: waveformColors.signalZ,
                textColor: waveformColors.text,
                labelBackgroundColor: effectiveLabelBg,
                useBezierCrossings: true,
              ));

    // Per-signal RepaintBoundary REMOVED: with 400+ signals, per-signal
    // composited layers cause 270ms+ COMPOSITING overhead per frame (CanvasKit
    // must composite each GPU texture individually). The top-level
    // RepaintBoundary on WaveformBackground already isolates the waveform
    // subtree. _ViewportPainter's Picture cache prevents re-rasterisation
    // when shouldRepaint returns false, so per-signal isolation is redundant.
    return Container(
      width: painterWidth,
      height: context.watch<WaveformScaleCubit>().scaledRowHeight,
      color:
          isFocused ? Colors.blue.withValues(alpha: 0.35) : Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: CustomPaint(
          size: Size.infinite,
          painter: _ViewportPainter(
            inner: innerPainter,
            scrollController: widget._horizontalScrollController,
            contentWidth: contentWidthForPainter,
            scrollingNotifier: _scrollingNotifier,
            repaint: _repaintNotifier,
          ),
        ),
      ),
    );
  }

  /// Draw a waveform using WaveData (Port + data).
  ///
  /// This method enables the new architecture where waveform data is fetched
  /// through SignalDataService and wrapped in WaveData objects.
  ///
  /// Usage:
  /// ```dart
  /// final waveData = await dataService.getSignalData(port);
  /// drawWaveformFromWaveData(context, waveData, ...);
  /// ```
  Widget drawWaveformFromWaveData(
    BuildContext context,
    WaveData waveData,
    double width,
    int startTime,
    int visibleTimeRange,
    double leftOffset,
    double visibleStartTime,
    double viewportWidth,
    double scrollOffset,
  ) {
    // Determine signal type from WaveData's port
    final sigType = (waveData.signalType.toLowerCase() == 'bin' ||
            waveData.signalType.toLowerCase() == 'binary')
        ? SignalType.binary
        : SignalType.hexadecimal;

    // Use the existing drawWaveform with data from WaveData
    return drawWaveform(
      context,
      waveData.data,
      sigType,
      width,
      startTime,
      visibleTimeRange,
      leftOffset,
      visibleStartTime,
      viewportWidth,
      scrollOffset,
      waveData.signalWidth,
    );
  }

  /// Convert a SignalOccurrence to a Port for use with SignalDataService.
  ///
  /// This helper enables gradual migration from SignalOccurrence-based code to
  /// Port-based code. Use this when you have a SignalOccurrence but need to
  /// fetch fresh data via the service.
  SignalOccurrence signalToPort(SignalOccurrence signal) => SignalOccurrence(
        name: signal.name,
        direction: signal.direction ?? 'unknown',
        width: signal.width,
      );
}
