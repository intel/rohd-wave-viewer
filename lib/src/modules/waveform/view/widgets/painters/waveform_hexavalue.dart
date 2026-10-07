// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// waveform_hexavalue.dart
// Paints the waveform with hexadecimal values.
//
// 2024 April
// Author(s): Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
//            Yao Jing Quek <yao.jing.quek@intel.com>

import 'dart:math' show min;
import 'package:material_ui/material_ui.dart';
import 'package:rohd_wave_viewer/src/const/const.dart';
import 'package:rohd_wave_viewer/src/modules/waveform/view/widgets/painters/waveform.dart'
    show Waveform;

/// Painter for hexadecimal or multi-bit bus waveforms.
class WaveformHexaValue extends Waveform {
  /// Creates a hexadecimal waveform painter.
  WaveformHexaValue(
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
    this.useBezierCrossings = true,
    super.repaint,
  });

  /// Whether to use Bezier curves for transition crossings.
  final bool useBezierCrossings;

  @override
  List<double> gapExtensionYPositions(String lastValue, Size size) {
    // Multi-bit bus: extend top and bottom rail lines (matching yInset=1.0).
    const yInset = 1.0;
    return [yInset, size.height - yInset];
  }

  // ── Pre-allocated Paint objects (avoid per-paint() CanvasKit alloc) ──
  late final Paint _greenFillPaint = Paint()
    ..color = greenPaint.color.withValues(alpha: 0.5)
    ..style = PaintingStyle.fill;
  late final Paint _redFillPaint = Paint()
    ..color = redPaint.color.withValues(alpha: 0.5)
    ..style = PaintingStyle.fill;
  late final Paint _yellowFillPaint = Paint()
    ..color = yellowPaint.color.withValues(alpha: 0.5)
    ..style = PaintingStyle.fill;
  late final Paint _greenOutlinePaint = Paint()
    ..color = greenPaint.color
    ..strokeWidth = 1.0
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;
  late final Paint _redOutlinePaint = Paint()
    ..color = redPaint.color
    ..strokeWidth = 1.0
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;
  late final Paint _yellowOutlinePaint = Paint()
    ..color = yellowPaint.color
    ..strokeWidth = 1.0
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;

  // ── Pre-allocated Path objects (reset at start of each paint()) ──
  final Path _greenPath = Path();
  final Path _redPath = Path();
  final Path _yellowPath = Path();
  final Path _greenOutlinePath = Path();
  final Path _redOutlinePath = Path();
  final Path _yellowOutlinePath = Path();

  // ── Pre-allocated lookup arrays (avoid per-frame List literal allocs) ──
  late final List<Path> _pathByColor = [_greenPath, _redPath, _yellowPath];
  late final List<Path> _oPathByColor = [
    _greenOutlinePath,
    _redOutlinePath,
    _yellowOutlinePath,
  ];
  final List<bool> _hasVerbs = [false, false, false];
  final List<bool> _oHasVerbs = [false, false, false];
  // Paint lookup arrays (indexed by colorIdx: 0=green, 1=red, 2=yellow)
  late final List<Paint> _strokeByColor = [greenPaint, redPaint, yellowPaint];
  late final List<Paint> _fillByColor = [
    _greenFillPaint,
    _redFillPaint,
    _yellowFillPaint,
  ];
  late final List<Paint> _outlineByColor = [
    _greenOutlinePaint,
    _redOutlinePaint,
    _yellowOutlinePaint,
  ];

  // ── Cached full-range segment list ─────────────────────────────────
  // Built once on first paint(), reused on every subsequent scroll frame.
  List<_HexSegment>? _cachedHexSegments;

  @override
  void paint(Canvas canvas, Size size) {
    // Removed paint debug logging
    // Use the instance leftOffset passed by the caller (may already be scaled)
    final left = leftOffset;
    final rightPadding = left;
    final drawingWidth = (size.width - left - rightPadding).clamp(
      0.0,
      double.infinity,
    );

    // Use ABSOLUTE time mapping: the canvas represents the full timescale.
    final effectiveTimescale = (timescale > 0) ? timescale : finalTime;
    if (effectiveTimescale <= 0 || drawingWidth <= 0) {
      return;
    }

    // We draw within the inner drawing region (excluding left/right padding)
    // We'll render multi-bit (hex) values as two parallel green lines with
    // the textual value between them. On transitions the two lines cross so
    // the visual encoding switches sides while remaining parallel.

    final pxPerTime = drawingWidth / effectiveTimescale;

    // The final segment is extended past effectiveTimescale so the
    // endTime crossing has real pixel width.  We clip the canvas at
    // the endTime pixel position so no overshoot is visible.
    final endTimeX = left + effectiveTimescale * pxPerTime;
    canvas
      ..save()
      ..clipRect(Rect.fromLTRB(0, 0, endTimeX, size.height));

    // ── Visibility culling ──────────────────────────────────────────────
    final (int visMinTime, int visMaxTime) = preVisMinTime != null
        ? (preVisMinTime!, preVisMaxTime!)
        : visibleTimeBoundsFor(size.width, liveScrollOffset, liveViewportWidth);

    // Map binary/multi-bit values to exact Y positions so rails match 0/1 positions.
    // Inset by 1px so strokes (strokeWidth=2.0) don't bleed outside
    // the CustomPaint bounds and cause visual misalignment.
    const yInset = 1.0;
    const yTop = yInset;
    final yBot = size.height - yInset;
    double yForBinary(String value) {
      try {
        final v = int.parse(value);
        return v == 1 ? yTop : yBot;
      } on Object catch (_) {
        // Non-scalar values map to top by default to keep rails symmetric.
        return yTop;
      }
    }

    final topY = yForBinary('1');
    final bottomY = yForBinary('0');

    // Build value-change segments [start, end) — cached on the painter
    // instance so scroll frames reuse the same list (zero per-frame alloc).
    final segments = _cachedHexSegments ??= () {
      final segs = <_HexSegment>[];
      if (waveform.isEmpty) {
        return segs;
      }
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
        segs.add(_HexSegment(start: lt, end: d.time, value: cv));
        lt = d.time;
        cv = d.value;
      }
      // Extend final segment past the limit so the transition crossing has
      // real pixel width (canvas clip trims the overshoot).
      final drawEnd = segLimit +
          (pxPerTime > 0 ? (6.0 / pxPerTime).ceil().clamp(1, 100) : 1);
      if (lt < drawEnd) {
        segs.add(_HexSegment(start: lt, end: drawEnd, value: cv));
      }
      return segs;
    }();

    if (segments.isEmpty) {
      paintGapRegion(canvas, size, pxPerTime);
      canvas.restore();
      return;
    }

    var side = true; // tracks which side (top/bottom) the current value is on

    // ── Pixel-stride rendering with density-based simplification ─────────
    // For zoomed-out views with overlapping transitions, render solid color
    // regions instead of drawing crossing shapes. When zoomed in (segW >=
    // 20px), render the detailed 7-point crossing polygons with optional Bezier
    // curves.

    // ── Colour classification + lookup tables (0=green, 1=red/x, 2=yellow/z)
    final strokeByColor = _strokeByColor;
    final fillByColor = _fillByColor;
    final outlineByColor = _outlineByColor;

    // Reset pre-allocated paths (no CanvasKit Path() alloc per paint()).
    _greenPath.reset();
    _redPath.reset();
    _yellowPath.reset();
    _greenOutlinePath.reset();
    _redOutlinePath.reset();
    _yellowOutlinePath.reset();
    final pathByColor = _pathByColor;
    final oPathByColor = _oPathByColor;
    final hasVerbs = _hasVerbs;
    hasVerbs[0] = false;
    hasVerbs[1] = false;
    hasVerbs[2] = false;
    final oHasVerbs = _oHasVerbs;
    oHasVerbs[0] = false;
    oHasVerbs[1] = false;
    oHasVerbs[2] = false;

    // Dense-run accumulator for sub-pixel segments
    double denseStartX = 0;
    double denseEndX = 0;
    String? denseValue;
    var inDense = false;

    void flushDense() {
      if (!inDense || denseValue == null) {
        return;
      }
      final w = denseEndX - denseStartX;
      final dci = Waveform.colorIdxOfHex(denseValue!);
      if (w > 0.5) {
        canvas.drawRect(
          Rect.fromLTRB(denseStartX, topY, denseEndX, bottomY),
          fillByColor[dci],
        );
        // Batch outline lines into outline paths instead of individual drawLine
        oPathByColor[dci]
          ..moveTo(denseStartX, topY)
          ..lineTo(denseEndX, topY)
          ..moveTo(denseStartX, bottomY)
          ..lineTo(denseEndX, bottomY);
        oHasVerbs[dci] = true;
      } else if (w > 0) {
        // Single-pixel dense: vertical line
        final oPath = oPathByColor[dci];
        final sx = Waveform.snapX(denseStartX);
        oPath
          ..moveTo(sx, topY)
          ..lineTo(sx, bottomY);
        oHasVerbs[dci] = true;
      }
      inDense = false;
      denseValue = null;
    }

    final centerY = (topY + bottomY) / 2;
    const connPx = 6;
    const halfConn = connPx / 2.0;

    // Label candidates (only when labels will be drawn)
    final labelSegs = <_HexSegment>[];

    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      // Skip segments entirely outside the visible window.
      if (seg.end < visMinTime || seg.start > visMaxTime) {
        side = !side;
        continue;
      }
      final startX = left + seg.start * pxPerTime;
      final endX = left + seg.end * pxPerTime;
      final segW = endX - startX;

      if (segW < 1.0) {
        // Sub-pixel segment → accumulate into dense run,
        // but draw vertical transition lines to keep narrow pulses visible.
        if (!inDense || denseValue != seg.value) {
          // Batch crossing/transition line at the boundary (via outline paths)
          final sci = Waveform.colorIdxOfHex(seg.value);
          if (inDense && denseValue != null && denseValue != seg.value) {
            // Vertical crossing at boundary of value change
            final oPath = oPathByColor[sci];
            final sx = Waveform.snapX(startX);
            oPath
              ..moveTo(sx, topY)
              ..lineTo(sx, bottomY);
            oHasVerbs[sci] = true;
          } else if (!inDense && i > 0) {
            // Entering dense from a wide segment — draw boundary crossing
            final oPath = oPathByColor[sci];
            final sx = Waveform.snapX(startX);
            oPath
              ..moveTo(sx, topY)
              ..lineTo(sx, bottomY);
            oHasVerbs[sci] = true;
          }
          flushDense();
          denseStartX = startX;
          denseValue = seg.value;
          inDense = true;
        }
        denseEndX = endX;
        if (i < segments.length - 1) {
          side = !side;
        }
        continue;
      }

      // Wide segment: batch crossing at dense→wide boundary, then flush
      final ci = Waveform.colorIdxOfHex(seg.value);
      if (inDense) {
        final oPath = oPathByColor[ci];
        final dx = Waveform.snapX(denseEndX);
        oPath
          ..moveTo(dx, topY)
          ..lineTo(dx, bottomY);
        oHasVerbs[ci] = true;
        flushDense();
      }

      if (endX <= startX) {
        if (i < segments.length - 1) {
          side = !side;
        }
        continue;
      }

      // Draw crossing polygon — ramps auto-clamp to segW/2 so tips never overlap.
      {
        final prevLenPx = (i > 0)
            ? ((segments[i - 1].end - segments[i - 1].start) * pxPerTime)
            : 0.0;
        final nextLenPx = (i < segments.length - 1)
            ? ((segments[i + 1].end - segments[i + 1].start) * pxPerTime)
            : 0.0;

        final double rampStart = min(
          halfConn,
          min(segW / 2.0, prevLenPx / 2.0),
        );
        final double rampEnd = min(halfConn, min(segW / 2.0, nextLenPx / 2.0));

        final leftRamp = rampStart.clamp(0.0, segW / 2);
        final rightRamp = rampEnd.clamp(0.0, segW / 2);
        final leftCp = leftRamp / 2.0;
        final rightCp = rightRamp / 2.0;

        final topRail = side ? topY : bottomY;
        final bottomRail = side ? bottomY : topY;

        // Use Bezier curves only when wide enough to see curvature
        final useCurves = useBezierCrossings && segW >= 20.0;

        // Draw 7-point crossing polygon
        final p = pathByColor[ci]..moveTo(startX, centerY);
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
        p.lineTo(endX - rightRamp, topRail);
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
        p.lineTo(startX + leftRamp, bottomRail);
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
        hasVerbs[ci] = true;

        if (segW >= 20.0) {
          labelSegs.add(seg);
        }
      }

      if (i < segments.length - 1) {
        side = !side;
      }
    }

    // Flush any trailing dense run
    flushDense();

    // Draw batched crossing-polygon paths (strokeWidth=2.0)
    for (var c = 0; c < 3; c++) {
      if (hasVerbs[c]) {
        canvas.drawPath(pathByColor[c], strokeByColor[c]);
      }
    }

    // Draw batched outline paths (strokeWidth=1.0) — dense outlines,
    // narrow-segment outlines, and dense-boundary transitions.
    for (var c = 0; c < 3; c++) {
      if (oHasVerbs[c]) {
        canvas.drawPath(oPathByColor[c], outlineByColor[c]);
      }
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
      final railSx = sx + halfConn;
      final railEx = ex - halfConn;
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
    if (oldDelegate is! WaveformHexaValue) {
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

class _HexSegment {
  const _HexSegment({
    required this.start,
    required this.end,
    required this.value,
  });
  final int start;
  final int end;
  final String value;
}
