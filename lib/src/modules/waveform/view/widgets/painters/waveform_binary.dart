// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// waveform_binary.dart
// Paints the binary waveform.
//
// 2024 April
// Author(s): Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
//            Yao Jing Quek <yao.jing.quek@intel.com>

import 'dart:math' show min;

import 'package:material_ui/material_ui.dart';
import 'package:rohd_wave_viewer/src/const/const.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/view/widgets/painters/waveform.dart';

/// Painter for binary and bitvector waveforms.
class WaveformBinary extends Waveform {
  /// Creates a binary waveform painter.
  WaveformBinary(
    super.waveform,
    super.finalTime,
    super.startTime, {
    super.signalWidth,
    super.valueFormat,
    super.leftOffset = waveformLeftOffset,
    super.viewportWidth = 0.0,
    super.scrollOffset = 0.0,
    super.timescale = 0,
    super.dataEndTime,
    super.signalColor,
    super.xColor,
    super.zColor,
    super.textColor,
    super.valueFont,
    super.labelBackgroundColor,
    this.useBezierCrossings = false,
    super.repaint,
  });

  /// Whether to use Bezier curves for transition crossings.
  final bool useBezierCrossings;

  @override
  List<double> gapExtensionYPositions(String lastValue, Size size) {
    // For single-bit: map 0→bottom, 1→top
    final intVal = int.tryParse(lastValue);
    if (intVal != null && (intVal == 0 || intVal == 1)) {
      return [size.height * (1 - intVal)];
    }
    // For multi-bit or X/Z: draw both rails
    return [0, size.height];
  }

  static bool _isBinaryValue(String value) {
    if (value.endsWith(' ')) {
      value = value.substring(0, value.length - 1);
    }
    return value.isNotEmpty &&
        value.codeUnits
            .every((codeUnit) => codeUnit == 0x30 || codeUnit == 0x31);
  }

  // ── Pre-allocated Paint objects — single-bit ──
  late final Paint _denseFill = Paint()
    ..color = signalColor.withValues(alpha: 0.35)
    ..style = PaintingStyle.fill;
  late final Paint _greenFill = Paint()
    ..color = signalColor.withValues(alpha: 0.20)
    ..style = PaintingStyle.fill;
  late final Paint _redFill = Paint()
    ..color = xColor.withValues(alpha: 0.20)
    ..style = PaintingStyle.fill;
  late final Paint _yellowFill = Paint()
    ..color = zColor.withValues(alpha: 0.20)
    ..style = PaintingStyle.fill;

  // ── Pre-allocated Paint objects — multi-bit ──
  late final Paint _multiBitDenseFill = Paint()
    ..color = signalColor.withValues(alpha: 0.5)
    ..style = PaintingStyle.fill;

  // ── Pre-allocated Path objects (reset at start of each paint()) ──
  final Path _bGreenPath = Path();
  final Path _bRedPath = Path();
  final Path _bYellowPath = Path();
  final Path _mGreenPath = Path();
  final Path _mRedPath = Path();
  final Path _mYellowPath = Path();

  // ── Pre-allocated lookup arrays (avoid per-frame List literal allocs) ──
  // Single-bit path arrays — indexed by colorIdx (0=green, 1=red, 2=yellow)
  late final List<Path> _bPathsByColor = [_bGreenPath, _bRedPath, _bYellowPath];
  final List<bool> _bHasVerbs = [false, false, false];
  // Multi-bit path arrays
  late final List<Path> _mPathsByColor = [_mGreenPath, _mRedPath, _mYellowPath];
  final List<bool> _mHasVerbs = [false, false, false];

  // ── Cached full-range segment lists ────────────────────────────────
  // Built once on first paint(), reused on every subsequent scroll frame.
  // Eliminates ~1050 List + segment object allocations per frame across
  // 25 signals (5.8 MB/s of GC pressure → 0).
  List<_BinarySegment>? _cachedBinSegments;
  List<_Segment>? _cachedMultiSegments;

  // Cached hasMultiValue result to avoid scanning all waveform data on every
  // paint
  bool? _cachedHasMultiValue;
  int? _cachedWaveformIdentity;

  /// Single-bit binary signals have no value labels.
  @override
  void collectLabelsForViewport(double contentWidth, double rowHeight) {
    if (!_getHasMultiValue()) {
      return;
    }
    super.collectLabelsForViewport(contentWidth, rowHeight);
  }

  bool _getHasMultiValue() {
    // Fast path: declared signal width
    if (signalWidth != null) {
      return signalWidth! > 1;
    }

    // Return cached result if waveform reference hasn't changed
    final identity = identityHashCode(waveform);
    if (_cachedHasMultiValue != null && _cachedWaveformIdentity == identity) {
      return _cachedHasMultiValue!;
    }

    // Compute and cache
    var result = false;
    for (final d in waveform) {
      final v = d.value.trim().toLowerCase();
      if (v.isEmpty) {
        continue;
      }

      // Scalar unknowns should remain in single-bit mode.
      if (v == 'x' || v == 'z') {
        continue;
      }

      // Radix literals like 1'bx / 1'b0 / 1'h1 should stay scalar.
      // Multi-bit radix literals (e.g. 16'hfffe) are buses.
      final tick = v.indexOf("'");
      if (tick > 0 && tick + 2 < v.length) {
        final declaredWidth = int.tryParse(v.substring(0, tick));
        if (declaredWidth != null && declaredWidth <= 1) {
          continue;
        }
        if (declaredWidth != null && declaredWidth > 1) {
          result = true;
          break;
        }
      }

      var vForXZ = v;
      if (vForXZ.startsWith('0x')) {
        vForXZ = vForXZ.substring(2);
      } else if (vForXZ.startsWith('0b')) {
        vForXZ = vForXZ.substring(2);
      }
      // Multi-bit unknown vectors (e.g., xx, zzzz) imply bus rendering.
      if ((vForXZ.contains('x') || vForXZ.contains('z')) && vForXZ.length > 1) {
        result = true;
        break;
      }
      if (v.startsWith('b')) {
        final bits = v.substring(1);
        if (bits.length > 1) {
          result = true;
          break;
        }
        continue;
      }
      if (v.startsWith('0x')) {
        final hex = v.substring(2);
        if (hex.length > 1) {
          result = true;
          break;
        }
        final parsed = int.tryParse(hex, radix: 16);
        if (parsed != null && parsed != 0 && parsed != 1) {
          result = true;
          break;
        }
        continue;
      }
      if (v.startsWith('0b')) {
        final bits = v.substring(2);
        if (bits.length > 1) {
          result = true;
          break;
        }
        final parsed = int.tryParse(bits, radix: 2);
        if (parsed != null && parsed != 0 && parsed != 1) {
          result = true;
          break;
        }
        continue;
      }
      if (_isBinaryValue(v)) {
        if (v.length > 1) {
          result = true;
          break;
        }
        continue;
      }
      final parsedDec = int.tryParse(v);
      if (parsedDec != null && parsedDec != 0 && parsedDec != 1) {
        result = true;
        break;
      }
    }
    _cachedHasMultiValue = result;
    _cachedWaveformIdentity = identity;
    return result;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (waveform.isEmpty || size.width <= 0) {
      return;
    }

    // Use the instance leftOffset (caller may pass a scaled offset)
    final left = leftOffset;

    // Reserve a right padding equal to the left offset (symmetric)
    final rightPadding = left;

    // Use ABSOLUTE time mapping: the canvas (size.width = contentWidth)
    // represents the full timescale.
    // Time 0 maps to x = leftOffset
    // Time timescale maps to x = size.width - rightPadding
    // This ensures waveform positions are consistent regardless of zoom/scroll.
    final effectiveTimescale = (timescale > 0) ? timescale : finalTime;
    if (effectiveTimescale <= 0) {
      return;
    }

    final drawingWidth = size.width - left - rightPadding;
    final pxPerTime = drawingWidth / effectiveTimescale;

    // The final segment is extended past effectiveTimescale so the
    // endTime transition/crossing has real pixel width.  We clip the
    // canvas at the endTime pixel position so no overshoot is visible.
    final endTimeX = left + effectiveTimescale * pxPerTime;
    canvas
      ..save()
      ..clipRect(Rect.fromLTRB(0, 0, endTimeX, size.height));

    // ── Visibility culling ──────────────────────────────────────────────
    // Compute the time window that maps to the current viewport so we can
    // skip drawing thousands of off-screen segments at high zoom levels.
    final (int visMinTime, int visMaxTime) = preVisMinTime != null
        ? (preVisMinTime!, preVisMaxTime!)
        : visibleTimeBoundsFor(size.width, liveScrollOffset, liveViewportWidth);

    // Use cached computation to avoid scanning all data on every paint/scroll
    final hasMultiValue = _getHasMultiValue();

    // If no multi-values found, draw simple single-bit waveform with coloring for X/Z
    if (!hasMultiValue) {
      // Draw waveform by segments, coloring X/Z appropriately

      // Calculate Y position for a value.
      // Inset by 1px so strokes (strokeWidth=2.0) don't bleed outside
      // the CustomPaint bounds and cause visual misalignment with
      // SignalTabContainer rows.
      const yInset = 1.0;
      const yTop = yInset;
      final yBot = size.height - yInset;
      int? parseScalar01(String value) {
        final v = value.trim().toLowerCase();
        if (v == '0' || v == '1') {
          return int.parse(v);
        }
        if (v.startsWith('0x')) {
          final parsed = int.tryParse(v.substring(2), radix: 16);
          if (parsed == 0 || parsed == 1) {
            return parsed;
          }
          return null;
        }
        if (v.startsWith('0b')) {
          final parsed = int.tryParse(v.substring(2), radix: 2);
          if (parsed == 0 || parsed == 1) {
            return parsed;
          }
          return null;
        }
        final tick = v.indexOf("'");
        if (tick > 0 && tick + 2 < v.length) {
          final radix = v[tick + 1];
          final digits = v.substring(tick + 2).replaceAll('_', '');
          if (digits == 'x' || digits == 'z') {
            return null;
          }
          if (radix == 'b') {
            final parsed = int.tryParse(digits, radix: 2);
            if (parsed == 0 || parsed == 1) {
              return parsed;
            }
          } else if (radix == 'h') {
            final parsed = int.tryParse(digits, radix: 16);
            if (parsed == 0 || parsed == 1) {
              return parsed;
            }
          }
        }
        return null;
      }

      double yForValue(String value) {
        if (Waveform.colorIdxOfHex(value) != 0) {
          return (yTop + yBot) / 2; // Middle for X/Z
        }
        final v = parseScalar01(value);
        return (v != null && v == 1) ? yTop : yBot;
      }

      // Build full-range segments once, cache on the painter instance.
      // During scroll the data and zoom are unchanged — only the scroll
      // offset differs — so we reuse the same list every frame and skip
      // off-screen segments via an inline bounds check below.
      // This eliminates ~350 _BinarySegment + List allocations per frame
      // (25 signals × 14 segs) that were the #1 V8 scavenger GC trigger.
      final binSegments = _cachedBinSegments ??= () {
        final segs = <_BinarySegment>[];
        if (waveform.isEmpty) {
          return segs;
        }
        // When dataEndTime is set (paused), only extend segments to that
        // point so the gap region beyond it isn't covered by normal paint.
        final segLimit = dataEndTime ?? effectiveTimescale;
        var cv = waveform.first.value;
        var lt = 0;
        for (var idx = 1; idx < waveform.length; idx++) {
          final d = waveform[idx];
          if (d.time < 0) {
            continue;
          }
          if (d.time > segLimit) {
            break;
          }
          if (d.value == cv) {
            continue;
          }
          segs.add(_BinarySegment(start: lt, end: d.time, value: cv));
          lt = d.time;
          cv = d.value;
        }
        // Extend final segment past the limit so the transition has real
        // pixel width (canvas clip trims the overshoot).
        final drawEnd = segLimit +
            (pxPerTime > 0 ? (6.0 / pxPerTime).ceil().clamp(1, 100) : 1);
        if (lt < drawEnd) {
          segs.add(_BinarySegment(start: lt, end: drawEnd, value: cv));
        }
        return segs;
      }();

      // ── Pixel-stride rendering for single-bit waveforms ───────────────
      // Absorb sub-pixel segments into dense runs to cap scene complexity
      // at O(viewportWidth).
      _bGreenPath.reset();
      _bRedPath.reset();
      _bYellowPath.reset();
      final bPaths = _bPathsByColor;
      final bHasVerbs = _bHasVerbs;
      bHasVerbs[0] = false;
      bHasVerbs[1] = false;
      bHasVerbs[2] = false;

      double denseStartX = 0;
      double denseEndX = 0;
      var inDense = false;

      // For single-bit waveforms, topY = yForValue('1') = yInset,
      // bottomY = yForValue('0') = size.height - yInset.
      // Inset the dense fill so it reads as "rapid toggling" rather than
      // a solid green block.
      final binTopY = yForValue('1');
      final binBottomY = yForValue('0');
      final denseInset = (binBottomY - binTopY) * 0.15;
      final denseTop = binTopY + denseInset;
      final denseBottom = binBottomY - denseInset;

      // Transition slope half-width removed — using vertical transitions
      // with strokeWidth=2.0 for pixel-aligned rendering.

      // Reuse pre-allocated fill paints (zero CanvasKit alloc).
      final denseFill = _denseFill;
      final greenFill = _greenFill;
      final redFill = _redFill;
      final yellowFill = _yellowFill;

      /// Return fill paint for a value, or null if no fill should be drawn.
      /// Only "high" segments (value == 1) get a fill. X/Z at mid-height
      /// get a half-height fill to indicate the indeterminate state.
      Paint? fillPaintForValue(String value) {
        final ci = Waveform.colorIdxOfHex(value);
        if (ci == 1) {
          return redFill;
        }
        if (ci == 2) {
          return yellowFill;
        }
        final v = parseScalar01(value);
        return (v != null && v == 1) ? greenFill : null;
      }

      // ── Pass 1: draw filled rectangles behind wide segments ────────────
      // Only fill segments that are at least 1px wide. Sub-pixel segments
      // are absorbed into dense runs (Pass 2), which draw their own fill.
      // Drawing fill here AND dense-fill later would double the opacity and
      // cause visible lightness variation.
      for (final seg in binSegments) {
        // Skip off-screen segments (cached list covers full data range).
        if (seg.end < visMinTime || seg.start > visMaxTime) {
          continue;
        }
        final sx = left + seg.start * pxPerTime;
        final ex = left + seg.end * pxPerTime;
        if (ex - sx < 1.0) {
          continue; // skip sub-pixel — handled by dense fill
        }
        final fillP = fillPaintForValue(seg.value);
        if (fillP == null) {
          continue;
        }
        final fillTop = yForValue(seg.value);
        canvas.drawRect(Rect.fromLTRB(sx, fillTop, ex, yBot), fillP);
      }

      // ── Pass 2: stroke paths ──────────────────────────────────────────

      void flushDense() {
        if (!inDense) {
          return;
        }
        final w = denseEndX - denseStartX;
        if (w > 0.5) {
          // Inset fill between the two rails
          canvas.drawRect(
            Rect.fromLTRB(denseStartX, denseTop, denseEndX, denseBottom),
            denseFill,
          );
          // Draw top and bottom rail lines at the actual rail positions
          bPaths[0].moveTo(denseStartX, binTopY);
          bPaths[0].lineTo(denseEndX, binTopY);
          bPaths[0].moveTo(denseStartX, binBottomY);
          bPaths[0].lineTo(denseEndX, binBottomY);
          bHasVerbs[0] = true;
        } else if (w > 0) {
          // Single-pixel dense: vertical line
          final sx = Waveform.snapX(denseStartX);
          bPaths[0].moveTo(sx, binTopY);
          bPaths[0].lineTo(sx, binBottomY);
          bHasVerbs[0] = true;
        }
        inDense = false;
      }

      for (var i = 0; i < binSegments.length; i++) {
        final seg = binSegments[i];
        // Skip segments entirely outside the visible window.
        if (seg.end < visMinTime || seg.start > visMaxTime) {
          continue;
        }
        final startX = left + seg.start * pxPerTime;
        final endX = left + seg.end * pxPerTime;
        final segW = endX - startX;

        if (segW < 1.0) {
          // Sub-pixel → absorb into dense run, but still draw vertical
          // transitions so narrow pulses remain visible as edge spikes.
          final y = yForValue(seg.value);

          // Draw vertical transition from previous segment into this one
          if (i > 0) {
            final prevY = yForValue(binSegments[i - 1].value);
            if ((prevY - y).abs() > 0.1) {
              final sx = Waveform.snapX(startX);
              bPaths[0].moveTo(sx, prevY);
              bPaths[0].lineTo(sx, y);
              bHasVerbs[0] = true;
            }
          }

          if (!inDense) {
            denseStartX = startX;
            inDense = true;
          }
          denseEndX = endX;
          continue;
        }

        // Wide segment: flush dense run first, including transition
        if (inDense) {
          // Draw vertical transition from last dense segment to this wide one
          if (i > 0) {
            final lastDenseIdx = i - 1;
            final lastDenseY = yForValue(binSegments[lastDenseIdx].value);
            final thisY = yForValue(seg.value);
            if ((lastDenseY - thisY).abs() > 0.1) {
              final dx = Waveform.snapX(denseEndX);
              bPaths[0].moveTo(dx, lastDenseY);
              bPaths[0].lineTo(dx, thisY);
              bHasVerbs[0] = true;
            }
          }
          flushDense();
        }

        if (endX <= startX) {
          continue;
        }

        final y = yForValue(seg.value);
        final ci = Waveform.colorIdxOfHex(seg.value);
        bHasVerbs[ci] = true;

        // ── Merge overlapping same-color, same-Y pairs ──
        if (segW < 6.0 && i + 1 < binSegments.length) {
          final nextSeg = binSegments[i + 1];
          final nextEndX = left + nextSeg.end * pxPerTime;
          final nextSegW = nextEndX - endX;
          final combinedSpan = nextEndX - startX;
          final nextY = yForValue(nextSeg.value);
          final nci = Waveform.colorIdxOfHex(nextSeg.value);
          if (nextSegW < 6.0 &&
              combinedSpan < 12.0 &&
              nci == ci &&
              (nextY - y).abs() < 0.1) {
            bPaths[ci].moveTo(startX, y);
            bPaths[ci].lineTo(nextEndX, y);
            i++;
            continue;
          }
        }

        bPaths[ci].moveTo(startX, y);
        bPaths[ci].lineTo(endX, y);

        // Draw vertical transition to next segment if it exists
        if (i < binSegments.length - 1) {
          final nextSeg = binSegments[i + 1];
          final nextY = yForValue(nextSeg.value);
          if ((nextY - y).abs() > 0.1) {
            final tx = Waveform.snapX(endX);
            final tci = Waveform.colorIdxOfHex(nextSeg.value);
            bHasVerbs[tci] = true;
            bPaths[tci].moveTo(tx, y);
            bPaths[tci].lineTo(tx, nextY);
          }
        }
      }

      // Flush trailing dense run
      flushDense();

      // Flush batched paths — at most 3 draw calls
      if (bHasVerbs[0]) {
        canvas.drawPath(bPaths[0], greenPaint);
      }
      if (bHasVerbs[1]) {
        canvas.drawPath(bPaths[1], redPaint);
      }
      if (bHasVerbs[2]) {
        canvas.drawPath(bPaths[2], yellowPaint);
      }

      paintGapRegion(canvas, size, pxPerTime);
      canvas.restore();
      return;
    }

    // Multi-value rendering: draw per-segment split paths that start/end at the
    // midpoint of each transition.

    // Map binary/multi-bit values to exact Y positions so rails match 0/1 positions.
    double yForBinary(String value) {
      try {
        // For scalar 0/1 values
        return size.height * (1 - int.parse(value));
      } on Object catch (_) {
        // For multi-bit vectors and X/Z containing vectors (e.g., bzzzz)
        // we map unknowns to the top rail when the previous side indicates
        // a high; the rails themselves are drawn symmetrically so unknowns
        // will occupy either top or bottom depending on logical side.
        // For simplicity, map non-scalar values to topY by returning 0.
        return size.height * 0; // top
      }
    }

    final topY = yForBinary('1');
    final bottomY = yForBinary('0');
    final centerY = (topY + bottomY) / 2;

    // Build segments between value changes — cached on the painter instance
    // so scroll frames reuse the same list (zero per-frame allocation).
    final List<_Segment> segments;

    if (_cachedMultiSegments != null) {
      segments = _cachedMultiSegments!;
    } else {
      final segs = <_Segment>[];
      final segLimit = dataEndTime ?? effectiveTimescale;
      if (waveform.isNotEmpty) {
        var cv = waveform.first.value;
        var lt = 0;
        for (var idx = 1; idx < waveform.length; idx++) {
          final d = waveform[idx];
          if (d.time < 0) {
            continue;
          }
          if (d.time > segLimit) {
            break;
          }
          if (d.value == cv) {
            continue;
          }
          segs.add(_Segment(start: lt, end: d.time, value: cv));
          lt = d.time;
          cv = d.value;
        }
        // Extend final segment past the limit (canvas clip trims overshoot).
        final drawEnd = segLimit +
            (pxPerTime > 0 ? (6.0 / pxPerTime).ceil().clamp(1, 100) : 1);
        if (lt < drawEnd) {
          segs.add(_Segment(start: lt, end: drawEnd, value: cv));
        }
      }
      _cachedMultiSegments = segs;
      segments = segs;
    }

    // For the visible window, count segments before visMinTime to get
    // the correct initial side parity.
    var segsBefore = 0;
    for (final seg in segments) {
      if (seg.end <= visMinTime) {
        segsBefore++;
      } else {
        break;
      }
    }

    if (segments.isEmpty) {
      paintGapRegion(canvas, size, pxPerTime);
      canvas.restore();
      return;
    }

    // Fixed connector width in pixels for consistent transition slopes
    const fixedConnectorPx = 6;
    const half = fixedConnectorPx / 2.0;

    // Initial side accounts for transitions before the visible window
    var side = segsBefore.isEven;

    // ── Batched paths per colour with closed polygons ────────────────────
    // Each segment is a single closed 7-point polygon.
    _mGreenPath.reset();
    _mRedPath.reset();
    _mYellowPath.reset();
    final mPaths = _mPathsByColor;
    final mHas = _mHasVerbs;
    mHas[0] = false;
    mHas[1] = false;
    mHas[2] = false;

    final denseFillPaint = _multiBitDenseFill;

    // Dense-run accumulator
    double denseStartX = 0;
    double denseEndX = 0;
    var inDense = false;

    void flushDense() {
      if (!inDense) {
        return;
      }
      final w = denseEndX - denseStartX;
      if (w > 0.5) {
        canvas.drawRect(
          Rect.fromLTRB(denseStartX, topY, denseEndX, bottomY),
          denseFillPaint,
        );
        mPaths[0].moveTo(denseStartX, topY);
        mPaths[0].lineTo(denseEndX, topY);
        mPaths[0].moveTo(denseStartX, bottomY);
        mPaths[0].lineTo(denseEndX, bottomY);
        mHas[0] = true;
      } else if (w > 0) {
        final sx = Waveform.snapX(denseStartX);
        mPaths[0].moveTo(sx, topY);
        mPaths[0].lineTo(sx, bottomY);
        mHas[0] = true;
      }
      inDense = false;
    }

    // Label candidates — always collected so that storeLabel() can populate
    // _pendingLabels for deferred viewport-aware rendering.
    final labelSegs = <_Segment>[];

    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      // Skip segments entirely outside the visible window.
      if (seg.end < visMinTime || seg.start > visMaxTime) {
        if (i < segments.length - 1) {
          side = !side;
        }
        continue;
      }
      final startX = left + seg.start * pxPerTime;
      final endX = left + seg.end * pxPerTime;
      final segW = endX - startX;

      if (segW < 1.0) {
        // Sub-pixel → absorb into dense run
        if (!inDense) {
          denseStartX = startX;
          inDense = true;
        }
        denseEndX = endX;
        if (i < segments.length - 1) {
          side = !side;
        }
        continue;
      }

      // ── Wide segment ──────────────────────────────────────────────────
      flushDense();

      final ci = Waveform.colorIdxOfHex(seg.value);

      if (endX <= startX) {
        if (i < segments.length - 1) {
          side = !side;
        }
        continue;
      }

      if (ci > 0) {
        // X/Z — center line
        mPaths[ci].moveTo(startX, centerY);
        mPaths[ci].lineTo(endX, centerY);
        mHas[ci] = true;
      } else {
        // First segment: no preceding transition, so leftRamp = 0.
        // Last segment: no following transition, so rightRamp = 0.
        final prevLenPx = (i > 0)
            ? ((segments[i - 1].end - segments[i - 1].start) * pxPerTime)
            : 0.0;
        final nextLenPx = (i < segments.length - 1)
            ? ((segments[i + 1].end - segments[i + 1].start) * pxPerTime)
            : 0.0;

        final double rampStart = min(half, min(segW / 2.0, prevLenPx / 2.0));
        final double rampEnd = min(half, min(segW / 2.0, nextLenPx / 2.0));

        final leftRamp = rampStart.clamp(0.0, segW / 2);
        final rightRamp = rampEnd.clamp(0.0, segW / 2);
        final leftCp = leftRamp / 2.0;
        final rightCp = rightRamp / 2.0;

        final topRail = side ? topY : bottomY;
        final bottomRail = side ? bottomY : topY;

        final useCurves = useBezierCrossings && segW >= 20.0;

        // ── Closed 7-point polygon (like Surfer) ──
        final p = mPaths[ci]
          // Start at left center
          ..moveTo(startX, centerY);
        // Left ramp up to top rail
        if (useCurves && leftRamp > 0) {
          p.cubicTo(
            startX + leftCp,
            centerY,
            startX + leftRamp - leftCp,
            topRail,
            startX + leftRamp,
            topRail,
          );
        } else {
          p.lineTo(startX + leftRamp, topRail);
        }
        // Top rail
        p.lineTo(endX - rightRamp, topRail);
        // Right ramp down to center
        if (useCurves && rightRamp > 0) {
          p.cubicTo(
            endX - rightRamp + rightCp,
            topRail,
            endX - rightCp,
            centerY,
            endX,
            centerY,
          );
        } else {
          p.lineTo(endX, centerY);
        }
        // Right ramp down to bottom rail
        if (useCurves && rightRamp > 0) {
          p.cubicTo(
            endX - rightCp,
            centerY,
            endX - rightRamp + rightCp,
            bottomRail,
            endX - rightRamp,
            bottomRail,
          );
        } else {
          p.lineTo(endX - rightRamp, bottomRail);
        }
        // Bottom rail
        p.lineTo(startX + leftRamp, bottomRail);
        // Left ramp back up to center
        if (useCurves && leftRamp > 0) {
          p.cubicTo(
            startX + leftRamp - leftCp,
            bottomRail,
            startX + leftCp,
            centerY,
            startX,
            centerY,
          );
        } else {
          p.lineTo(startX, centerY);
        }
        p.close();
        mHas[ci] = true;
      }

      if (segW >= 20.0) {
        labelSegs.add(seg);
      }
      if (i < segments.length - 1) {
        side = !side;
      }
    }

    // Flush trailing dense run
    flushDense();

    // Flush batched paths — at most 3 drawPath calls
    if (mHas[0]) {
      canvas.drawPath(mPaths[0], greenPaint);
    }
    if (mHas[1]) {
      canvas.drawPath(mPaths[1], redPaint);
    }
    if (mHas[2]) {
      canvas.drawPath(mPaths[2], yellowPaint);
    }

    // ── Labels ──────────────────────────────────────────────────────────
    // Labels are centred within the flat "rail" portion of the crossing
    // polygon (between the ramps), not the full segment.
    //
    // Labels are ALWAYS computed and stored via storeLabel() so that
    // paintStoredLabels() can draw them with viewport-aware centering.
    // When skipLabels is true (strip tile or active scrolling), only the
    // stored labels are produced.  When false (_ViewportPainter single-
    // signal path), labels are also drawn directly.
    final vpCenter = viewportCenterLabels;
    final scrollOff =
        vpCenter ? (liveScrollOffset.isNaN ? 0.0 : liveScrollOffset) : 0.0;
    final vpEnd = vpCenter
        ? scrollOff +
            (liveViewportWidth.isNaN
                ? (drawingWidth + left)
                : liveViewportWidth)
        : double.infinity;

    for (final seg in labelSegs) {
      final sx = left + seg.start * pxPerTime;
      final ex = left + seg.end * pxPerTime;
      // Inset by the maximum ramp half-width so the label stays on the
      // flat rail between crossing ramps.
      final railSx = sx + half;
      final railEx = ex - half;
      final available = railEx - railSx - 2.0; // 1 px pad each side
      if (available < 10.0) {
        continue;
      }
      final label = formatValueAsHexLabel(seg.value);
      // Try full label, then progressively truncated versions.
      final tp = Waveform.fitLabelToWidth(
        label,
        available,
        Waveform.scaledFontSize(size.height),
        effectiveLabelTextColor,
        valueFont: valueFont,
      );
      if (tp == null) {
        continue;
      }
      final textY = ((topY + bottomY) / 2 - tp.height / 2).roundToDouble();

      // Always store for deferred viewport-aware rendering.
      storeLabel(tp, railSx, railEx, textY, label);

      // When labels are suppressed (strip tiles / active scrolling),
      // paintStoredLabels() draws them later with viewport-aware centering.
      if (skipLabels) {
        continue;
      }

      if (vpCenter) {
        // ── Viewport-aware centering (_ViewportPainter path) ──
        final visSx = railSx < scrollOff ? scrollOff : railSx;
        final visEx = railEx > vpEnd ? vpEnd : railEx;
        final visW = visEx - visSx;

        TextPainter? activeTp;
        if (visW >= tp.width) {
          activeTp = tp;
        } else {
          final narrowAvail = visW - 2.0;
          if (narrowAvail >= 10.0) {
            activeTp = Waveform.fitLabelToWidth(
              label,
              narrowAvail,
              Waveform.scaledFontSize(size.height),
              effectiveLabelTextColor,
              valueFont: valueFont,
            );
          }
        }
        if (activeTp == null) {
          continue;
        }

        final cx = (visSx + visEx) / 2.0;
        var drawX = cx - activeTp.width / 2.0;
        drawX = drawX < visSx
            ? visSx
            : (drawX > visEx - activeTp.width ? visEx - activeTp.width : drawX);

        // Snap to integer screen pixel to avoid sub-pixel AA artefacts.
        final screenX = (drawX - scrollOff).roundToDouble();
        final snappedX = screenX + scrollOff;

        if (snappedX < visSx - 0.5 || snappedX + activeTp.width > visEx + 0.5) {
          continue;
        }

        final bgPaint = labelBgPaint;
        if (bgPaint != null) {
          canvas.drawRect(
            Rect.fromLTRB(
              snappedX - 1,
              textY,
              snappedX + activeTp.width + 1,
              textY + activeTp.height,
            ),
            bgPaint,
          );
        }
        activeTp.paint(canvas, Offset(snappedX, textY));
      } else {
        // ── Naive centering (fallback) ──
        final cx = (railSx + railEx) / 2.0;
        final drawX = (cx - tp.width / 2.0).roundToDouble();

        final bgPaint = labelBgPaint;
        if (bgPaint != null) {
          canvas.drawRect(
            Rect.fromLTRB(
              drawX - 1,
              textY,
              drawX + tp.width + 1,
              textY + tp.height,
            ),
            bgPaint,
          );
        }
        tp.paint(canvas, Offset(drawX, textY));
      }
    }

    paintGapRegion(canvas, size, pxPerTime);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant Waveform oldDelegate) {
    // Different subtype (e.g., after reorder) always needs repaint
    if (oldDelegate is! WaveformBinary) {
      return true;
    }
    // Delegate to base class for common checks (colors, waveform data,
    // geometry) — fixes theme-switch bug where color changes didn't
    // invalidate the GPU texture cache.
    return super.shouldRepaint(oldDelegate) ||
        oldDelegate.finalTime != finalTime ||
        oldDelegate.startTime != startTime ||
        oldDelegate.useBezierCrossings != useBezierCrossings;
  }
}

class _Segment {
  const _Segment({required this.start, required this.end, required this.value});

  final int start;
  final int end;
  final String value;
}

class _BinarySegment {
  const _BinarySegment({
    required this.start,
    required this.end,
    required this.value,
  });
  final int start;
  final int end;
  final String value;
}
