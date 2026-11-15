// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../models/bead_color.dart';
import '../models/pattern.dart';
import '../state/editor_controller.dart';
import '../utils/bead_lookup.dart';
import '../utils/color_utils.dart';

/// Renders a pattern into a shareable PNG card entirely with dart:ui so the
/// result is independent of screen size and can be as large as needed.
Future<Uint8List> renderPatternPng({
  required BeadPattern pattern,
  required CanvasStyle style,
  required bool showGrid,
  required bool showLegend,
  required bool showHeader,
  BeadPalette? palette,
  int frameIndex = 0,
}) async {
  final frame = frameIndex.clamp(0, pattern.frameCount - 1);
  final cells = pattern.frameAt(frame);
  const padding = 30.0;
  const headerHeight = 62.0;
  const footerHeight = 34.0;
  const legendHeading = 30.0;
  const legendRowHeight = 24.0;
  const legendGap = 26.0;
  const maxGraphicSide = 3000.0;

  final maxCells = math.max(pattern.width, pattern.height);
  var cellSize = 24.0;
  if (maxCells * cellSize > maxGraphicSide) {
    cellSize = math.max(3.0, (maxGraphicSide / maxCells).floorToDouble());
  }
  final gridWidth = pattern.width * cellSize;
  final gridHeight = pattern.height * cellSize;

  final counts = pattern.colorCountsFor(frame).entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final legendColumns = showLegend && counts.isNotEmpty
      ? math.min(5, counts.length)
      : 0;
  const legendColumnWidth = 210.0;
  final legendRows = legendColumns == 0
      ? 0
      : (counts.length / legendColumns).ceil();
  final legendHeight = legendColumns == 0
      ? 0.0
      : legendHeading + legendRows * legendRowHeight + 18;

  final contentWidth = math.max(
    gridWidth,
    legendColumns == 0 ? 0.0 : legendColumns * legendColumnWidth,
  );
  final width = contentWidth + padding * 2;
  final height =
      padding +
      (showHeader ? headerHeight : 0) +
      gridHeight +
      (showLegend ? legendGap + legendHeight : 0) +
      footerHeight +
      padding;

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final imageWidth = width.ceil();
  final imageHeight = height.ceil();
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, imageWidth.toDouble(), imageHeight.toDouble()),
    ui.Paint()..color = const Color(0xFFFFFFFF),
  );

  var cursorY = padding;

  if (showHeader) {
    _paintText(
      canvas,
      pattern.title,
      ui.Offset(padding, cursorY),
      const TextStyle(
        color: Color(0xFF2A2420),
        fontSize: 26,
        fontWeight: FontWeight.w700,
        height: 1.15,
      ),
      maxWidth: width - padding * 2,
    );
    _paintText(
      canvas,
      '${pattern.width} × ${pattern.height}  ·  '
      '${_formatCount(pattern.beadCountFor(frame))} 颗豆  ·  '
      '${pattern.usedColorCountFor(frame)} 种颜色',
      ui.Offset(padding, cursorY + 34),
      const TextStyle(color: Color(0xFF8A8178), fontSize: 13, height: 1.2),
      maxWidth: width - padding * 2,
    );
    cursorY += headerHeight;
  }

  final gridRect = ui.Rect.fromLTWH(padding, cursorY, gridWidth, gridHeight);
  _paintPattern(
    canvas: canvas,
    pattern: pattern,
    cells: cells,
    rect: gridRect,
    cellSize: cellSize,
    style: style,
    showGrid: showGrid,
  );
  cursorY += gridHeight;

  if (showLegend && counts.isNotEmpty) {
    cursorY += legendGap;
    _paintText(
      canvas,
      '材料清单',
      ui.Offset(padding, cursorY),
      const TextStyle(
        color: Color(0xFF2A2420),
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
      maxWidth: contentWidth,
    );
    cursorY += legendHeading;

    for (var i = 0; i < counts.length; i++) {
      final column = i % legendColumns;
      final row = i ~/ legendColumns;
      final x = padding + column * legendColumnWidth;
      final y = cursorY + row * legendRowHeight;
      final color = counts[i].key;
      final count = counts[i].value;
      final bead = findBeadForColor(color, preferred: palette);
      final label = bead == null
          ? formatHex(color)
          : '${bead.brand} ${bead.code}';
      final center = ui.Offset(x + 9, y + 9);
      canvas.drawCircle(center, 8, ui.Paint()..color = Color(color));
      canvas.drawCircle(
        center,
        8,
        ui.Paint()
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0x33000000),
      );
      _paintText(
        canvas,
        '$label  × ${_formatCount(count)}',
        ui.Offset(x + 24, y + 1),
        const TextStyle(color: Color(0xFF4A423B), fontSize: 12, height: 1.25),
        maxWidth: legendColumnWidth - 30,
      );
    }
    cursorY += legendRows * legendRowHeight + 18;
  }

  final footerY = imageHeight - padding - 16;
  _paintText(
    canvas,
    '拼豆工坊 · Bead Studio',
    ui.Offset(padding, footerY),
    const TextStyle(color: Color(0xFFA39A90), fontSize: 10),
    maxWidth: contentWidth * 0.6,
  );
  _paintText(
    canvas,
    'GPL-3.0-or-later',
    ui.Offset(padding, footerY),
    const TextStyle(color: Color(0xFFA39A90), fontSize: 10),
    maxWidth: contentWidth * 0.6,
    alignRightAt: padding + contentWidth,
  );

  final picture = recorder.endRecording();
  final image = await picture.toImage(imageWidth, imageHeight);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) {
    throw StateError('无法生成图片');
  }
  return data.buffer.asUint8List();
}

void _paintPattern({
  required ui.Canvas canvas,
  required BeadPattern pattern,
  required Uint32List cells,
  required ui.Rect rect,
  required double cellSize,
  required CanvasStyle style,
  required bool showGrid,
}) {
  final boardPaint = ui.Paint()..color = const Color(0xFFF6F0E4);
  final borderRadius = ui.Radius.circular(math.min(8, cellSize * 0.35));
  canvas.drawRRect(ui.RRect.fromRectAndRadius(rect, borderRadius), boardPaint);

  final pegPaint = ui.Paint()..color = const Color(0xFFE6DCCB);
  final borderPaint = ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = math.max(1, cellSize * 0.03)
    ..color = const Color(0xFFD9CEBB);

  canvas.save();
  canvas.clipRRect(ui.RRect.fromRectAndRadius(rect, borderRadius));

  for (var y = 0; y < pattern.height; y++) {
    for (var x = 0; x < pattern.width; x++) {
      final argb = cells[y * pattern.width + x];
      final cellRect = ui.Rect.fromLTWH(
        rect.left + x * cellSize,
        rect.top + y * cellSize,
        cellSize,
        cellSize,
      );

      if (argb == 0) {
        if (cellSize >= 8) {
          canvas.drawCircle(
            cellRect.center,
            math.max(0.8, cellSize * 0.07),
            pegPaint,
          );
        }
        continue;
      }

      if (style == CanvasStyle.pixel) {
        final inset = math.max(0.4, cellSize * 0.045);
        canvas.drawRect(
          cellRect.deflate(inset),
          ui.Paint()..color = Color(argb),
        );
        continue;
      }

      final center = cellRect.center;
      final radius = cellSize * 0.46;
      canvas.drawCircle(center, radius, ui.Paint()..color = Color(argb));
      canvas.drawCircle(
        center,
        radius,
        ui.Paint()
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = math.max(0.7, cellSize * 0.035)
          ..color = Color(darken(argb, 0.2)).withValues(alpha: 0.55),
      );
      if (cellSize >= 7) {
        canvas.drawCircle(
          center + ui.Offset(-radius * 0.27, -radius * 0.27),
          radius * 0.3,
          ui.Paint()..color = const Color(0x45FFFFFF),
        );
        canvas.drawCircle(
          center,
          radius * 0.16,
          ui.Paint()..color = Color(darken(argb, 0.32)).withValues(alpha: 0.45),
        );
      }
    }
  }

  canvas.restore();

  if (showGrid && cellSize >= 6) {
    final thin = ui.Paint()
      ..color = const Color(0x16000000)
      ..strokeWidth = math.max(0.5, cellSize * 0.025);
    final thick = ui.Paint()
      ..color = const Color(0x2A000000)
      ..strokeWidth = math.max(0.8, cellSize * 0.045);
    for (var x = 1; x < pattern.width; x++) {
      final paint = x % 10 == 0 ? thick : thin;
      final dx = rect.left + x * cellSize;
      canvas.drawLine(
        ui.Offset(dx, rect.top),
        ui.Offset(dx, rect.bottom),
        paint,
      );
    }
    for (var y = 1; y < pattern.height; y++) {
      final paint = y % 10 == 0 ? thick : thin;
      final dy = rect.top + y * cellSize;
      canvas.drawLine(
        ui.Offset(rect.left, dy),
        ui.Offset(rect.right, dy),
        paint,
      );
    }
  }

  canvas.drawRRect(ui.RRect.fromRectAndRadius(rect, borderRadius), borderPaint);
}

void _paintText(
  ui.Canvas canvas,
  String text,
  ui.Offset offset,
  TextStyle style, {
  required double maxWidth,
  double? alignRightAt,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: ui.TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: maxWidth);
  final dx = alignRightAt == null ? offset.dx : alignRightAt - painter.width;
  painter.paint(canvas, ui.Offset(dx, offset.dy));
}

String _formatCount(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
