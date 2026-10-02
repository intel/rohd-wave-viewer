// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// waveform.dart
// Abstract class for waveform painters.
//
// 2024 April
// Author(s): Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
//            Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:material_ui/material_ui.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd_wave_viewer/src/const/const.dart';
import 'package:rohd_wave_viewer/src/viewer_waveform_client.dart';

/// Base painter for waveform rows.
abstract class Waveform extends CustomPainter {
  // --- Debug flag: set to true to completely suppress all label rendering ---
  // This bypasses label computation, text measurement, fitLabelToWidth,
  // AND the scroll-settle repaint that re-enables labels.  Use this to
  // isolate whether the jerkiness is from waveform geometry alone or
  // from text/label overhead.
  /// Whether all label rendering should be suppressed for debugging.
  static bool debugSuppressLabels = false;

  // --- Performance option: defer labels while scrolling ---
  // false (default): labels are baked into strip tiles and scroll with
  // waveform.
  // true: labels are omitted from strip tiles during scroll and repainted in
  // a separate overlay pass after scroll settles.
  /// Whether labels should be deferred while scrolling.
  static bool deferLabelsWhileScrolling = false;

  // --- Static caches shared across all waveform painter instances ---
  static bool _isDecimalDigit(int codeUnit) =>
      codeUnit >= 0x30 && codeUnit <= 0x39;

  static bool _hasRadixPrefix(String value) {
    final apostrophe = value.indexOf("'");
    if (apostrophe <= 0 || apostrophe + 1 >= value.length) {
      return false;
    }
    for (var index = 0; index < apostrophe; index++) {
      if (!_isDecimalDigit(value.codeUnitAt(index))) {
        return false;
      }
    }
    return 'bqodh'.contains(value[apostrophe + 1]);
  }

  static int? _hexRadixPrefixEnd(String value) {
    final apostrophe = value.indexOf("'");
    if (apostrophe <= 0 ||
        apostrophe + 1 >= value.length ||
        value[apostrophe + 1] != 'h') {
      return null;
    }
    for (var index = 0; index < apostrophe; index++) {
      if (!_isDecimalDigit(value.codeUnitAt(index))) {
        return null;
      }
    }
    return apostrophe + 2;
  }

  static bool _isBinaryValue(String value) =>
      value.isNotEmpty &&
      value.codeUnits.every((codeUnit) => codeUnit == 0x30 || codeUnit == 0x31);

  static bool _containsUnknownDigits(String value) {
    final lower = value.toLowerCase();
    final apostrophe = lower.indexOf("'");
    final digits = apostrophe > 0 && apostrophe + 2 <= lower.length
        ? lower.substring(apostrophe + 2)
        : lower.startsWith('0x') || lower.startsWith('0b')
            ? lower.substring(2)
            : lower;
    return digits.contains('x') || digits.contains('z');
  }

  /// Formats a normalized waveform value for a monitor row.
  static String formatValueForDisplay(
    String value,
    MonitorValueFormat valueFormat,
    int width,
  ) {
    final lower = value.toLowerCase();
    if (_containsUnknownDigits(lower)) {
      return value;
    }
    BigInt? numeric;
    final apostrophe = lower.indexOf("'");
    if (apostrophe > 0 && apostrophe + 1 < lower.length) {
      final radix = switch (lower[apostrophe + 1]) {
        'b' => 2,
        'o' || 'q' => 8,
        'd' => 10,
        'h' => 16,
        _ => null,
      };
      if (radix != null) {
        numeric = BigInt.tryParse(
          lower.substring(apostrophe + 2),
          radix: radix,
        );
      }
    } else if (lower.startsWith('0x')) {
      numeric = BigInt.tryParse(lower.substring(2), radix: 16);
    } else if (lower.startsWith('0b')) {
      numeric = BigInt.tryParse(lower.substring(2), radix: 2);
    } else {
      numeric = BigInt.tryParse(lower, radix: _isBinaryValue(lower) ? 2 : 10);
    }
    if (numeric == null) {
      return value;
    }

    final displayWidth = width > 0 ? width : 1;
    final byteCount = ((displayWidth + 7) ~/ 8).clamp(1, 32);
    return switch (valueFormat) {
      MonitorValueFormat.waveform =>
        LogicValue.ofBigInt(numeric, displayWidth).toString(),
      MonitorValueFormat.binary =>
        numeric.toRadixString(2).padLeft(displayWidth, '0'),
      MonitorValueFormat.hexadecimal =>
        LogicValue.ofBigInt(numeric, displayWidth).toString(),
      MonitorValueFormat.unsignedDecimal => numeric.toString(),
      MonitorValueFormat.signedDecimal =>
        (numeric >= (BigInt.one << (displayWidth - 1))
                ? numeric - (BigInt.one << displayWidth)
                : numeric)
            .toString(),
      MonitorValueFormat.octal => '0o${numeric.toRadixString(8)}',
      MonitorValueFormat.ascii => String.fromCharCodes(
          List<int>.generate(
            byteCount,
            (index) {
              final shift = (byteCount - index - 1) * 8;
              final codeUnit =
                  ((numeric! >> shift) & BigInt.from(0xff)).toInt();
              return codeUnit >= 0x20 && codeUnit <= 0x7e ? codeUnit : 0x2e;
            },
          ),
        ),
    };
  }

  // TextPainter label cache keyed by (text, fontSize, colorValue).
  // Sized to cover visible labels across all signal rows.
  // With direct paint (no toImageSync), labels are repainted every frame;
  // a warm cache avoids TextPainter allocation and Paragraph layout.
  // 256 entries ≈ ~1 frame of visible labels across all signal rows.
  // Kept small to prevent V8 old-gen promotion of long-lived entries
  // which triggers incremental-marking GC stalls.  On overflow, all
  // entries are disposed and the cache is cleared.  Explicit dispose()
  // releases underlying CanvasKit SkParagraph WASM objects immediately.
  static const int _maxLabelCache = 256;
  static final Map<int, TextPainter> _labelCache = {};

  // Cache for formatValueAsHexLabel results.  During scroll, the same raw
  // values are re-formatted every frame; caching avoids BigInt.tryParse /
  // toRadixString which together cost ~1.7% CPU (the _mulAdd + _parseRadix
  // hotspots in the profiler trace).
  // Sized small (256) to prevent promoted strings from triggering V8
  // incremental marking.  With pixel-sampling LOD, far fewer unique
  // values are formatted per frame than the raw transition count.
  static const int _maxHexFormatCache = 256;
  static final Map<String, String> _hexFormatCache = {};

  // Cache for fitLabelToWidth results.  Keyed by (label, widthBucket, color).
  // During scroll at fixed zoom, the same labels appear at the same widths,
  // giving near-100% hit rate and eliminating the binary search entirely
  // on subsequent frames.  Sized to match _maxLabelCache.
  static const int _maxFitResultCache = 256;
  static final Map<int, TextPainter?> _fitResultCache = {};

  // Reusable TextPainter for width measurement during fitLabelToWidth
  // binary search.  Avoids creating + caching intermediate TextPainters
  // that pollute _labelCache and trigger thrashing (the #1 cause of
  // cold-cache every frame when zoomed out with text shortening).
  static final TextPainter _measurePainter = TextPainter(
    textDirection: TextDirection.ltr,
  );

  /// Get (or create+layout) a cached TextPainter for the given label.
  static TextPainter getCachedLabel(
    String text,
    double fontSize,
    Color color, {
    FontWeight? fontWeight,
  }) {
    // Use a cheap composite key.  The old `Object.hash(text, fontSize,
    // color.toARGB32(), fontWeight)` call triggered the top-1 SDK hotspot
    // (hashCode at 2.4% combined CPU).  We now build an integer key
    // directly from the components, avoiding hash-of-hash overhead.
    //
    // Layout: bits [63..32] = color ARGB32
    //         bits [31..16] = text.hashCode (truncated to 16 bits)
    //         bits [15..8]  = fontSize * 4 (enough for 0-63.75)
    //         bits [7..0]   = fontWeight index (0-8) + 1, or 0 for null
    final colorVal = color.toARGB32();
    final textHash = text.hashCode;
    final fwIdx =
        fontWeight != null ? FontWeight.values.indexOf(fontWeight) + 1 : 0;
    // Combine into a single int key.  On JS (53-bit ints) we use XOR
    // for the upper 32 bits to stay in safe integer range.
    final key = (textHash ^ (colorVal * 0x10001)) +
        ((fontSize * 4).toInt() << 8) +
        fwIdx;
    return _labelCache.putIfAbsent(key, () {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: fontWeight,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      if (_labelCache.length > _maxLabelCache) {
        // Dispose all TextPainters to release underlying CanvasKit
        // SkParagraph WASM objects immediately.  Without dispose(),
        // these linger until V8 GC finalization, causing massive
        // GC_MC_BACKGROUND_MARKING stalls (2+ seconds observed in
        // Trace-paint-fix.gz with 21k GC events vs 4.5k baseline).
        for (final oldTp in _labelCache.values) {
          oldTp.dispose();
        }
        _labelCache.clear();
        // _fitResultCache values reference the same TextPainters
        // (now disposed).  Clear to prevent use-after-dispose.
        _fitResultCache.clear();
      }
      return tp;
    });
  }

  /// Try to fit a hex label into the available pixel width by progressively
  /// truncating. Returns the TextPainter for the best-fit string, or null
  /// if even the shortest abbreviation doesn't fit.
  ///
  /// Truncation scheme for a label like `0xA0000000174`:
  ///   1. Full label: `0xA0000000174`
  ///   2. Keep `0x` + first 2 hex digits + `..` + last N digits, shrinking N:
  ///      `0xA0..000174` → `0xA0..0174` → ... → `0xA0..74`
  ///   3. If `0xDD..DD` (8 chars min) doesn't fit, return null.
  ///
  /// Results are cached in [_fitResultCache] so that during scroll at fixed
  /// zoom (same label + same width), the binary search is skipped entirely.
  /// Intermediate truncation probes use [_measurePainter] (a single reusable
  /// TextPainter) to avoid polluting [_labelCache] with entries that are
  /// never painted — this was the #1 cause of cache thrashing (256-entry
  /// cache overflowed and cleared every frame when 24 signals × 6 probes
  /// each = ~1440 entries).
  static TextPainter? fitLabelToWidth(
    String label,
    double availableWidth,
    double fontSize,
    Color color,
  ) {
    // Fast path: check fit-result cache (label + width bucket + color).
    // Width is bucketed to nearest integer so sub-pixel scroll jitter
    // doesn't fragment the cache.
    final widthBucket = availableWidth.toInt();
    final fitKey = label.hashCode ^
        (widthBucket * 0x9E3779B9) ^
        (color.toARGB32() * 0x10001);
    final cachedResult = _fitResultCache[fitKey];
    // Use containsKey because the cached value can be null (= doesn't fit).
    if (_fitResultCache.containsKey(fitKey)) {
      return cachedResult;
    }

    final result = _fitLabelToWidthImpl(label, availableWidth, fontSize, color);

    // Store result (may be null)
    if (_fitResultCache.length >= _maxFitResultCache) {
      _fitResultCache.clear();
    }
    _fitResultCache[fitKey] = result;
    return result;
  }

  /// Core implementation of fitLabelToWidth (uncached).
  static TextPainter? _fitLabelToWidthImpl(
    String label,
    double availableWidth,
    double fontSize,
    Color color,
  ) {
    // Try full label first.
    final fullTp = getCachedLabel(label, fontSize, color);
    if (fullTp.width <= availableWidth) {
      return fullTp;
    }

    // Only truncate hex labels — radixString (e.g. 16'hfffe) or legacy 0x.
    final tickHEnd = _hexRadixPrefixEnd(label);
    if (tickHEnd == null &&
        !label.startsWith('0x') &&
        !label.startsWith('0X')) {
      return null;
    }
    // Extract the hex portion after the prefix.
    final String prefix0;
    final String hexDigits;
    if (tickHEnd != null) {
      prefix0 = label.substring(0, tickHEnd);
      hexDigits = label.substring(tickHEnd).replaceAll('_', '');
    } else {
      prefix0 = label.substring(0, 2); // '0x'
      hexDigits = label.substring(2);
    }
    // Need at least 7 hex digits for truncation to produce something
    // shorter than the full label.
    // Minimum abbreviation: 0xDD..DD = 2+2+2+2 = 8 chars.
    // Full label with 7 hex digits = 0x + 7 = 9 chars > 8.
    if (hexDigits.length < 7) {
      return null;
    }

    // Keep first 2 hex digits + ".." separator.
    final first2 = hexDigits.substring(0, 2);
    final prefix = '$prefix0$first2..';

    // Check minimum truncation first (2 trailing digits) using the
    // reusable measurement painter to avoid cache pollution.
    final minSuffix = hexDigits.substring(hexDigits.length - 2);
    final minAbbrev = '$prefix$minSuffix';
    _measurePainter.text = TextSpan(
      text: minAbbrev,
      style: TextStyle(color: color, fontSize: fontSize),
    );
    _measurePainter.layout();
    if (_measurePainter.width > availableWidth) {
      return null;
    }

    // Binary search for the longest suffix that still fits.
    // Use _measurePainter for all probes — only getCachedLabel the winner.
    var lo = 2;
    var hi = hexDigits.length - 2;
    var bestSuffixLen = 2; // minimum always fits (checked above)
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1; // ceiling to converge
      final suffix = hexDigits.substring(hexDigits.length - mid);
      final abbreviated = '$prefix$suffix';
      // Skip if abbreviation isn't actually shorter than the full label.
      if (abbreviated.length >= label.length) {
        hi = mid - 1;
        continue;
      }
      _measurePainter.text = TextSpan(
        text: abbreviated,
        style: TextStyle(color: color, fontSize: fontSize),
      );
      _measurePainter.layout();
      if (_measurePainter.width <= availableWidth) {
        bestSuffixLen = mid;
        lo = mid; // try longer suffix
      } else {
        hi = mid - 1; // try shorter suffix
      }
    }

    // Only cache the winning label string (not intermediates).
    final bestSuffix = hexDigits.substring(hexDigits.length - bestSuffixLen);
    final bestAbbrev = '$prefix$bestSuffix';
    return getCachedLabel(bestAbbrev, fontSize, color);
  }

  /// Dispose and clear all static caches.
  ///
  /// Call when the scale factor changes (or any configuration that
  /// invalidates cached TextPainters / fit results).
  static void clearCaches() {
    for (final tp in _labelCache.values) {
      tp.dispose();
    }
    _labelCache.clear();
    _hexFormatCache.clear();
    _fitResultCache.clear();
  }

  /// Snap an X coordinate to the nearest half-pixel so that vertical
  /// strokes of `strokeWidth = 2.0` land on exact pixel boundaries.
  /// A 2px stroke centered on X.0 covers [X-1, X+1] — two full pixels.
  static double snapX(double x) => x.roundToDouble();

  /// Zero-allocation colour classification: 0=green, 1=red(x), 2=yellow(z).
  ///
  /// Replaces `.toLowerCase().contains('x'/'z')` which allocates a new
  /// String on every call — 12 500+ Strings/frame across 25 signals.
  static int colorIdxOf(String value) {
    for (var i = 0; i < value.length; i++) {
      final c = value.codeUnitAt(i);
      if (c == 0x78 || c == 0x58) {
        return 1; // x/X
      }
      if (c == 0x7A || c == 0x5A) {
        return 2; // z/Z
      }
    }
    return 0;
  }

  /// Like [colorIdxOf] but skips a leading `0x`/`0X` prefix so that
  /// the literal hex-prefix character is not mistaken for an unknown 'x'.
  static int colorIdxOfHex(String value) {
    var start = 0;
    if (value.length > 2 &&
        value.codeUnitAt(0) == 0x30 && // '0'
        (value.codeUnitAt(1) == 0x78 || value.codeUnitAt(1) == 0x58)) {
      start = 2;
    }
    for (var i = start; i < value.length; i++) {
      final c = value.codeUnitAt(i);
      if (c == 0x78 || c == 0x58) {
        return 1; // x/X
      }
      if (c == 0x7A || c == 0x5A) {
        return 2; // z/Z
      }
    }
    return 0;
  }

  // ── Direct-to-screen label rendering ───────────────────────────────
  // When true, paint() skips text labels so they aren't baked into the
  // off-screen raster cache.  The labels are stored in _pendingLabels
  // and painted directly to the screen canvas by paintStoredLabels().
  /// Whether label painting should be skipped for the current pass.
  bool skipLabels = false;

  /// Lightweight label collection for the overlay pass.
  ///
  /// Iterates the signal's data points, computes which segments are
  /// visible and wide enough, formats each label, and stores it for painting
  /// — without touching Canvas or building any Path geometry.
  ///
  /// Subclasses may override (for example, `WaveformBinary` skips single-bit
  /// signals that never carry labels).
  void collectLabelsForViewport(double contentWidth, double rowHeight) {
    final left = leftOffset;
    final rightPadding = left;
    final drawingWidth = (contentWidth - left - rightPadding).clamp(
      0.0,
      double.infinity,
    );

    final effectiveTimescale = (timescale > 0) ? timescale : finalTime;
    if (effectiveTimescale <= 0 || drawingWidth <= 0) {
      return;
    }

    final pxPerTime = drawingWidth / effectiveTimescale;

    // Reuse pre-computed visible time bounds when available.
    final (int visMinTime, int visMaxTime) = preVisMinTime != null
        ? (preVisMinTime!, preVisMaxTime!)
        : visibleTimeBoundsFor(
            contentWidth,
            liveScrollOffset,
            liveViewportWidth,
          );

    // Y geometry — matches both hex and binary multi-bit painters.
    const yInset = 1.0;
    const topY = yInset;
    final bottomY = rowHeight - yInset;
    const halfConn = 3.0; // ramp half-width (identical in both painters)

    if (waveform.isEmpty) {
      return;
    }

    var currentValue = waveform.first.value;
    var segStart = 0;

    for (var idx = 1; idx < waveform.length; idx++) {
      final d = waveform[idx];
      if (d.time < 0) {
        continue;
      }
      if (d.time > effectiveTimescale) {
        break;
      }
      if (d.value == currentValue) {
        continue;
      }

      _storeLabelForSegment(
        segStart,
        d.time,
        currentValue,
        left,
        pxPerTime,
        visMinTime,
        visMaxTime,
        halfConn,
        topY,
        bottomY,
      );
      segStart = d.time;
      currentValue = d.value;
    }
    // Final segment — extend past effectiveTimescale so labels on the
    // last crossing are visible (painters clip drawing at endTime).
    if (segStart < effectiveTimescale) {
      _storeLabelForSegment(
        segStart,
        effectiveTimescale,
        currentValue,
        left,
        pxPerTime,
        visMinTime,
        visMaxTime,
        halfConn,
        topY,
        bottomY,
      );
    }
  }

  /// Store a label for one segment if it is visible and wide enough.
  void _storeLabelForSegment(
    int segStart,
    int segEnd,
    String value,
    double left,
    double pxPerTime,
    int visMinTime,
    int visMaxTime,
    double halfConn,
    double topY,
    double bottomY,
  ) {
    if (segEnd < visMinTime || segStart > visMaxTime) {
      return;
    }

    final startX = left + segStart * pxPerTime;
    final endX = left + segEnd * pxPerTime;
    if (endX - startX < 20.0) {
      return; // matches painters' 20-px threshold
    }

    final railSx = startX + halfConn;
    final railEx = endX - halfConn;
    final available = railEx - railSx - 2.0;
    if (available < 10.0) {
      return;
    }

    final label = formatValueAsHexLabel(value);
    final fs = scaledFontSize(bottomY + 1.0); // bottomY = rowHeight - 1
    final tp = Waveform.fitLabelToWidth(
      label,
      available,
      fs,
      effectiveLabelTextColor,
    );
    if (tp == null) {
      return;
    }

    final textY = ((topY + bottomY) / 2 - tp.height / 2).roundToDouble();
    storeLabel(tp, railSx, railEx, textY, label);
  }

  /// Each stored label keeps the segment bounds and the original label
  /// string so that [paintEdgeLabels] can re-centre the text within
  /// the *visible* intersection of the segment with the viewport, and
  /// re-truncate the label when the segment scrolls partially off-screen.
  ///
  /// Fields: (TextPainter, segStartX, segEndX, textY, originalLabel)
  /// All X coordinates are in content space.
  final List<(TextPainter, double, double, double, String)> _pendingLabels = [];

  /// Record a label together with its segment's content-space X range
  /// and the original (untruncated) label string.
  void storeLabel(
    TextPainter tp,
    double segStartX,
    double segEndX,
    double y,
    String label,
  ) {
    _pendingLabels.add((tp, segStartX, segEndX, y, label));
  }

  /// Paint all stored labels directly to [canvas] using stable
  /// full-rail centering (position depends only on segment bounds,
  /// not on the viewport).
  ///
  /// The canvas must already have `translate(-scrollOffset, 0)` applied
  /// so that content-space coordinates map to screen coordinates.
  ///
  /// [scrollOffset] and [vpWidth] define the viewport used for culling.
  ///
  /// Viewport-edge centering (abbreviation + centering within the
  /// visible intersection) is handled separately by [paintEdgeLabels],
  /// which should be called *after* this method (or after a GPU-cache
  /// blit) on every frame.
  void paintStoredLabels(Canvas canvas, double scrollOffset, double vpWidth) {
    if (_pendingLabels.isEmpty) {
      return;
    }

    final vpEnd = scrollOffset + vpWidth;
    final bgPaint = labelBgPaint;

    for (final (tp, segSx, segEx, y, _) in _pendingLabels) {
      if (segEx <= scrollOffset || segSx >= vpEnd) {
        continue;
      }

      // Centre within the full segment rail (scroll-invariant).
      final railW = segEx - segSx;
      var drawX = segSx + (railW - tp.width) / 2.0;
      if (drawX < segSx) {
        drawX = segSx;
      }
      if (drawX + tp.width > segEx) {
        drawX = segEx - tp.width;
      }

      // Snap to integer screen pixel.
      final screenX = (drawX - scrollOffset).roundToDouble();
      final snappedX = screenX + scrollOffset;

      if (bgPaint != null) {
        canvas.drawRect(
          Rect.fromLTRB(
            snappedX - 1,
            y,
            snappedX + tp.width + 1,
            y + tp.height,
          ),
          bgPaint,
        );
      }
      tp.paint(canvas, Offset(snappedX, y));
    }
  }

  /// Paint edge-centred labels for segments clipped by the viewport.
  ///
  /// Call after [paintStoredLabels] (or after a GPU-cache blit) to add
  /// viewport-aware centering for the 1–2 labels per row whose segment
  /// straddles a viewport edge.  This runs per-frame so it always
  /// reflects the current scroll position.
  ///
  /// For each edge label:
  /// 1. A cover rect (using [labelBgPaint]) hides the full-rail-centred
  ///    version already on the canvas.
  /// 2. The label is re-truncated via [fitLabelToWidth] to fit the
  ///    visible intersection of the segment with the viewport.
  /// 3. The abbreviated label is centred within that intersection.
  /// 4. When the visible space is too narrow for even the shortest
  ///    abbreviation, no text is drawn (the cover rect still hides the
  ///    stale full-width version).
  ///
  /// The canvas must already have `translate(-scrollOffset, 0)` applied.
  void paintEdgeLabels(
    Canvas canvas,
    double scrollOffset,
    double vpWidth, {
    double? rowHeight,
  }) {
    if (_pendingLabels.isEmpty) {
      return;
    }

    final vpEnd = scrollOffset + vpWidth;
    final bgPaint = labelBgPaint;
    final txtColor = effectiveLabelTextColor;

    for (final (tp, segSx, segEx, y, label) in _pendingLabels) {
      // Only process labels whose segment crosses a viewport edge.
      final crossesLeft = segSx < scrollOffset && segEx > scrollOffset;
      final crossesRight = segSx < vpEnd && segEx > vpEnd;
      if (!crossesLeft && !crossesRight) {
        continue;
      }

      // Visible intersection of segment with viewport.
      final visSx = segSx < scrollOffset ? scrollOffset : segSx;
      final visEx = segEx > vpEnd ? vpEnd : segEx;
      final visW = visEx - visSx;

      // ── Cover the cached full-rail-centred label ──────────────────
      if (bgPaint != null) {
        final railW = segEx - segSx;
        var cachedX = segSx + (railW - tp.width) / 2.0;
        if (cachedX < segSx) {
          cachedX = segSx;
        }
        if (cachedX + tp.width > segEx) {
          cachedX = segEx - tp.width;
        }
        // Cover visible portion of cached label bg (+2 px for rounding).
        final cL = (cachedX - 2.0).clamp(visSx, visEx);
        final cR = (cachedX + tp.width + 2.0).clamp(visSx, visEx);
        if (cR > cL) {
          canvas.drawRect(Rect.fromLTRB(cL, y, cR, y + tp.height), bgPaint);
        }
      }

      // Not enough visible space for any text.
      if (visW < 10.0) {
        continue;
      }

      // ── Re-truncate to fit visible width ──────────────────────────
      final narrowAvail = visW - 2.0; // 1 px pad each side
      TextPainter? activeTp;
      if (tp.width <= narrowAvail) {
        activeTp = tp;
      } else if (narrowAvail >= 10.0) {
        activeTp = Waveform.fitLabelToWidth(
          label,
          narrowAvail,
          Waveform.scaledFontSize(rowHeight ?? baseSignalRowHeight),
          txtColor,
        );
      }
      if (activeTp == null) {
        continue;
      }

      // ── Centre within visible intersection ────────────────────────
      var drawX = visSx + (visW - activeTp.width) / 2.0;
      if (drawX < visSx) {
        drawX = visSx;
      }
      if (drawX + activeTp.width > visEx) {
        drawX = visEx - activeTp.width;
      }

      // Snap to integer screen pixel.
      final screenX = (drawX - scrollOffset).roundToDouble();
      final snappedX = screenX + scrollOffset;

      if (snappedX < visSx - 0.5 || snappedX + activeTp.width > visEx + 0.5) {
        continue;
      }

      if (bgPaint != null) {
        canvas.drawRect(
          Rect.fromLTRB(
            snappedX - 1,
            y,
            snappedX + activeTp.width + 1,
            y + activeTp.height,
          ),
          bgPaint,
        );
      }
      activeTp.paint(canvas, Offset(snappedX, y));
    }
  }

  /// Clear stored labels before a new recording pass.
  void clearStoredLabels() {
    _pendingLabels.clear();
  }

  /// Whether there are stored labels waiting to be painted.
  bool get hasStoredLabels => _pendingLabels.isNotEmpty;

  // Theme-aware colors (initialized in constructor)
  /// Paint used for normal signal segments.
  late final Paint greenPaint;

  /// Paint used for `x` signal segments.
  late final Paint redPaint;

  /// Paint used for `z` signal segments.
  late final Paint yellowPaint;

  // Color values for text styling
  /// Color used for normal signal rendering.
  final Color signalColor;

  /// Color used for `x` signal values.
  final Color xColor;

  /// Color used for `z` signal values.
  final Color zColor;

  /// Color used for waveform text labels.
  final Color textColor;

  /// Opaque background color drawn behind labels to prevent cached-image
  /// blending artefacts (crossing-polygon strokes bleeding into text
  /// anti-aliased edges).  When null, no background is drawn.
  final Color? labelBackgroundColor;

  /// Label text colour guaranteed to contrast with [labelBackgroundColor].
  ///
  /// Returns [textColor] when it already has sufficient WCAG contrast
  /// (≥ 3:1) against the background.  Otherwise derives a high-contrast
  /// fallback: near-black on light backgrounds, light grey on dark.
  late final Color effectiveLabelTextColor = _computeEffectiveLabelTextColor();

  Color _computeEffectiveLabelTextColor() {
    if (labelBackgroundColor == null) {
      return textColor;
    }
    final bgLum = labelBackgroundColor!.computeLuminance();
    final textLum = textColor.computeLuminance();
    final lighter = textLum > bgLum ? textLum : bgLum;
    final darker = textLum > bgLum ? bgLum : textLum;
    final ratio = (lighter + 0.05) / (darker + 0.05);
    if (ratio >= 3.0) {
      return textColor;
    }
    // Insufficient contrast — derive from background luminance.
    return bgLum > 0.5 ? const Color(0xFF1A1A1A) : const Color(0xFFE0E0E0);
  }

  /// Pre-created Paint for label backgrounds.  Reused across all labels
  /// in [paintStoredLabels] to avoid allocating a new Paint() per label
  /// per frame (eliminates the toSkPaint hotspot).
  @protected
  late final Paint? labelBgPaint;

  /// Waveform data points to render.
  final List<Data> waveform;

  /// Visible time range for compatibility with older callers.
  final int finalTime; // Visible time range (kept for compatibility, but use
  // timescale for mapping)

  /// Visible start time for compatibility with older callers.
  final int startTime; // Visible start time (kept for compatibility)

  /// Optional declared signal width.
  final int? signalWidth; // optional declared width for the signal

  /// Left offset used to align the waveform with the timescale.
  final double leftOffset; // Left offset to align with timescale

  /// Visible viewport width in pixels.
  final double viewportWidth; // visible viewport width in pixels

  /// Horizontal scroll offset captured at build time.
  final double scrollOffset; // horizontal scroll offset in pixels (build-time)

  /// Full timescale used for absolute time mapping.
  final int timescale; // Full timescale for absolute time mapping

  /// Live scroll offset set by `_ViewportPainter` just before `paint()` is
  /// called.  Falls back to [scrollOffset] if never set.
  /// Current live scroll offset used during painting.
  double _liveScrollOffset = double.nan;

  /// Returns the live scroll offset, or the build-time offset if unset.
  double get liveScrollOffset =>
      _liveScrollOffset.isNaN ? scrollOffset : _liveScrollOffset;

  /// Updates the live scroll offset used during painting.
  set liveScrollOffset(double v) => _liveScrollOffset = v;

  /// Mutable viewport width override, set by `_ViewportPainter` when
  /// recording a wider-than-viewport Picture for caching.
  double _liveViewportWidth = double.nan;

  /// Returns the live viewport width, or the build-time width if unset.
  double get liveViewportWidth =>
      _liveViewportWidth.isNaN ? viewportWidth : _liveViewportWidth;

  /// Updates the live viewport width used during painting.
  set liveViewportWidth(double v) => _liveViewportWidth = v;

  /// When `true`, label rendering uses viewport-aware centering: the
  /// label is centred within the *visible* intersection of the interval
  /// and the user's viewport.  When `false` (default), labels are simply
  /// centred within the full interval — correct for strip-tile rendering
  /// where the "viewport" is the strip, not the user's screen.
  ///
  /// Set to `true` by `_ViewportPainter` (single-signal mode) and the
  /// deferred-label overlay pass in `_CombinedWaveformPainter`.
  bool viewportCenterLabels = false;

  /// Pre-computed visible time bounds, set by the panel painter before
  /// calling paint().  When non-null, paint() skips the redundant
  /// `visibleTimeBoundsFor()` computation (saves 23 × per cache rebuild).
  /// Minimum visible time bound prepared by the panel painter.
  int? preVisMinTime;

  /// Maximum visible time bound prepared by the panel painter.
  int? preVisMaxTime;

  /// Time up to which waveform data is known to be valid.
  ///
  /// When non-null and less than [timescale], the region from
  /// [dataEndTime] to [timescale] is painted as a gray dashed line
  /// to indicate that data has not been fetched for that range
  /// (e.g. while waveform fetches are paused).
  final int? dataEndTime;

  /// Creates a waveform painter.
  Waveform(
    this.waveform,
    this.finalTime,
    this.startTime, {
    this.signalWidth,
    this.valueFormat = MonitorValueFormat.waveform,
    this.leftOffset = waveformLeftOffset,
    this.viewportWidth = 0.0,
    this.scrollOffset = 0.0,
    this.timescale = 0,
    this.dataEndTime,
    this.signalColor = Colors.green,
    this.xColor = Colors.red,
    this.zColor = Colors.yellow,
    this.textColor = const Color(0xFFD4D4D4),
    this.labelBackgroundColor,
    super.repaint,
  }) {
    greenPaint = Paint()
      ..color = signalColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true
      ..strokeCap = StrokeCap.butt
      ..strokeJoin = StrokeJoin.miter;
    redPaint = Paint()
      ..color = xColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true
      ..strokeCap = StrokeCap.butt
      ..strokeJoin = StrokeJoin.miter;
    yellowPaint = Paint()
      ..color = zColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true
      ..strokeCap = StrokeCap.butt
      ..strokeJoin = StrokeJoin.miter;
    labelBgPaint = labelBackgroundColor != null
        ? (Paint()
          ..color = labelBackgroundColor!
          ..style = PaintingStyle.fill)
        : null;
  }

  /// Display format selected for this waveform row.
  final MonitorValueFormat valueFormat;

  /// Compute the visible time window from scroll state and drawing geometry.
  ///
  /// Returns `(minTime, maxTime)` clamped to `[0, effectiveTimescale]`.
  /// A small margin is added so partially-visible segments at viewport edges
  /// are still drawn.
  ///
  /// [liveScrollOffset] should be the current scroll position (may differ from
  /// the build-time [scrollOffset] field when called from `_ViewportPainter`).
  (int, int) visibleTimeBoundsFor(
    double contentWidth,
    double liveScrollOffset,
    double vpWidth,
  ) {
    final effectiveTimescale =
        (timescale > 0) ? timescale : (finalTime > 0 ? finalTime : 0);
    if (effectiveTimescale <= 0 || contentWidth <= 0) {
      return (0, effectiveTimescale);
    }

    final left = leftOffset;
    final rightPadding = left;
    final drawingWidth = contentWidth - left - rightPadding;
    if (drawingWidth <= 0) {
      return (0, effectiveTimescale);
    }

    const marginPx = 50;
    final pxPerTime = drawingWidth / effectiveTimescale;
    final minX = liveScrollOffset - marginPx;
    final maxX = liveScrollOffset + vpWidth + marginPx;
    final minTime = ((minX - left) / pxPerTime).floor().clamp(
          0,
          effectiveTimescale,
        );
    final maxTime = ((maxX - left) / pxPerTime).ceil().clamp(
          0,
          effectiveTimescale,
        );
    return (minTime, maxTime);
  }

  /// Binary search for the index of the last waveform entry with
  /// `time <= targetTime`.  Returns -1 if none exists.
  static int indexAtOrBefore(List<Data> data, int targetTime) {
    var lo = 0;
    var hi = data.length - 1;
    var res = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (data[mid].time <= targetTime) {
        res = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return res;
  }

  /// Build value-change segments using pixel-sampling LOD.
  ///
  /// Instead of iterating every transition in the waveform data, this walks
  /// through the visible time range at pixel-stride resolution.  At each
  /// pixel boundary a binary search determines the signal value; segments
  /// are emitted only when the value actually changes between consecutive
  /// pixels.  After locating a value the algorithm peeks at the next
  /// transition in the data to compute which pixel it maps to and *skips*
  /// directly there, so the cost is **O(visibleChanges × log N)** where
  /// `visibleChanges ≤ imageWidthPx` — regardless of total data density.
  ///
  /// Returns a list of `(startTime, endTime, value)` records.  An empty
  /// list signals the caller that pixel-sampling was not applicable (e.g.
  /// the zoom level is high enough that normal iteration is faster).
  ///
  /// [visMinTime]/[visMaxTime] are the visible (recording) time bounds.
  /// [pxPerTime] maps time → pixel coordinates.
  /// [effectiveTimescale] is the upper time bound of the data.
  static List<(int, int, String)> buildPixelSampledSegments({
    required List<Data> data,
    required int visMinTime,
    required int visMaxTime,
    required int effectiveTimescale,
    required double pxPerTime,
  }) {
    // Only apply LOD when each pixel spans multiple time units.
    // Below this threshold every transition maps to its own pixel so
    // normal iteration is already O(pixels).
    final timePerPx = pxPerTime > 0 ? 1.0 / pxPerTime : 0;
    if (timePerPx < 2.0 || data.isEmpty || visMinTime >= visMaxTime) {
      return const [];
    }

    final clampedMax = visMaxTime.clamp(0, effectiveTimescale);
    final segments = <(int, int, String)>[];

    // Locate starting value via binary search.
    var curIdx = indexAtOrBefore(data, visMinTime);
    String curValue;
    int segStart;
    if (curIdx < 0) {
      curValue = data.first.value;
      segStart = visMinTime;
      curIdx = 0;
    } else {
      curValue = data[curIdx].value;
      segStart = visMinTime;
    }

    // Walk forward through transitions, skipping sub-pixel clusters.
    var nextIdx = curIdx + 1;
    while (nextIdx < data.length) {
      final nextTime = data[nextIdx].time;
      if (nextTime > clampedMax || nextTime > effectiveTimescale) {
        break;
      }

      // Skip same-value entries (some loaders emit duplicates).
      if (data[nextIdx].value == curValue) {
        nextIdx++;
        continue;
      }

      // A genuine value change at nextTime.
      final segPx = (nextTime - segStart) * pxPerTime;

      if (segPx >= 1.0) {
        // Wide enough to be a visible segment — emit as-is.
        segments.add((segStart, nextTime, curValue));
        segStart = nextTime;
        curValue = data[nextIdx].value;
        curIdx = nextIdx;
        nextIdx = curIdx + 1;
      } else {
        // Sub-pixel: emit the tiny segment, then binary-search to the
        // next pixel boundary to skip potentially thousands of
        // intermediate transitions in one O(log N) step.
        segments.add((segStart, nextTime, curValue));

        final nextPixelTime = (segStart + timePerPx.ceil()).clamp(
          0,
          clampedMax,
        );
        final jumpIdx = indexAtOrBefore(data, nextPixelTime);
        if (jumpIdx > nextIdx) {
          curIdx = jumpIdx;
          curValue = data[jumpIdx].value;
          segStart = data[jumpIdx].time.clamp(segStart, clampedMax);
          nextIdx = curIdx + 1;
        } else {
          // Jump didn't advance past nextIdx — normal advance.
          curIdx = nextIdx;
          curValue = data[nextIdx].value;
          segStart = nextTime;
          nextIdx = curIdx + 1;
        }
      }
    }

    // Final segment to reach the end of the visible range.
    if (segStart < clampedMax) {
      segments.add((segStart, clampedMax, curValue));
    }

    return segments;
  }

  /// Find the last value at or before [time] using binary search on
  /// ordered data.
  String? getValueAtOrBeforeTime(List<Data> data, int time) {
    if (data.isEmpty) {
      return null;
    }
    var lo = 0;
    var hi = data.length - 1;
    var res = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (data[mid].time <= time) {
        res = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    if (res == -1) {
      return null;
    }
    return data[res].value;
  }

  /// Returns the exact value at [time], or null if no sample matches.
  String? getValueAtTime(List<Data> data, int time) {
    for (final dataItem in data) {
      if (dataItem.time == time) {
        return dataItem.value;
      }
    }
    return null;
  }

  // ── Gray gap region for paused data ───────────────────────────────
  // Pre-allocated paint for the gap extension line.
  static final Paint _gapPaint = Paint()
    ..color = const Color(0xFF888888)
    ..strokeWidth = 1.0
    ..style = PaintingStyle.stroke;
  static final Paint _gapLinePaint = Paint()
    ..color = const Color(0xFF888888)
    ..strokeWidth = 2.0
    ..style = PaintingStyle.stroke;

  /// Returns the Y positions at which the last waveform value should be
  /// extended as gray lines into the gap region.
  ///
  /// Subclasses override this to match their value→Y mapping.
  /// Returns an empty list if no extension line should be drawn.
  @protected
  List<double> gapExtensionYPositions(String lastValue, Size size) => [];

  /// Paint a gray extension of the last waveform value from `dataEndTime`
  /// to the effective timescale to indicate the time range where data has not
  /// been fetched.
  ///
  /// Call this at the end of `paint` in subclasses, before `canvas.restore()`.
  void paintGapRegion(Canvas canvas, Size size, double pxPerTime) {
    if (dataEndTime == null) {
      return;
    }
    final effectiveTimescale = (timescale > 0) ? timescale : finalTime;
    if (dataEndTime! >= effectiveTimescale) {
      return;
    }
    final left = leftOffset;
    final gapStartX = left + dataEndTime! * pxPerTime;
    final gapEndX = left + effectiveTimescale * pxPerTime;
    if (gapEndX <= gapStartX) {
      return;
    }

    // Find the last waveform value at or before dataEndTime.
    String? lastValue;
    for (var i = waveform.length - 1; i >= 0; i--) {
      if (waveform[i].time <= dataEndTime!) {
        lastValue = waveform[i].value;
        break;
      }
    }

    // Draw gray extension lines at the Y positions for the last value.
    if (lastValue != null) {
      final yPositions = gapExtensionYPositions(lastValue, size);
      for (final y in yPositions) {
        canvas.drawLine(
          Offset(gapStartX, y),
          Offset(gapEndX, y),
          _gapLinePaint,
        );
      }
    }

    // Vertical dashed separator at the gap boundary
    final sx = Waveform.snapX(gapStartX);
    final h = size.height;
    const dash = 4;
    const gap = 3.0;
    var y = 0.0;
    while (y < h) {
      final end = (y + dash).clamp(0.0, h);
      canvas.drawLine(Offset(sx, y), Offset(sx, end), _gapPaint);
      y = end + gap;
    }
  }

  // Repaint only if meaningful properties change
  // Ignore repaint notifier changes (handled separately via valueListenable)
  @override
  bool shouldRepaint(covariant Waveform oldDelegate) =>
      oldDelegate.waveform != waveform ||
      oldDelegate.signalColor != signalColor ||
      oldDelegate.xColor != xColor ||
      oldDelegate.zColor != zColor ||
      oldDelegate.textColor != textColor ||
      oldDelegate.labelBackgroundColor != labelBackgroundColor ||
      oldDelegate.timescale != timescale ||
      oldDelegate.dataEndTime != dataEndTime ||
      oldDelegate.leftOffset != leftOffset ||
      oldDelegate.viewportWidth != viewportWidth ||
      oldDelegate.signalWidth != signalWidth;

  /// Base font size for waveform labels (at default row height of 30).
  static const double _baseFontSize = 18;

  /// Compute a scaled font size proportional to the given [rowHeight].
  static double scaledFontSize(double rowHeight) =>
      _baseFontSize * (rowHeight / baseSignalRowHeight);

  /// Paints cached text at [offset] using the waveform label style.
  void writeText(
    Canvas canvas,
    Offset offset, {
    required String text,
    TextStyle? customTextStyle,
    double? rowHeight,
  }) {
    // Scale font size proportionally to the row height.
    final fs = rowHeight != null ? scaledFontSize(rowHeight) : _baseFontSize;
    final style = customTextStyle ??
        TextStyle(color: effectiveLabelTextColor, fontSize: fs);
    getCachedLabel(
      text,
      style.fontSize ?? fs,
      style.color ?? effectiveLabelTextColor,
      fontWeight: style.fontWeight,
    ).paint(canvas, offset);
  }

  /// Formats a waveform value for multi-bit labels.
  ///
  /// - Preserves X/Z values (returns the original string without `0x`).
  /// - Converts bitvectors (`1010`, `0b1010`) and decimals to hex.
  /// - Pads hex to `signalWidth` when available.
  ///
  /// Results are cached in [_hexFormatCache] keyed by
  /// `rawValue + ':' + signalWidth`.  The cache avoids
  /// BigInt.tryParse / toRadixString calls during scroll frames,
  /// which together were responsible for ~1.7% CPU in profiler traces
  /// (_mulAdd + _parseRadix hotspots).
  String formatValueAsHexLabel(String rawValue) {
    // Build a cache key that incorporates the signal width (since it
    // affects padding).  Using ':' separator is safe because rawValue
    // never contains it in practice (hex/binary/decimal strings).
    final cacheKey = signalWidth != null
        ? '$valueFormat:$rawValue:$signalWidth'
        : '$valueFormat:$rawValue';
    final cached = _hexFormatCache[cacheKey];
    if (cached != null) {
      return cached;
    }

    final result = formatValueForDisplay(
      _formatValueAsHexLabelImpl(rawValue),
      valueFormat,
      signalWidth ?? 1,
    );

    // Full clear when cache is full — cheaper than partial eviction
    // and prevents string accumulation in old-gen.
    if (_hexFormatCache.length >= _maxHexFormatCache) {
      _hexFormatCache.clear();
    }
    _hexFormatCache[cacheKey] = result;
    return result;
  }

  /// Core implementation of hex formatting (uncached).
  ///
  /// Values arriving from the VM or evaluators are in ROHD's native
  /// radixString format (`<width>'h<hex>`).  These are passed through
  /// unchanged.  Legacy `0x`/binary formats are normalised via [LogicValue].
  String _formatValueAsHexLabelImpl(String rawValue) {
    var v = rawValue.trim();
    if (v.isEmpty) {
      return v;
    }
    v = v.replaceAll('\u0000', '');

    // Already a radixString — pass through.
    if (_hasRadixPrefix(v)) {
      return v;
    }

    // Legacy 0x / 0b / bare value — convert via LogicValue.
    final w = signalWidth ?? 1;
    try {
      final lower = v.toLowerCase();
      BigInt? parsed;
      if (lower.startsWith('0x')) {
        parsed = BigInt.tryParse(lower.substring(2), radix: 16);
      } else if (lower.startsWith('0b')) {
        parsed = BigInt.tryParse(lower.substring(2), radix: 2);
      } else if (_isBinaryValue(lower) && lower.length > 1) {
        parsed = BigInt.tryParse(lower, radix: 2);
      } else {
        parsed = BigInt.tryParse(lower);
      }
      if (parsed != null) {
        return LogicValue.ofBigInt(parsed, w > 0 ? w : 1).toString();
      }
      return v;
    } on Object catch (_) {
      return v;
    }
  }

  /// Static convenience to format a raw waveform value as a radixString label.
  ///
  /// This mirrors `formatValueAsHexLabel` but can be called without a
  /// painter instance. It is used by the hover tooltip in `WaveformPanel`.
  static String formatHexValue(String rawValue, {int? width}) {
    var v = rawValue.trim();
    if (v.isEmpty) {
      return v;
    }
    v = v.replaceAll('\u0000', '');

    // Already a radixString — pass through.
    if (_hasRadixPrefix(v)) {
      return v;
    }

    // Legacy 0x / 0b / bare value — convert via LogicValue.
    final w = (width != null && width > 0) ? width : 1;
    try {
      final lower = v.toLowerCase();
      BigInt? parsed;
      if (lower.startsWith('0x')) {
        parsed = BigInt.tryParse(lower.substring(2), radix: 16);
      } else if (lower.startsWith('0b')) {
        parsed = BigInt.tryParse(lower.substring(2), radix: 2);
      } else if (_isBinaryValue(lower) && lower.length > 1) {
        parsed = BigInt.tryParse(lower, radix: 2);
      } else {
        parsed = BigInt.tryParse(lower);
      }
      if (parsed != null) {
        return LogicValue.ofBigInt(parsed, w).toString();
      }
      return v;
    } on Object catch (_) {
      return v;
    }
  }
}
