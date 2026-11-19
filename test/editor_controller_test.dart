// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:bead_studio/models/pattern.dart';
import 'package:bead_studio/state/editor_controller.dart';
import 'package:flutter_test/flutter_test.dart';

EditorController _controller({int width = 4, int height = 4}) {
  return EditorController(
    pattern: BeadPattern.blank(title: '测试', width: width, height: height),
  );
}

void main() {
  group('EditorController', () {
    test('paints a stroke and undoes / redoes it', () {
      final controller = _controller();
      controller.selectColor(0xFF112233);

      controller.beginStroke();
      controller.paintAt(1, 1);
      controller.paintSegment(1, 1, 3, 1);
      controller.endStroke();

      expect(controller.pattern.cellAt(1, 1), 0xFF112233);
      expect(controller.pattern.cellAt(3, 1), 0xFF112233);
      expect(controller.pattern.beadCount, 3);
      expect(controller.canUndo, isTrue);

      controller.undo();
      expect(controller.pattern.beadCount, 0);
      expect(controller.canRedo, isTrue);

      controller.redo();
      expect(controller.pattern.cellAt(1, 1), 0xFF112233);
      expect(controller.pattern.cellAt(3, 1), 0xFF112233);
    });

    test('flood fills only the matching region', () {
      final controller = _controller();
      controller.selectColor(0xFFAA0000);
      controller.beginStroke();
      controller.paintAt(0, 0);
      controller.endStroke();

      controller.selectColor(0xFF00AA00);
      controller.floodFillAt(3, 3);
      expect(controller.pattern.colorCounts[0xFF00AA00], 15);
      expect(controller.pattern.cellAt(0, 0), 0xFFAA0000);

      controller.undo();
      expect(controller.pattern.beadCount, 1);
    });

    test('draws an outlined rectangle', () {
      final controller = _controller(width: 5, height: 5);
      controller.selectColor(0xFF336699);
      controller.commitRectangle(1, 1, 3, 3);

      expect(controller.pattern.cellAt(1, 1), 0xFF336699);
      expect(controller.pattern.cellAt(3, 1), 0xFF336699);
      expect(controller.pattern.cellAt(1, 3), 0xFF336699);
      expect(controller.pattern.cellAt(3, 3), 0xFF336699);
      expect(controller.pattern.cellAt(2, 2), 0);
      expect(controller.pattern.beadCount, 8);
    });

    test('draws a Bresenham line', () {
      final controller = _controller(width: 5, height: 5);
      controller.selectColor(0xFF0000FF);
      controller.commitLine(0, 0, 4, 4);
      for (var i = 0; i < 5; i++) {
        expect(controller.pattern.cellAt(i, i), 0xFF0000FF);
      }
      expect(controller.pattern.beadCount, 5);
      controller.undo();
      expect(controller.pattern.beadCount, 0);
    });

    test('eyedropper selects an existing bead colour', () {
      final controller = _controller();
      controller.selectColor(0xFFCC5500);
      controller.beginStroke();
      controller.paintAt(2, 2);
      controller.endStroke();

      controller.selectColor(0xFF000000);
      controller.setTool(EditorTool.eyedropper);
      controller.pickAt(2, 2);

      expect(controller.currentColor, 0xFFCC5500);
      expect(controller.tool, EditorTool.pen);
      expect(controller.recentColors.first, 0xFFCC5500);
    });

    test('tracks dirty state when saved', () {
      final controller = _controller();
      expect(controller.isDirty, isFalse);
      controller.selectColor(0xFF123456);
      controller.beginStroke();
      controller.paintAt(0, 0);
      controller.endStroke();
      expect(controller.isDirty, isTrue);

      final revision = controller.revision;
      controller.markSaved(revision);
      expect(controller.isDirty, isFalse);
    });

    test('clears the canvas and undo restores it', () {
      final controller = _controller();
      controller.selectColor(0xFF654321);
      controller.floodFillAt(0, 0);
      expect(controller.pattern.beadCount, 16);

      controller.clearCanvas();
      expect(controller.pattern.beadCount, 0);

      controller.undo();
      expect(controller.pattern.beadCount, 16);
    });

    test('supports multiple frames with duplicate, switch, delete and undo', () {
      final controller = _controller();
      controller.selectColor(0xFFAA3355);
      controller.floodFillAt(0, 0);
      expect(controller.frameCount, 1);
      expect(controller.currentBeadCount, 16);

      expect(controller.duplicateCurrentFrame(), isTrue);
      expect(controller.frameCount, 2);
      expect(controller.currentFrame, 1);
      expect(controller.currentBeadCount, 16);

      controller.switchFrame(0);
      controller.selectColor(0xFF00AA55);
      controller.floodFillAt(0, 0);
      expect(controller.pattern.colorCountsFor(0)[0xFF00AA55], 16);
      expect(controller.pattern.colorCountsFor(1)[0xFFAA3355], 16);

      expect(controller.deleteCurrentFrame(), isTrue);
      expect(controller.frameCount, 1);
      expect(controller.currentFrame, 0);
      controller.undo();
      expect(controller.frameCount, 2);
    });

    test('resizes every frame and restores dimensions on undo', () {
      final controller = _controller();
      controller.selectColor(0xFF123456);
      controller.beginStroke();
      controller.paintAt(1, 1);
      controller.endStroke();

      expect(
        controller.resizeCanvas(6, 6, anchor: FrameAnchor.center),
        isTrue,
      );
      expect(controller.pattern.width, 6);
      expect(controller.pattern.height, 6);
      expect(controller.pattern.cellAt(2, 2), 0xFF123456);

      controller.undo();
      expect(controller.pattern.width, 4);
      expect(controller.pattern.height, 4);
      expect(controller.pattern.cellAt(1, 1), 0xFF123456);
    });

    test('cancels an active stroke when a pinch starts', () {
      final controller = _controller();
      controller.selectColor(0xFF336699);
      controller.beginStroke();
      controller.paintAt(1, 1);
      controller.cancelStroke();
      expect(controller.pattern.beadCount, 0);
      expect(controller.canUndo, isFalse);
    });

    test('pen tap removes a bead matching the held colour', () {
      final controller = _controller();
      controller.selectColor(0xFF112233);
      controller.beginStroke();
      controller.paintAt(0, 0);
      controller.paintAt(1, 0);
      controller.endStroke();

      controller.beginStroke();
      controller.paintAt(0, 0);
      controller.endStroke();
      expect(controller.pattern.cellAt(0, 0), 0);
      expect(controller.pattern.cellAt(1, 0), 0xFF112233);
      expect(controller.pattern.beadCount, 1);

      controller.undo();
      expect(controller.pattern.cellAt(0, 0), 0xFF112233);
    });

    test('pen tap replaces a bead of another colour', () {
      final controller = _controller();
      controller.selectColor(0xFF112233);
      controller.beginStroke();
      controller.paintAt(0, 0);
      controller.endStroke();

      controller.selectColor(0xFF00FF00);
      controller.beginStroke();
      controller.paintAt(0, 0);
      controller.endStroke();
      expect(controller.pattern.cellAt(0, 0), 0xFF00FF00);
    });

    test('pen drag keeps the mode decided by the first touched cell', () {
      final controller = _controller();
      controller.selectColor(0xFF112233);
      controller.beginStroke();
      controller.paintSegment(0, 0, 3, 0);
      controller.endStroke();

      controller.beginStroke();
      controller.paintAt(2, 0);
      controller.paintSegment(2, 0, 0, 0);
      controller.endStroke();
      expect(controller.pattern.beadCount, 1);
      expect(controller.pattern.cellAt(3, 0), 0xFF112233);

      controller.undo();
      expect(controller.pattern.beadCount, 4);

      controller.selectColor(0xFF00FF00);
      controller.beginStroke();
      controller.paintAt(3, 0);
      controller.paintSegment(3, 0, 0, 0);
      controller.endStroke();
      expect(controller.pattern.beadCount, 4);
      expect(controller.pattern.cellAt(0, 0), 0xFF00FF00);

      controller.selectColor(0xFF112233);
      controller.beginStroke();
      controller.paintAt(0, 1);
      controller.paintSegment(0, 1, 3, 1);
      controller.endStroke();
      expect(controller.pattern.beadCount, 8);
      expect(controller.pattern.cellAt(0, 0), 0xFF00FF00);
    });
  });
}
