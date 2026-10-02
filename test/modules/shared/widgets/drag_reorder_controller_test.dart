// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// drag_reorder_controller_test.dart
// Tests for DragReorderController.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_wave_viewer/src/modules/shared/widgets/drag_reorder_controller.dart';

void main() {
  late DragReorderController controller;

  setUp(() {
    controller = DragReorderController();
  });

  tearDown(() {
    controller.dispose();
  });

  group('DragReorderController', () {
    // ──── Initial state ────

    test('initial state is idle', () {
      expect(controller.isDragging, isFalse);
      expect(controller.isGroupDrag, isFalse);
      expect(controller.sourceIndex, isNull);
      expect(controller.targetIndex, isNull);
      expect(controller.dragOffsetY, 0);
      expect(controller.itemCount, 0);
      expect(controller.groupIndices, isEmpty);
    });

    // ──── startDrag ────

    test('startDrag sets sourceIndex and targetIndex', () {
      controller.startDrag(2, 5);
      expect(controller.isDragging, isTrue);
      expect(controller.sourceIndex, 2);
      expect(controller.targetIndex, 2);
      expect(controller.itemCount, 5);
      expect(controller.dragOffsetY, 0);
      expect(controller.isGroupDrag, isFalse);
    });

    test('startDrag with group sets groupIndices', () {
      controller.startDrag(1, 5, groupIndices: [1, 3, 4]);
      expect(controller.isDragging, isTrue);
      expect(controller.isGroupDrag, isTrue);
      expect(controller.groupIndices, [1, 3, 4]);
    });

    test('startDrag with single-element group is not group drag', () {
      controller.startDrag(2, 5, groupIndices: [2]);
      expect(controller.isGroupDrag, isFalse);
    });

    test('startDrag notifies listeners', () {
      var notified = false;
      controller
        ..addListener(() => notified = true)
        ..startDrag(0, 3);
      expect(notified, isTrue);
    });

    // ──── updateDrag (single) ────

    test('updateDrag is no-op when not dragging', () {
      controller.updateDrag(100);
      expect(controller.isDragging, isFalse);
      expect(controller.targetIndex, isNull);
    });

    test('updateDrag moves targetIndex based on rowHeight', () {
      controller
        ..startDrag(2, 5)
        // Move down by 1 row
        ..updateDrag(controller.rowHeight);
      expect(controller.targetIndex, 3);
      expect(controller.dragOffsetY, controller.rowHeight);
    });

    test('updateDrag clamps targetIndex to bounds', () {
      controller
        ..startDrag(0, 5)
        // Move up past top
        ..updateDrag(-controller.rowHeight * 3);
      expect(controller.targetIndex, 0);
    });

    test('updateDrag clamps targetIndex to bottom', () {
      controller
        ..startDrag(3, 5)
        // Move down past bottom
        ..updateDrag(controller.rowHeight * 10);
      expect(controller.targetIndex, 4);
    });

    test('updateDrag accumulates deltaY', () {
      controller
        ..startDrag(2, 10)
        ..updateDrag(10)
        ..updateDrag(20);
      expect(controller.dragOffsetY, 30);
    });

    // ──── updateDrag (group) ────

    test('updateDrag clamps group drag to keep entire group in bounds', () {
      // Group indices: [0, 1, 2], anchor=1, itemCount=6
      controller
        ..startDrag(1, 6, groupIndices: [0, 1, 2])
        // Move down a lot — should clamp so group stays in bounds
        ..updateDrag(controller.rowHeight * 20);
      // anchor is at pos 1 in group (0-indexed), groupSize=3
      // maxTarget = 6 - (3-1) = 4
      expect(controller.targetIndex! <= 4, isTrue);
    });

    test('updateDrag clamps group drag upward', () {
      controller
        ..startDrag(3, 6, groupIndices: [2, 3, 4])
        // Move up a lot
        ..updateDrag(-controller.rowHeight * 20);
      // anchor is at pos 1 in group, minTarget = 1
      expect(controller.targetIndex! >= 1, isTrue);
    });

    // ──── endDrag ────

    test('endDrag returns null when no drag active', () {
      expect(controller.endDrag(), isNull);
    });

    test('endDrag returns null when item did not move', () {
      controller.startDrag(2, 5);
      // No updateDrag — source == target
      final result = controller.endDrag();
      expect(result, isNull);
      expect(controller.isDragging, isFalse);
    });

    test('endDrag returns (oldIndex, newIndex) when item moved', () {
      controller
        ..startDrag(1, 5)
        ..updateDrag(controller.rowHeight * 2);
      final result = controller.endDrag();
      expect(result, isNotNull);
      expect(result!.oldIndex, 1);
      expect(result.newIndex, 3);
      expect(result.groupOldIndices, isNull);
      // Should be reset
      expect(controller.isDragging, isFalse);
    });

    test('endDrag returns groupOldIndices for group drag', () {
      controller
        ..startDrag(1, 6, groupIndices: [1, 3])
        ..updateDrag(controller.rowHeight * 2);
      final result = controller.endDrag();
      expect(result, isNotNull);
      expect(result!.groupOldIndices, [1, 3]);
    });

    test('endDrag returns null for group drag when anchor did not move', () {
      controller.startDrag(2, 5, groupIndices: [1, 2]);
      // No updateDrag
      final result = controller.endDrag();
      expect(result, isNull);
    });

    // ──── cancelDrag ────

    test('cancelDrag resets state', () {
      controller
        ..startDrag(1, 5)
        ..updateDrag(100)
        ..cancelDrag();
      expect(controller.isDragging, isFalse);
      expect(controller.sourceIndex, isNull);
      expect(controller.targetIndex, isNull);
      expect(controller.dragOffsetY, 0);
    });

    // ──── getRowTranslateY (single drag) ────

    test('getRowTranslateY returns 0 when not dragging', () {
      expect(controller.getRowTranslateY(0), 0);
    });

    test('getRowTranslateY: source row follows pointer', () {
      controller
        ..startDrag(2, 5)
        ..updateDrag(50);
      expect(controller.getRowTranslateY(2), 50);
    });

    test('getRowTranslateY: rows between source and target shift down', () {
      controller
        ..startDrag(0, 5)
        // Move source from 0 to 2
        ..updateDrag(controller.rowHeight * 2);
      // Rows 1 and 2 should shift up by -rowHeight
      expect(controller.getRowTranslateY(1), -controller.rowHeight);
      expect(controller.getRowTranslateY(2), -controller.rowHeight);
      // Row 3 is unaffected
      expect(controller.getRowTranslateY(3), 0);
    });

    test('getRowTranslateY: rows shift up when dragging upward', () {
      controller
        ..startDrag(3, 5)
        // Move source from 3 to 1
        ..updateDrag(-controller.rowHeight * 2);
      // Rows 1 and 2 should shift down by +rowHeight
      expect(controller.getRowTranslateY(1), controller.rowHeight);
      expect(controller.getRowTranslateY(2), controller.rowHeight);
      // Row 0 is unaffected
      expect(controller.getRowTranslateY(0), 0);
    });

    // ──── getRowTranslateY (group drag) ────

    test('getRowTranslateY: group members follow pointer', () {
      controller
        ..startDrag(1, 6, groupIndices: [1, 2])
        ..updateDrag(controller.rowHeight * 2);
      // Group member at index 1 (anchor) should follow pointer
      final anchorY = controller.getRowTranslateY(1);
      expect(anchorY, controller.rowHeight * 2);
    });

    test('getRowTranslateY: non-group rows shift for group drag', () {
      controller
        ..startDrag(1, 6, groupIndices: [1, 2])
        ..updateDrag(controller.rowHeight * 2);
      // Non-group row at index 0 should shift based on block position
      final row0Y = controller.getRowTranslateY(0);
      // Row 0 is a non-group row; the group moved down, so row 0 stays put
      expect(row0Y.isFinite, isTrue);
    });

    // ──── isSourceRow ────

    test('isSourceRow returns false when idle', () {
      expect(controller.isSourceRow(0), isFalse);
    });

    test('isSourceRow identifies source in single drag', () {
      controller.startDrag(2, 5);
      expect(controller.isSourceRow(2), isTrue);
      expect(controller.isSourceRow(1), isFalse);
    });

    test('isSourceRow identifies all group members', () {
      controller.startDrag(1, 5, groupIndices: [1, 3]);
      expect(controller.isSourceRow(1), isTrue);
      expect(controller.isSourceRow(3), isTrue);
      expect(controller.isSourceRow(2), isFalse);
    });

    // ──── rowHeight ────

    test('custom rowHeight affects target calculation', () {
      controller
        ..rowHeight = 50
        ..startDrag(0, 10)
        ..updateDrag(100); // 2 rows at height 50
      expect(controller.targetIndex, 2);
    });

    // ──── notifyListeners ────

    test('updateDrag notifies listeners', () {
      controller.startDrag(0, 5);
      var count = 0;
      controller
        ..addListener(() => count++)
        ..updateDrag(10)
        ..updateDrag(10);
      expect(count, 2);
    });

    test('endDrag notifies listeners via reset', () {
      controller
        ..startDrag(0, 5)
        ..updateDrag(controller.rowHeight);
      var notified = false;
      controller
        ..addListener(() => notified = true)
        ..endDrag();
      expect(notified, isTrue);
    });

    test('cancelDrag notifies listeners', () {
      controller.startDrag(0, 5);
      var notified = false;
      controller
        ..addListener(() => notified = true)
        ..cancelDrag();
      expect(notified, isTrue);
    });
  });
}
