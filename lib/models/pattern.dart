// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../utils/rle.dart';

const int maxPatternDimension = 400;
const String patternFormatId = 'bead-studio-pattern';

String generatePatternId() {
  final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final salt = Random().nextInt(0xFFFFFF).toRadixString(36).padLeft(4, '0');
  return '$time$salt';
}

class BeadPattern {
  BeadPattern({
    required this.id,
    required this.title,
    required this.width,
    required this.height,
    required Uint32List cells,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : cells = cells.length == width * height
           ? cells
           : _fitCells(cells, width, height),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  factory BeadPattern.blank({
    String? id,
    required String title,
    required int width,
    required int height,
  }) {
    final w = width.clamp(1, maxPatternDimension);
    final h = height.clamp(1, maxPatternDimension);
    return BeadPattern(
      id: id ?? generatePatternId(),
      title: title.trim().isEmpty ? '未命名作品' : title.trim(),
      width: w,
      height: h,
      cells: Uint32List(w * h),
    );
  }

  factory BeadPattern.fromJson(Map<String, dynamic> json) {
    if (json['format'] != patternFormatId) {
      throw const FormatException('不是拼豆工坊工程文件');
    }
    final version = json['version'];
    if (version is! int || version > 1) {
      throw const FormatException('工程文件版本不受支持');
    }
    final width = json['width'];
    final height = json['height'];
    if (width is! int || height is! int) {
      throw const FormatException('画布尺寸无效');
    }
    if (width < 1 ||
        height < 1 ||
        width > maxPatternDimension ||
        height > maxPatternDimension) {
      throw const FormatException('画布尺寸超出支持范围');
    }
    final rawCells = json['cells'];
    if (rawCells is! String) {
      throw const FormatException('画布数据缺失');
    }
    final encoding = json['encoding'] ?? 'rle';
    if (encoding != 'rle') {
      throw const FormatException('不支持的画布编码');
    }
    return BeadPattern(
      id: json['id'] is String && (json['id'] as String).isNotEmpty
          ? json['id'] as String
          : generatePatternId(),
      title: json['title'] is String ? json['title'] as String : '未命名作品',
      width: width,
      height: height,
      cells: decodeRle(rawCells, width * height),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
    );
  }

  factory BeadPattern.fromJsonString(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('工程文件内容无效');
    }
    return BeadPattern.fromJson(decoded);
  }

  final String id;
  String title;
  final int width;
  final int height;
  final Uint32List cells;
  final DateTime createdAt;
  DateTime updatedAt;

  Map<int, int>? _counts;
  int? _beadCount;

  int get length => cells.length;

  bool inBounds(int x, int y) => x >= 0 && y >= 0 && x < width && y < height;

  int cellAt(int x, int y) {
    if (!inBounds(x, y)) return 0;
    return cells[y * width + x];
  }

  bool setCellAt(int x, int y, int argb) {
    if (!inBounds(x, y)) return false;
    final index = y * width + x;
    final previous = cells[index];
    if (previous == argb) return false;
    cells[index] = argb;

    if (_counts != null) {
      if (previous != 0) {
        final next = (_counts![previous] ?? 0) - 1;
        if (next <= 0) {
          _counts!.remove(previous);
        } else {
          _counts![previous] = next;
        }
      }
      if (argb != 0) {
        _counts![argb] = (_counts![argb] ?? 0) + 1;
      }
      _beadCount = null;
    }
    return true;
  }

  void replaceCells(Uint32List next) {
    if (next.length != cells.length) {
      throw ArgumentError.value(next.length, 'next', '长度与画布不一致');
    }
    cells.setAll(0, next);
    _counts = null;
    _beadCount = null;
  }

  void clear() {
    cells.fillRange(0, cells.length, 0);
    _counts = null;
    _beadCount = null;
  }

  Map<int, int> get colorCounts {
    final cached = _counts;
    if (cached != null) return Map<int, int>.unmodifiable(cached);
    final counts = <int, int>{};
    for (final value in cells) {
      if (value != 0) counts[value] = (counts[value] ?? 0) + 1;
    }
    _counts = counts;
    return Map<int, int>.unmodifiable(counts);
  }

  int get beadCount {
    final cached = _beadCount;
    if (cached != null) return cached;
    var total = 0;
    for (final count in colorCounts.values) {
      total += count;
    }
    _beadCount = total;
    return total;
  }

  int get usedColorCount => colorCounts.length;

  BeadPattern copyWithId(String newId) => BeadPattern(
    id: newId,
    title: title,
    width: width,
    height: height,
    cells: Uint32List.fromList(cells),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'format': patternFormatId,
    'version': 1,
    'id': id,
    'title': title,
    'width': width,
    'height': height,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'encoding': 'rle',
    'cells': encodeRle(cells),
  };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  static Uint32List _fitCells(Uint32List source, int width, int height) {
    final result = Uint32List(width * height);
    final copyLength = min(source.length, result.length);
    if (copyLength > 0) result.setRange(0, copyLength, source);
    return result;
  }
}
