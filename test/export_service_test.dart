// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:typed_data';

import 'package:bead_studio/data/palettes.dart';
import 'package:bead_studio/models/pattern.dart';
import 'package:bead_studio/services/export_service.dart';
import 'package:bead_studio/services/pattern_image_service.dart';
import 'package:bead_studio/state/editor_controller.dart';
import 'package:bead_studio/widgets/bead_canvas.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('material CSV contains a BOM, header and sorted counts', () {
    final pattern = BeadPattern.blank(title: '测试', width: 3, height: 3);
    pattern.setCellAt(0, 0, 0xFFE85D75);
    pattern.setCellAt(1, 0, 0xFFE85D75);
    pattern.setCellAt(2, 0, 0xFF2BA39A);

    final csv = ExportService.materialsCsv(pattern, palette: mardPalette);
    expect(csv.startsWith('\uFEFF品牌,色号,名称,颜色,数量'), isTrue);
    final lines = csv.trim().split('\n');
    expect(lines.length, 3);
    expect(lines[1], contains('#E85D75'));
    expect(lines[1], contains(',2'));
    expect(lines[2], contains('#2BA39A'));
  });

  test('safe filenames strip forbidden path characters', () {
    expect(
      ExportService.safeFilename('a/b:c*?"<>|d', '.png'),
      'a_b_c______d.png',
    );
    expect(ExportService.safeFilename('   ', '.png'), '拼豆作品.png');
  });

  testWidgets('renders a pattern PNG with the PNG signature', (tester) async {
    final pattern = BeadPattern.blank(title: '导出测试', width: 6, height: 5);
    pattern.setCellAt(0, 0, 0xFFE85D75);
    pattern.setCellAt(1, 1, 0xFF2BA39A);
    pattern.setCellAt(5, 4, 0xFFF2B23E);

    late Uint8List bytes;
    await tester.runAsync(() async {
      bytes = await renderPatternPng(
        pattern: pattern,
        style: CanvasStyle.bead,
        showGrid: true,
        showLegend: true,
        showHeader: true,
        palette: mardPalette,
      );
    });

    expect(bytes.length, greaterThan(200));
    expect(bytes.sublist(0, 8), <int>[137, 80, 78, 71, 13, 10, 26, 10]);
  });

  testWidgets('bead canvas paints cells from a drag', (tester) async {
    final pattern = BeadPattern.blank(title: '画布', width: 8, height: 8);
    final controller = EditorController(pattern: pattern);
    addTearDown(controller.dispose);

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

    final center = tester.getCenter(find.byType(BeadCanvas));
    final gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(pattern.beadCount, greaterThan(0));
    expect(controller.canUndo, isTrue);

    controller.undo();
    expect(pattern.beadCount, 0);
  });
}
