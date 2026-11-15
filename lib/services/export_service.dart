// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';
import 'dart:typed_data';

import '../models/bead_color.dart';
import '../models/pattern.dart';
import '../state/editor_controller.dart';
import '../utils/bead_lookup.dart';
import '../utils/color_utils.dart';
import 'pattern_image_service.dart';
import 'platform_files.dart' as files;

class ExportService {
  static bool get isMobile => files.isMobilePlatform;

  static bool get canSaveToDisk => files.canSaveToDisk;

  static Future<Uint8List> renderPattern({
    required BeadPattern pattern,
    required CanvasStyle style,
    required bool showGrid,
    required bool showLegend,
    required bool showHeader,
    BeadPalette? palette,
    int frameIndex = 0,
  }) => renderPatternPng(
    pattern: pattern,
    style: style,
    showGrid: showGrid,
    showLegend: showLegend,
    showHeader: showHeader,
    palette: palette,
    frameIndex: frameIndex,
  );

  static Future<String?> saveFile({
    required Uint8List bytes,
    required String filename,
    required String mime,
    required List<String> extensions,
  }) => files.saveBytesToDisk(
    bytes: bytes,
    filename: filename,
    mime: mime,
    extensions: extensions,
  );

  static Future<String?> shareFile({
    required Uint8List bytes,
    required String filename,
    required String mime,
    String? text,
  }) => files.shareBytesFile(
    bytes: bytes,
    filename: filename,
    mime: mime,
    text: text,
  );

  static Uint8List textBytes(String text) =>
      Uint8List.fromList(utf8.encode(text));

  static String safeFilename(String title, String extension) {
    var base = title
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'^\.+|\.+$'), '');
    if (base.isEmpty) base = '拼豆作品';
    if (base.length > 60) base = base.substring(0, 60);
    final ext = extension.startsWith('.') ? extension : '.$extension';
    return '$base$ext';
  }

  static String materialsCsv(
    BeadPattern pattern, {
    BeadPalette? palette,
    int frameIndex = 0,
  }) {
    final frame = frameIndex.clamp(0, pattern.frameCount - 1);
    final buffer = StringBuffer('\uFEFF品牌,色号,名称,颜色,数量\n');
    final entries = pattern.colorCountsFor(frame).entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in entries) {
      final bead = findBeadForColor(entry.key, preferred: palette);
      buffer.writeln(
        '${_csv(bead?.brand ?? '自定义')},'
        '${_csv(bead?.code ?? formatHex(entry.key))},'
        '${_csv(bead?.name ?? '自定义颜色')},'
        '${formatHex(entry.key)},'
        '${entry.value}',
      );
    }
    return buffer.toString();
  }

  static String materialsText(
    BeadPattern pattern, {
    BeadPalette? palette,
    int frameIndex = 0,
  }) {
    final frame = frameIndex.clamp(0, pattern.frameCount - 1);
    final buffer = StringBuffer()
      ..writeln('拼豆工坊 · 材料清单')
      ..writeln('作品：${pattern.title}')
      ..writeln('尺寸：${pattern.width} × ${pattern.height}')
      ..writeln(
        '总计：${pattern.beadCountFor(frame)} 颗，'
        '${pattern.usedColorCountFor(frame)} 种颜色',
      )
      ..writeln();
    final entries = pattern.colorCountsFor(frame).entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in entries) {
      final bead = findBeadForColor(entry.key, preferred: palette);
      final prefix = bead == null
          ? formatHex(entry.key)
          : '${bead.brand} ${bead.code}';
      final name = bead == null ? '自定义颜色' : bead.name;
      buffer.writeln('$prefix  $name  ${entry.value} 颗');
    }
    return buffer.toString();
  }

  static String _csv(String value) {
    if (!value.contains(',') && !value.contains('"') && !value.contains('\n')) {
      return value;
    }
    return '"${value.replaceAll('"', '""')}"';
  }
}
