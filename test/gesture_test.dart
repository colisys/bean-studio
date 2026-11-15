// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:bead_studio/models/pattern.dart';
import 'package:bead_studio/state/editor_controller.dart';
import 'package:bead_studio/widgets/bead_canvas.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpCanvas(
  WidgetTester tester,
  EditorController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            height: 400,
            child: BeadCanvas(controller: controller),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('two-finger pinch zooms the canvas without painting', (
    tester,
  ) async {
    final pattern = BeadPattern.blank(title: 'canvas', width: 12, height: 12);
    final controller = EditorController(pattern: pattern);
    addTearDown(controller.dispose);
    await _pumpCanvas(tester, controller);

    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final transform = viewer.transformationController!;
    final beforeScale = transform.value.getMaxScaleOnAxis();

    final center = tester.getCenter(find.byType(BeadCanvas));
    final first = await tester.startGesture(center - const Offset(20, 0));
    final second = await tester.startGesture(center + const Offset(20, 0));
    await tester.pump();
    await first.moveTo(center - const Offset(70, 0));
    await second.moveTo(center + const Offset(70, 0));
    await tester.pump();
    await first.up();
    await second.up();
    await tester.pumpAndSettle();

    final afterScale = transform.value.getMaxScaleOnAxis();
    expect(afterScale, greaterThan(beforeScale * 1.05));
    expect(pattern.beadCount, 0);
  });

  testWidgets('two-finger pan moves the canvas', (tester) async {
    final pattern = BeadPattern.blank(title: 'canvas', width: 12, height: 12);
    final controller = EditorController(pattern: pattern);
    addTearDown(controller.dispose);
    await _pumpCanvas(tester, controller);

    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final transform = viewer.transformationController!;
    final before = transform.value.getTranslation();

    final center = tester.getCenter(find.byType(BeadCanvas));
    final first = await tester.startGesture(center - const Offset(20, 0));
    final second = await tester.startGesture(center + const Offset(20, 0));
    await tester.pump();
    await first.moveBy(const Offset(45, 25));
    await second.moveBy(const Offset(45, 25));
    await tester.pump();
    await first.up();
    await second.up();
    await tester.pumpAndSettle();

    final after = transform.value.getTranslation();
    expect((after.x - before.x).abs() + (after.y - before.y).abs(), greaterThan(5));
    expect(pattern.beadCount, 0);
  });

  testWidgets('pan tool moves the canvas on one-finger drag', (tester) async {
    final pattern = BeadPattern.blank(title: 'canvas', width: 12, height: 12);
    final controller = EditorController(pattern: pattern);
    addTearDown(controller.dispose);
    controller.setTool(EditorTool.pan);
    await _pumpCanvas(tester, controller);

    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final transform = viewer.transformationController!;
    final before = transform.value.getTranslation();

    final center = tester.getCenter(find.byType(BeadCanvas));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(50, 30));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final after = transform.value.getTranslation();
    expect((after.x - before.x).abs() + (after.y - before.y).abs(), greaterThan(5));
    expect(pattern.beadCount, 0);
  });
}
