// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

import '../utils/rle.dart';

const int maxPatternDimension = 400;
const String patternFormatId = 'bead-studio-pattern';
const int maxPatternFrames = 120;

enum FrameAnchor { topLeft, center }

class PatternSnapshot {
  PatternSnapshot({
    required this.width,
    required this.height,
    required this.frames,
  });

  factory PatternSnapshot.capture(BeadPattern pattern) => PatternSnapshot(
    width: pattern.width,
    height: pattern.height,
    frames: pattern.frames
        .map((cells) => Uint32List.fromList(cells))
        .toList(growable: false),
  );

  final int width;
  final int height;
  final List<Uint32List> frames;
}

class BeadPattern {
  BeadPattern({
    required this.id,
    required this.title,
    required int width,
    required int height,
    required List<Uint32List> frames,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : _width = width,
       _height = height,
       frames = frames
           .map((cells) => _normalizeFrame(cells, width, height))
           .toList(growable: true),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now() {
    if (width < 1 || width > maxPatternDimension) {
      throw ArgumentError.value(width, 'width', '画布宽度超出范围');
    }
    if (height < 1 || height > maxPatternDimension) {
      throw ArgumentError.value(height, 'height', '画布高度超出范围');
    }
    if (this.frames.isEmpty || this.frames.length > maxPatternFrames) {
      throw ArgumentError.value(this.frames.length, 'frames', '帧数量超出范围');
    }
    _resetCaches();
  }

  factory BeadPattern.blank({
    String? id,
    required String title,
    required int width,
    required int height,
  }) {
    final w = width < 1
        ? 1
        : width > maxPatternDimension
        ? maxPatternDimension
        : width;
    final h = height < 1
        ? 1
        : height > maxPatternDimension
        ? maxPatternDimension
        : height;
    return BeadPattern(
      id: id ?? generatePatternId(),
      title: title.trim().isEmpty ? '未命名作品' : title.trim(),
      width: w,
      height: h,
      frames: <Uint32List>[Uint32List(w * h)],
    );
  }

  factory BeadPattern.fromJson(Map<String, Object?> json) {
    if (json['format'] != patternFormatId) {
      throw const FormatException('不是拼豆工坊工程文件');
    }
    final version = json['version'];
    if (version is! int || version < 1 || version > 2) {
      throw const FormatException('不支持的工程版本');
    }
    final width = json['width'];
    final height = json['height'];
    if (width is! int ||
        height is! int ||
        width < 1 ||
        height < 1 ||
        width > maxPatternDimension ||
        height > maxPatternDimension) {
      throw const FormatException('画布尺寸无效');
    }
    final expectedLength = width * height;

    final List<Uint32List> frames;
    final rawFrames = json['frames'];
    if (version >= 2 && rawFrames is List && rawFrames.isNotEmpty) {
      if (rawFrames.length > maxPatternFrames) {
        throw const FormatException('帧数量过多');
      }
      frames = <Uint32List>[];
      for (final raw in rawFrames) {
        if (raw is! String) {
          throw const FormatException('帧数据格式无效');
        }
        frames.add(decodeRle(raw, expectedLength));
      }
    } else {
      final rawCells = json['cells'];
      if (rawCells is! String) {
        throw const FormatException('缺少画布数据');
      }
      frames = <Uint32List>[
        decodeRle(rawCells, expectedLength),
      ];
    }

    final id = json['id'];
    final title = json['title'];
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '');
    final updatedAt = DateTime.tryParse(json['updatedAt'] as String? ?? '');
    return BeadPattern(
      id: id is String && id.isNotEmpty ? id : generatePatternId(),
      title: title is String && title.trim().isNotEmpty
          ? title.trim()
          : '未命名作品',
      width: width,
      height: height,
      frames: frames,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  factory BeadPattern.fromJsonString(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('工程文件内容无效');
    }
    return BeadPattern.fromJson(decoded);
  }

  final String id;
  String title;
  final List<Uint32List> frames;
  final DateTime createdAt;
  DateTime updatedAt;

  int _width;
  int _height;
  List<Map<int, int>?> _counts = <Map<int, int>?>[];
  List<int?> _beadCounts = <int?>[];

  int get width => _width;
  int get height => _height;
  int get frameCount => frames.length;
  int get length => _width * _height;

  /// Backwards-compatible access to the first frame.
  Uint32List get cells => frames.first;

  Uint32List frameAt(int index) => frames[index.clamp(0, frames.length - 1)];

  bool inBounds(int x, int y) =>
      x >= 0 && y >= 0 && x < _width && y < _height;

  int cellAt(int x, int y, {int frame = 0}) {
    if (!inBounds(x, y)) return 0;
    return frames[frame][y * _width + x];
  }

  bool setCellAt(int x, int y, int argb, {int frame = 0}) {
    if (!inBounds(x, y)) return false;
    final index = y * _width + x;
    final cellIndex = index;
    final cells = frames[frame];
    final previous = cells[cellIndex];
    if (previous == argb) return false;
    final cached = _counts.length > frame ? _counts[frame] : null;
    if (cached != null) {
      if (previous != 0) {
        final count = (cached[previous] ?? 1) - 1;
        if (count <= 0) {
          cached.remove(previous);
        } else {
          cached[previous] = count;
        }
      }
      if (argb != 0) {
        cached[argb] = (cached[argb] ?? 0) + 1;
      }
    }
    if (_beadCounts.length > frame) {
      _beadCounts[frame] = null;
    }
    cells[cellIndex] = argb;
    return true;
  }

  void replaceFrame(int frame, Uint32List next) {
    frames[frame] = _normalizeFrame(next, _width, _height);
    _invalidateFrame(frame);
  }

  void clearFrame(int frame) {
    frames[frame] = Uint32List(_width * _height);
    _invalidateFrame(frame);
  }

  /// Backwards-compatible aliases for the first frame.
  void replaceCells(Uint32List next) => replaceFrame(0, next);

  void clear() => clearFrame(0);

  Map<int, int> colorCountsFor(int frame) {
    _ensureCaches();
    final cached = _counts[frame];
    if (cached != null) return Map<int, int>.unmodifiable(cached);
    final counts = <int, int>{};
    for (final value in frames[frame]) {
      if (value == 0) continue;
      counts[value] = (counts[value] ?? 0) + 1;
    }
    _counts[frame] = counts;
    return Map<int, int>.unmodifiable(counts);
  }

  Map<int, int> get colorCounts => colorCountsFor(0);

  int beadCountFor(int frame) {
    _ensureCaches();
    final cached = _beadCounts[frame];
    if (cached != null) return cached;
    var count = 0;
    for (final value in frames[frame]) {
      if (value != 0) count++;
    }
    _beadCounts[frame] = count;
    return count;
  }

  int get beadCount => beadCountFor(0);

  int get totalBeadCount {
    var total = 0;
    for (var i = 0; i < frames.length; i++) {
      total += beadCountFor(i);
    }
    return total;
  }

  int get usedColorCount => colorCountsFor(0).length;

  int usedColorCountFor(int frame) => colorCountsFor(frame).length;

  int get totalColorCount {
    final colors = <int>{};
    for (var i = 0; i < frames.length; i++) {
      colors.addAll(colorCountsFor(i).keys);
    }
    return colors.length;
  }

  void addFrame(int index, {Uint32List? cells}) {
    if (frames.length >= maxPatternFrames) {
      throw StateError('最多支持 $maxPatternFrames 帧');
    }
    final position = index.clamp(0, frames.length);
    frames.insert(
      position,
      _normalizeFrame(cells ?? Uint32List(_width * _height), _width, _height),
    );
    _counts.insert(position, null);
    _beadCounts.insert(position, null);
  }

  void removeFrameAt(int index) {
    if (frames.length <= 1) {
      throw StateError('至少保留一帧');
    }
    frames.removeAt(index);
    _counts.removeAt(index);
    _beadCounts.removeAt(index);
  }

  void moveFrame(int from, int to) {
    if (from == to) return;
    final frame = frames.removeAt(from);
    frames.insert(to, frame);
    final counts = _counts.removeAt(from);
    _counts.insert(to, counts);
    final beadCount = _beadCounts.removeAt(from);
    _beadCounts.insert(to, beadCount);
  }

  void resize(int width, int height, {FrameAnchor anchor = FrameAnchor.center}) {
    if (width < 1 ||
        width > maxPatternDimension ||
        height < 1 ||
        height > maxPatternDimension) {
      throw ArgumentError('画布尺寸超出范围');
    }
    final dx = anchor == FrameAnchor.center
        ? ((width - _width) / 2).floor()
        : 0;
    final dy = anchor == FrameAnchor.center
        ? ((height - _height) / 2).floor()
        : 0;
    final resized = <Uint32List>[];
    for (final cells in frames) {
      final next = Uint32List(width * height);
      for (var y = 0; y < _height; y++) {
        for (var x = 0; x < _width; x++) {
          final value = cells[y * _width + x];
          if (value == 0) continue;
          final nx = x + dx;
          final ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
          next[ny * width + nx] = value;
        }
      }
      resized.add(next);
    }
    _width = width;
    _height = height;
    frames
      ..clear()
      ..addAll(resized);
    _resetCaches();
  }

  PatternSnapshot snapshot() => PatternSnapshot.capture(this);

  void restoreSnapshot(PatternSnapshot snapshot) {
    _width = snapshot.width;
    _height = snapshot.height;
    frames
      ..clear()
      ..addAll(
        snapshot.frames.map((cells) => Uint32List.fromList(cells)),
      );
    _resetCaches();
  }

  bool matchesSnapshot(PatternSnapshot snapshot) {
    if (_width != snapshot.width ||
        _height != snapshot.height ||
        frames.length != snapshot.frames.length) {
      return false;
    }
    for (var f = 0; f < frames.length; f++) {
      final current = frames[f];
      final previous = snapshot.frames[f];
      if (current.length != previous.length) return false;
      for (var i = 0; i < current.length; i++) {
        if (current[i] != previous[i]) return false;
      }
    }
    return true;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'format': patternFormatId,
    'version': 2,
    'id': id,
    'title': title,
    'width': _width,
    'height': _height,
    'frames': frames.map(encodeRle).toList(growable: false),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  BeadPattern copyWithId(String newId) => BeadPattern(
    id: newId,
    title: title,
    width: _width,
    height: _height,
    frames: frames.map((cells) => Uint32List.fromList(cells)).toList(),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  void _ensureCaches() {
    if (_counts.length == frames.length) return;
    _resetCaches();
  }

  void _resetCaches() {
    _counts = List<Map<int, int>?>.filled(frames.length, null, growable: true);
    _beadCounts = List<int?>.filled(frames.length, null, growable: true);
  }

  void _invalidateFrame(int frame) {
    if (frame >= 0 && frame < _counts.length) {
      _counts[frame] = null;
      _beadCounts[frame] = null;
    }
  }

  static Uint32List _normalizeFrame(
    Uint32List cells,
    int width,
    int height,
  ) {
    final length = width * height;
    if (cells.length == length) return cells;
    final normalized = Uint32List(length);
    final copyLength = cells.length < length ? cells.length : length;
    normalized.setRange(0, copyLength, cells);
    return normalized;
  }
}

String generatePatternId() {
  final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final salt = DateTime.now().hashCode.toRadixString(36);
  return '$now$salt';
}
