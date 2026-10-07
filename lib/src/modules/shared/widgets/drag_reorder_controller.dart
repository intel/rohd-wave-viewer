// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// drag_reorder_controller.dart
// Cross-panel drag-reorder controller for synchronized signal reordering.
//
// 2026 March
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/foundation.dart';
import 'package:rohd_wave_viewer/src/const/const.dart';

/// Shared controller for cross-panel drag-reorder.
///
/// Created once in `_WaveFormViewerPageState` and passed to all three
/// panels (Selected Signals, Value, Waveform). Any panel can initiate
/// a drag; all panels observe the controller to animate their rows in
/// lockstep.
///
/// During a drag:
/// - The source row follows the pointer (translated by [dragOffsetY]).
/// - Rows between [sourceIndex] and [targetIndex] shift by one row
///   height (up or down) to make room for the dragged row.
/// - On drop, the caller should emit a `SignalReorderEvent` with the
///   returned `(oldIndex, newIndex)` pair.
class DragReorderController extends ChangeNotifier {
  int? _sourceIndex;
  int? _targetIndex;
  double _dragOffsetY = 0;
  int _itemCount = 0;

  /// The current row height used for drag calculations.
  /// Updated when the waveform scale changes.
  double rowHeight = signalRowHeight;

  /// When non-empty, a group of rows is being dragged together.
  /// Sorted ascending.  The first element whose original index equals
  /// [_sourceIndex] is the "anchor" that follows the pointer.
  List<int> _groupIndices = const [];

  /// The index of the row being dragged (null when idle).
  int? get sourceIndex => _sourceIndex;

  /// Where the dragged row would land if released now.
  int? get targetIndex => _targetIndex;

  /// Cumulative vertical pixel offset from the drag start point.
  double get dragOffsetY => _dragOffsetY;

  /// Number of items in the list at drag start.
  int get itemCount => _itemCount;

  /// Whether a drag is currently in progress.
  bool get isDragging => _sourceIndex != null;

  /// Whether the current drag involves a group of rows.
  bool get isGroupDrag => _groupIndices.length > 1;

  /// The sorted indices of all rows in the drag group.
  List<int> get groupIndices => _groupIndices;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Begin dragging the row at [index] within a list of [count] items.
  void startDrag(int index, int count, {List<int>? groupIndices}) {
    debugPrint(
      '[DragReorder] startDrag: sourceIndex=$index, itemCount=$count'
      '${groupIndices != null ? ", group=$groupIndices" : ""}',
    );
    _sourceIndex = index;
    _targetIndex = index;
    _dragOffsetY = 0;
    _itemCount = count;
    if (groupIndices != null && groupIndices.length > 1) {
      _groupIndices = List<int>.from(groupIndices)..sort();
    } else {
      _groupIndices = const [];
    }
    notifyListeners();
  }

  /// Update the drag with a vertical pointer delta of [deltaY] pixels.
  void updateDrag(double deltaY) {
    if (!isDragging) {
      return;
    }
    _dragOffsetY += deltaY;

    // Compute the target index based on how many rows the pointer has
    // travelled from the source position.
    final rowsMoved = (_dragOffsetY / rowHeight).round();
    if (isGroupDrag) {
      // For group drag, target represents where the anchor row lands.
      // Clamp so the entire group stays in bounds.
      final anchorPosInGroup = _groupIndices.indexOf(_sourceIndex!);
      final minTarget = anchorPosInGroup;
      final maxTarget = _itemCount - (_groupIndices.length - anchorPosInGroup);
      _targetIndex = (_sourceIndex! + rowsMoved).clamp(minTarget, maxTarget);
    } else {
      _targetIndex = (_sourceIndex! + rowsMoved).clamp(0, _itemCount - 1);
    }
    notifyListeners();
  }

  /// Finish the drag and return `(oldIndex, newIndex)`, or `null` if
  /// the item didn't move (or no drag was active).
  ///
  /// For group drags, `groupOldIndices` contains the original sorted
  /// indices of all group members.
  ({int oldIndex, int newIndex, List<int>? groupOldIndices})? endDrag() {
    if (_sourceIndex == null || _targetIndex == null) {
      cancelDrag();
      return null;
    }
    final src = _sourceIndex!;
    final tgt = _targetIndex!;
    final group = isGroupDrag ? List<int>.from(_groupIndices) : null;
    debugPrint(
      '[DragReorder] endDrag: oldIndex=$src, newIndex=$tgt'
      '${group != null ? ", group=$group" : ""}, dragOffsetY=$_dragOffsetY',
    );
    _reset();
    if (src == tgt && group == null) {
      return null;
    }
    if (group != null && src == tgt) {
      return null;
    }
    return (oldIndex: src, newIndex: tgt, groupOldIndices: group);
  }

  /// Cancel the current drag without committing.
  void cancelDrag() {
    _reset();
  }

  // ---------------------------------------------------------------------------
  // Row layout helpers
  // ---------------------------------------------------------------------------

  /// The Y-axis translation for [index] during an active drag.
  ///
  /// **Single drag:** source follows pointer, rows between source↔target
  /// shift by ±[rowHeight].
  ///
  /// **Group drag:** all group members follow the pointer maintaining
  /// relative spacing.  Non-group rows shift to make room for the block.
  double getRowTranslateY(int index) {
    if (!isDragging) {
      return 0;
    }

    if (isGroupDrag) {
      return _groupTranslateY(index);
    }

    // Single-row drag.
    if (index == _sourceIndex) {
      return _dragOffsetY;
    }
    final src = _sourceIndex!;
    final tgt = _targetIndex!;
    if (src < tgt) {
      if (index > src && index <= tgt) {
        return -rowHeight;
      }
    } else if (src > tgt) {
      if (index >= tgt && index < src) {
        return rowHeight;
      }
    }
    return 0;
  }

  double _groupTranslateY(int index) {
    final src = _sourceIndex!;
    final tgt = _targetIndex!;
    final anchorPosInGroup = _groupIndices.indexOf(src);
    final groupSize = _groupIndices.length;

    // Where the group block's first row lands in the final ordering.
    final blockFirst = tgt - anchorPosInGroup;

    final groupPos = _groupIndices.indexOf(index);
    if (groupPos >= 0) {
      // This row is a group member.
      // Its target position (in the final list) = blockFirst + groupPos.
      // Its current on-screen position = index * rowHeight.
      // But we display it as: following the anchor's drag offset,
      // adjusted for its position in the group relative to anchor.
      final offsetFromAnchor = (groupPos - anchorPosInGroup) * rowHeight;
      return _dragOffsetY + offsetFromAnchor - (index - src) * rowHeight;
    }

    // Non-group row: compute how many group members were originally
    // above this row vs how many will be above after the move.
    var groupOrigAbove = 0;
    for (final gi in _groupIndices) {
      if (gi < index) {
        groupOrigAbove++;
      }
    }

    // The row's "non-group rank" (position among non-group rows only).
    final nonGroupRank = index - groupOrigAbove;

    // After the move, group occupies [blockFirst..blockFirst+groupSize-1].
    // Non-group rows fill remaining slots in order.
    // How many group members will be above this row's final position?
    final int groupTargetAbove;
    if (nonGroupRank >= blockFirst) {
      groupTargetAbove = groupSize;
    } else {
      groupTargetAbove = 0;
    }

    return (groupTargetAbove - groupOrigAbove) * rowHeight;
  }

  /// Whether [index] is a row currently being dragged (source or group member).
  bool isSourceRow(int index) {
    if (_groupIndices.isNotEmpty) {
      return _groupIndices.contains(index);
    }
    return index == _sourceIndex;
  }

  // ---------------------------------------------------------------------------
  // Private
  // ---------------------------------------------------------------------------

  void _reset() {
    _sourceIndex = null;
    _targetIndex = null;
    _dragOffsetY = 0;
    _itemCount = 0;
    _groupIndices = const [];
    notifyListeners();
  }
}
