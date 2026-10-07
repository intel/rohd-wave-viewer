// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// timescale.dart
// The timescale widget for the waveform display.
//
// 2024 April
// Author(s): Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
//            Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:material_ui/material_ui.dart';
import 'package:rohd_wave_viewer/src/const/const.dart';

/// Widget that paints the waveform timescale for the current viewport.
class TimescaleWidget extends StatelessWidget {
  final double _zoomLevel;
  final double _finalTime;
  final double _startTime;
  final double _viewportWidth;
  final double _leftOffset;
  final double _scrollOffset;
  final Color _lineColor;
  final Color? _backgroundColor;

  /// Creates a timescale widget.
  const TimescaleWidget({
    required double zoomLevel,
    required double finalTime,
    required double viewportWidth,
    super.key,
    double startTime = 0.0,
    double leftOffset =
        waveformLeftOffset, // Match SignalTabContainer horizontal padding
    double scrollOffset = 0.0,
    Color lineColor = Colors.blue,
    Color? backgroundColor,
  })  : _zoomLevel = zoomLevel,
        _finalTime = finalTime,
        _viewportWidth = viewportWidth,
        _startTime = startTime,
        _leftOffset = leftOffset,
        _scrollOffset = scrollOffset,
        _lineColor = lineColor,
        _backgroundColor = backgroundColor;

  @override
  Widget build(BuildContext context) {
    // Use viewport width for painting, not the constraint from parent
    final Widget painter = CustomPaint(
      size: Size(_viewportWidth, 60),
      painter: TimescalePainter(
        timeScale: _zoomLevel,
        finalTime: _finalTime,
        startTime: _startTime,
        leftOffset: _leftOffset,
        viewportWidth: _viewportWidth,
        scrollOffset: _scrollOffset,
        lineColor: _lineColor,
      ),
    );

    if (_backgroundColor != null) {
      return ColoredBox(color: _backgroundColor, child: painter);
    }
    return painter;
  }
}

/// Painter that renders timescale ticks and labels for the waveform view.
class TimescalePainter extends CustomPainter {
  /// The unit if the timescale, default to pico seconds
  final String timeUnit;

  /// The zoom level of the painter.
  final double timeScale;

  /// The full timescale duration (total simulation time in ps).
  final double finalTime;

  /// The start time (usually 0 for absolute mapping)
  final double startTime;

  /// Left offset to align with waveform content
  final double leftOffset;

  /// The viewport width (visible area width)
  final double viewportWidth;

  /// Horizontal scroll offset in pixels
  final double scrollOffset;

  /// Color for the timescale lines and labels
  final Color lineColor;

  // ----- Label TextPainter cache -----
  // Labels are deterministic: same text + style → same laid-out TextPainter.
  // We cache per (text, isMajor) to avoid creating dozens of TextPainters
  // every scroll frame.  A static cache with a size cap keeps memory bounded.
  static const int _maxCacheSize = 128;
  static final Map<String, TextPainter> _majorLabelCache = {};
  static final Map<String, TextPainter> _minorLabelCache = {};

  TextPainter _getMajorLabel(String text) {
    final key = '$text@${lineColor.toARGB32()}';
    return _majorLabelCache.putIfAbsent(key, () {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: lineColor,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      if (_majorLabelCache.length > _maxCacheSize) {
        for (final tp in _majorLabelCache.values) {
          tp.dispose();
        }
        _majorLabelCache.clear();
      }
      return tp;
    });
  }

  TextPainter _getMinorLabel(String text) {
    final key = '$text@${lineColor.toARGB32()}';
    return _minorLabelCache.putIfAbsent(key, () {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(color: lineColor, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      if (_minorLabelCache.length > _maxCacheSize) {
        for (final tp in _minorLabelCache.values) {
          tp.dispose();
        }
        _minorLabelCache.clear();
      }
      return tp;
    });
  }

  // ── Pre-allocated Paint objects (avoid per-paint() allocations) ──
  late final Paint _tickPaint = Paint()
    ..color = lineColor
    ..strokeWidth = 1;
  late final Paint _majorTickPaint = Paint()
    ..color = lineColor
    ..strokeWidth = 3;

  /// Creates a timescale painter.
  TimescalePainter({
    required this.timeScale,
    required this.finalTime,
    this.timeUnit = 'ps',
    this.startTime = 0.0,
    this.leftOffset = waveformLeftOffset,
    this.viewportWidth = 0.0,
    this.scrollOffset = 0.0,
    this.lineColor = Colors.blue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Timescale paint logging removed

    final paint = _tickPaint;
    final majorTickPaint = _majorTickPaint;

    // Shifted up to free bottom area for cursor label
    // (+2 breathing room)
    const double initPosY = 12;
    const majorTickHeight = 10;
    const minorTickHeight = 6; // Medium minor ticks
    const labelOffset = 12; // vertical offset for labels above line

    // Use the SAME absolute coordinate mapping as waveform painters:
    // contentX = leftOffset + (time / timescale) * drawingContentWidth
    // where drawingContentWidth = contentWidth - leftOffset - rightPadding
    //       contentWidth = viewportWidth * zoomLevel
    //
    // To convert contentX to viewportX: viewportX = contentX - scrollOffset
    final contentWidth = viewportWidth * timeScale;
    const rightPadding = waveformLeftOffset;
    final drawingContentWidth =
        (contentWidth - leftOffset - rightPadding).clamp(0.0, double.infinity);

    // Helper: convert time (ps) to viewport X coordinate
    double timeToViewportX(double time) {
      if (finalTime <= 0 || drawingContentWidth <= 0) {
        return leftOffset;
      }
      final contentX = leftOffset + (time / finalTime) * drawingContentWidth;
      return contentX - scrollOffset;
    }

    // Drawing area in viewport coordinates
    final viewportDrawStart = leftOffset;
    final viewportDrawEnd = size.width - rightPadding;

    /// Draw the horizontal scale line (from leftOffset to end of viewport)
    canvas.drawLine(
      Offset(viewportDrawStart, initPosY),
      Offset(viewportDrawEnd, initPosY),
      paint,
    );

    // Calculate visible time range from scroll position. Visible content spans
    // [scrollOffset, scrollOffset + viewportWidth] in content coordinates
    // Convert to time: time = ((contentX - leftOffset) / drawingContentWidth) *
    // finalTime.
    double contentXToTime(double contentX) {
      if (drawingContentWidth <= 0 || finalTime <= 0) {
        return 0;
      }
      return ((contentX - leftOffset) / drawingContentWidth) * finalTime;
    }

    final visibleStartTime = contentXToTime(scrollOffset).clamp(0.0, finalTime);
    final visibleEndTime = contentXToTime(
      scrollOffset + viewportWidth,
    ).clamp(0.0, finalTime);
    final visibleTimeRange = visibleEndTime - visibleStartTime;

    // Target: ~10 major ticks on screen
    const targetMajorTicks = 10;

    // Choose a "nice" major interval from the sequence {1,2,5} * 10^n Do
    // interval math in integer picoseconds to avoid floating rounding artifacts
    int chooseNiceIntervalPs(double rough) {
      // Integer-only "nice" chooser. Input `rough` is in picoseconds (may be
      // fractional), but we work with integer powers-of-ten and multipliers
      // {1,2,5,10}.
      if (rough <= 0) {
        return 1;
      }
      // Convert rough to integer ps (ceil to avoid undersizing)
      final r = rough.ceil();

      // Determine power of ten base (pow10) as largest power of 10 <= r
      var pow10 = 1;
      while (pow10 * 10 <= r) {
        pow10 *= 10;
      }

      // Try multipliers 1,2,5,10 against pow10 to find the smallest >= r
      final m1 = pow10 * 1;
      final m2 = pow10 * 2;
      final m5 = pow10 * 5;
      final m10 = pow10 * 10;

      if (r <= m1) {
        return m1;
      }
      if (r <= m2) {
        return m2;
      }
      if (r <= m5) {
        return m5;
      }
      return m10;
    }

    // Work in integer picoseconds for tick generation
    // Use visible time range for calculating tick intervals
    final visibleStartPs = visibleStartTime.round();
    final visibleEndPs = visibleEndTime.round();
    final visibleRangePs = visibleTimeRange.round();

    // Compute rough interval based on VISIBLE time range
    final roughInterval = visibleRangePs / targetMajorTicks;

    final majorIntervalPs = chooseNiceIntervalPs(roughInterval);
    // Measure actual major label widths (more accurate than conservative
    // estimate)
    const minLabelSpacing =
        2; // Minimum gap between labels (reduced to avoid clipping)

    // Compute first major/minor tick in integer picoseconds (round up to next
    // interval) Start from visible range, but align to interval boundaries for
    // consistency
    final firstMajorTickPs =
        (visibleStartPs ~/ majorIntervalPs) * majorIntervalPs;

    // Gather major tick times (in picoseconds) across full timeline
    // but we'll only draw those within visible range
    final totalTimePs = finalTime.round();
    final majorTimesPs = <int>[];
    for (var t = firstMajorTickPs;
        t <= visibleEndPs + majorIntervalPs;
        t += majorIntervalPs) {
      if (t >= 0 && t <= totalTimePs) {
        majorTimesPs.add(t);
      }
    }
    // Extra diagnostics for small intervals (help reproduce 1ns/5ns anomaly)
    // (Additional verbose diagnostics removed)

    // --- Use label cache instead of creating fresh TextPainters ---
    // Measure max major label width from cache
    var maxMeasuredMajorWidth = 0.0;
    for (final t in majorTimesPs) {
      final tp = _getMajorLabel(_formatTimeLabel(t, majorIntervalPs));
      if (tp.width > maxMeasuredMajorWidth) {
        maxMeasuredMajorWidth = tp.width;
      }
    }

    // Always prefer showing major labels; minors will collapse first when
    // space is tight.

    // Precompute which major labels will actually be drawn (so minors can refer
    // to them) Record fields: (x, left, right, textPainter)
    final drawnMajors = <(double, double, double, TextPainter)>[];
    var precomputeLastMajorRight = -1000000000000.0;
    // Iterate precomputed integer picosecond major times
    for (final t in majorTimesPs) {
      final absoluteTime = t.toDouble();
      final x = timeToViewportX(absoluteTime);
      // Skip ticks that fall outside the visible drawing area
      if (x < viewportDrawStart || x > viewportDrawEnd) {
        continue;
      }
      final tp = _getMajorLabel(_formatTimeLabel(t, majorIntervalPs));
      final labelLeft = x - tp.width / 2;
      final labelRight = x + tp.width / 2;
      if (labelLeft > precomputeLastMajorRight + minLabelSpacing) {
        drawnMajors.add((x, labelLeft, labelRight, tp));
        precomputeLastMajorRight = labelRight;
      }
    }
    // Ensure first and last visible major labels are present for orientation
    if (majorTimesPs.isNotEmpty) {
      final firstT = majorTimesPs.first;
      final lastT = majorTimesPs.last;
      final firstX = timeToViewportX(firstT.toDouble());
      final lastX = timeToViewportX(lastT.toDouble());
      final hasFirst = drawnMajors.any((m) => m.$1 == firstX);
      final hasLast = drawnMajors.any((m) => m.$1 == lastX);
      if (!hasFirst &&
          firstX >= viewportDrawStart &&
          firstX <= viewportDrawEnd) {
        final tp = _getMajorLabel(_formatTimeLabel(firstT, majorIntervalPs));
        final labelLeft = firstX - tp.width / 2;
        final labelRight = firstX + tp.width / 2;
        drawnMajors.insert(0, (firstX, labelLeft, labelRight, tp));
      }
      if (!hasLast && lastX >= viewportDrawStart && lastX <= viewportDrawEnd) {
        final tp = _getMajorLabel(_formatTimeLabel(lastT, majorIntervalPs));
        final labelLeft = lastX - tp.width / 2;
        final labelRight = lastX + tp.width / 2;
        drawnMajors.add((lastX, labelLeft, labelRight, tp));
      }
    }

    // Place exactly one minor tick at the midpoint between each pair of
    // drawn major ticks.  This avoids the "two unnecessary minors" problem
    // (e.g. 8.376ns + 8.378ns) and instead shows a single label like 8.3775ns.
    // We also add a minor before the first major and after the last if they
    // fall within the visible area.
    final minorMidpoints = <(double, double)>[]; // (x, timePs)
    // Add midpoint before first drawn major (using majorIntervalPs)
    if (drawnMajors.isNotEmpty) {
      final firstMajorTime =
          (drawnMajors.first.$1 + scrollOffset - leftOffset) /
              drawingContentWidth *
              finalTime;
      final prevTime = firstMajorTime - majorIntervalPs;
      final midTime = (prevTime + firstMajorTime) / 2;
      final midX = timeToViewportX(midTime);
      if (midX >= viewportDrawStart &&
          midX <= viewportDrawEnd &&
          midTime >= 0) {
        minorMidpoints.add((midX, midTime));
      }
    }
    // Add midpoints between consecutive drawn majors
    for (var i = 0; i < drawnMajors.length - 1; i++) {
      final x1 = drawnMajors[i].$1;
      final x2 = drawnMajors[i + 1].$1;
      final midX = (x1 + x2) / 2;
      // Compute the time at the midpoint
      final t1 =
          (x1 + scrollOffset - leftOffset) / drawingContentWidth * finalTime;
      final t2 =
          (x2 + scrollOffset - leftOffset) / drawingContentWidth * finalTime;
      final midTime = (t1 + t2) / 2;
      if (midX >= viewportDrawStart && midX <= viewportDrawEnd) {
        minorMidpoints.add((midX, midTime));
      }
    }
    // Add midpoint after last drawn major
    if (drawnMajors.isNotEmpty) {
      final lastMajorTime = (drawnMajors.last.$1 + scrollOffset - leftOffset) /
          drawingContentWidth *
          finalTime;
      final nextTime = lastMajorTime + majorIntervalPs;
      final midTime = (lastMajorTime + nextTime) / 2;
      final midX = timeToViewportX(midTime);
      if (midX >= viewportDrawStart &&
          midX <= viewportDrawEnd &&
          midTime <= totalTimePs) {
        minorMidpoints.add((midX, midTime));
      }
    }

    // The minor interval for formatting purposes is half the major interval
    final minorIntervalForFormat = (majorIntervalPs + 1) ~/ 2;

    for (final (midX, midTime) in minorMidpoints) {
      // Draw minor tick mark
      canvas.drawLine(
        Offset(midX, initPosY),
        Offset(midX, initPosY + minorTickHeight),
        paint,
      );

      final tp = _getMinorLabel(
        _formatTimeLabel(midTime.round(), minorIntervalForFormat),
      );

      // Place minor labels below the scale line
      const yOffset = initPosY + 5;
      final labelLeft = midX - tp.width / 2;

      // Skip if overlaps any major label
      var overlaps = false;
      for (final m in drawnMajors) {
        if (labelLeft < m.$3 + minLabelSpacing &&
            labelLeft + tp.width > m.$2 - minLabelSpacing) {
          overlaps = true;
          break;
        }
      }
      if (overlaps) {
        continue;
      }

      tp.paint(canvas, Offset(labelLeft, yOffset));
    }

    // Draw major ticks LAST (on top of minor ticks) using precomputed
    // drawnMajors
    for (final m in drawnMajors) {
      // Draw major tick mark
      canvas.drawLine(
        Offset(m.$1, initPosY),
        Offset(m.$1, initPosY + majorTickHeight),
        majorTickPaint,
      );
      const yOffset = initPosY - labelOffset;
      m.$4.paint(canvas, Offset(m.$2, yOffset));
    }
  }

  /// Format a time value (in ps) as a human-readable label.
  ///
  /// [intervalPs] is the tick spacing in ps.  We use enough decimal places
  /// so that adjacent ticks produce *different* label strings, e.g.
  /// 9440ps and 9445ps → "9.440ns" / "9.445ns" instead of both "9.44ns".
  String _formatTimeLabel(int value, [int intervalPs = 0]) {
    if (value == 0) {
      return '0ps';
    }
    final v = value.toDouble();
    String unit;
    double divisor;
    if (v.abs() >= 1e9) {
      unit = 's';
      divisor = 1e9;
    } else if (v.abs() >= 1e6) {
      unit = 'ms';
      divisor = 1e6;
    } else if (v.abs() >= 1e3) {
      unit = 'ns';
      divisor = 1e3;
    } else {
      unit = 'ps';
      divisor = 1;
    }
    final displayVal = v / divisor;

    // Determine minimum decimals needed so that the interval is visible
    // in the formatted string.  E.g. interval 5ps with divisor 1000
    // → intervalInUnit = 0.005 → need 3 decimals.
    var minDecimals = 0;
    if (intervalPs > 0 && divisor > 1) {
      final intervalInUnit = intervalPs / divisor;
      // Find how many decimals to represent the interval
      var threshold = 1.0;
      for (var d = 1; d <= 9; d++) {
        threshold /= 10.0;
        if (intervalInUnit >= threshold * 0.99) {
          minDecimals = d;
          break;
        }
      }
    }

    // Default decimals based on magnitude
    int defaultDecimals;
    final ax = displayVal.abs();
    if (ax >= 100) {
      defaultDecimals = 0;
    } else if (ax >= 10) {
      defaultDecimals = 1;
    } else {
      defaultDecimals = 2;
    }

    final decimals =
        minDecimals > defaultDecimals ? minDecimals : defaultDecimals;
    var s = displayVal.toStringAsFixed(decimals);

    // Strip trailing zeros, but keep at least one digit after the decimal
    // point when there is a decimal.
    if (decimals > minDecimals) {
      // We can strip zeros down to minDecimals places
      while (s.endsWith('0')) {
        s = s.substring(0, s.length - 1);
      }
      if (s.endsWith('.')) {
        s = s.substring(0, s.length - 1);
      }
    }

    return '$s$unit';
  }

  @override
  bool shouldRepaint(covariant TimescalePainter oldDelegate) =>
      oldDelegate.timeScale != timeScale ||
      oldDelegate.finalTime != finalTime ||
      oldDelegate.startTime != startTime ||
      oldDelegate.leftOffset != leftOffset ||
      oldDelegate.viewportWidth != viewportWidth ||
      oldDelegate.scrollOffset != scrollOffset ||
      oldDelegate.lineColor != lineColor;
}
