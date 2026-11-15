// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../data/palettes.dart';
import '../models/bead_color.dart';
import '../models/pattern.dart';
import '../utils/color_utils.dart';

enum EditorTool { pen, eraser, fill, line, rectangle, eyedropper, pan }

enum CanvasStyle { bead, pixel }

/// Mutable editor state for one pattern, including frames, undo/redo and tools.
class EditorController extends ChangeNotifier {
  EditorController({required this.pattern, BeadPalette? palette})
    : palette = palette ?? mardPalette {
    currentColor = _initialColor();
    _recentColors.add(currentColor);
    final counts = pattern.colorCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in counts.take(9)) {
      if (!_recentColors.contains(entry.key)) _recentColors.add(entry.key);
    }
    selectedBead = _beadFor(currentColor);
  }

  final BeadPattern pattern;
  BeadPalette palette;

  late int currentColor;
  BeadColor? selectedBead;
  EditorTool tool = EditorTool.pen;
  CanvasStyle canvasStyle = CanvasStyle.bead;
  bool showGrid = true;

  /// Increments when the color, palette or recent colors change. Palette UI
  /// listens to this instead of the full editor to avoid rebuilding hundreds of
  /// swatches for every painted bead.
  final ValueNotifier<int> colorRevision = ValueNotifier<int>(0);

  int revision = 0;
  int _savedRevision = 0;
  int currentFrame = 0;

  final List<int> _recentColors = <int>[];
  final List<PatternSnapshot> _undo = <PatternSnapshot>[];
  final List<PatternSnapshot> _redo = <PatternSnapshot>[];
  PatternSnapshot? _strokeSnapshot;
  bool _notifyScheduled = false;
  bool _disposed = false;

  Uint32List get currentCells => pattern.frameAt(currentFrame);
  List<int> get recentColors => List<int>.unmodifiable(_recentColors);
  bool get isDirty => revision != _savedRevision;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  bool get isStroking => _strokeSnapshot != null;
  int get frameCount => pattern.frameCount;
  Map<int, int> get currentCounts => pattern.colorCountsFor(currentFrame);
  int get currentBeadCount => pattern.beadCountFor(currentFrame);
  int get currentColorCount => currentCounts.length;

  int get _totalCells => pattern.width * pattern.height * pattern.frameCount;

  int get _historyLimit {
    if (_totalCells <= 20000) return 80;
    if (_totalCells <= 60000) return 30;
    if (_totalCells <= 200000) return 12;
    return 4;
  }

  int _initialColor() {
    final counts = pattern.colorCounts;
    if (counts.isNotEmpty) {
      final mostUsed = counts.entries.reduce(
        (a, b) => a.value >= b.value ? a : b,
      );
      return mostUsed.key;
    }
    return mardPalette.colors
        .firstWhere(
          (c) => c.code == 'F4',
          orElse: () => mardPalette.colors.first,
        )
        .argb;
  }

  void markSaved([int? atRevision]) {
    _savedRevision = atRevision ?? revision;
    _notifyNow();
  }

  void rename(String title) {
    final next = title.trim();
    if (next.isEmpty || next == pattern.title) return;
    pattern.title = next;
    pattern.updatedAt = DateTime.now();
    revision++;
    _notifyNow();
  }

  void selectBead(BeadColor bead) {
    selectColor(bead.argb, bead: bead);
  }

  void selectColor(int argb, {BeadColor? bead}) {
    currentColor = opaque(argb);
    selectedBead = bead ?? _beadFor(currentColor);
    _rememberRecent(currentColor);
    if (tool == EditorTool.eraser || tool == EditorTool.eyedropper) {
      tool = EditorTool.pen;
    }
    colorRevision.value++;
    _notifyNow();
  }

  void setPalette(BeadPalette next) {
    if (next.id == palette.id) return;
    palette = next;
    selectedBead = _beadFor(currentColor);
    colorRevision.value++;
    _notifyNow();
  }

  void setTool(EditorTool next) {
    if (tool == next) return;
    tool = next;
    _notifyNow();
  }

  void setCanvasStyle(CanvasStyle next) {
    if (canvasStyle == next) return;
    canvasStyle = next;
    _notifyNow();
  }

  void toggleGrid() {
    showGrid = !showGrid;
    _notifyNow();
  }

  void switchFrame(int index) {
    _finishStrokeIfNeeded();
    final next = index.clamp(0, frameCount - 1);
    if (next == currentFrame) return;
    currentFrame = next;
    _notifyNow();
  }

  bool addFrame({bool duplicate = false}) {
    if (frameCount >= maxPatternFrames) return false;
    _finishStrokeIfNeeded();
    final before = pattern.snapshot();
    final source = duplicate
        ? Uint32List.fromList(currentCells)
        : Uint32List(pattern.width * pattern.height);
    pattern.addFrame(currentFrame + 1, cells: source);
    currentFrame++;
    _commitStructuralEdit(before);
    return true;
  }

  bool duplicateCurrentFrame() => addFrame(duplicate: true);

  bool deleteCurrentFrame() {
    if (frameCount <= 1) return false;
    _finishStrokeIfNeeded();
    final before = pattern.snapshot();
    pattern.removeFrameAt(currentFrame);
    if (currentFrame >= pattern.frameCount) {
      currentFrame = pattern.frameCount - 1;
    }
    _commitStructuralEdit(before);
    return true;
  }

  bool moveCurrentFrame(int delta) {
    final target = (currentFrame + delta).clamp(0, frameCount - 1);
    if (target == currentFrame) return false;
    _finishStrokeIfNeeded();
    final before = pattern.snapshot();
    pattern.moveFrame(currentFrame, target);
    currentFrame = target;
    _commitStructuralEdit(before);
    return true;
  }

  bool resizeCanvas(
    int width,
    int height, {
    FrameAnchor anchor = FrameAnchor.center,
  }) {
    if (width < 1 ||
        width > maxPatternDimension ||
        height < 1 ||
        height > maxPatternDimension) {
      return false;
    }
    if (width == pattern.width && height == pattern.height) return false;
    _finishStrokeIfNeeded();
    _runEdit(() => pattern.resize(width, height, anchor: anchor));
    if (currentFrame >= pattern.frameCount) {
      currentFrame = pattern.frameCount - 1;
    }
    return true;
  }

  void beginStroke() {
    _strokeSnapshot ??= pattern.snapshot();
  }

  void cancelStroke() {
    final before = _strokeSnapshot;
    _strokeSnapshot = null;
    if (before == null) return;
    if (pattern.matchesSnapshot(before)) return;
    pattern.restoreSnapshot(before);
    revision++;
    _notifyNow();
  }

  void paintAt(int x, int y) {
    final color = tool == EditorTool.eraser ? 0 : currentColor;
    if (pattern.setCellAt(x, y, color, frame: currentFrame)) {
      revision++;
      _notifySoon();
    }
  }

  /// Paints an interpolated segment during a drag and coalesces the repaint.
  void paintSegment(int x0, int y0, int x1, int y1) {
    final color = tool == EditorTool.eraser ? 0 : currentColor;
    var changed = false;
    for (final index in _lineIndexes(x0, y0, x1, y1)) {
      final x = index % pattern.width;
      final y = index ~/ pattern.width;
      if (pattern.setCellAt(x, y, color, frame: currentFrame)) changed = true;
    }
    if (changed) {
      revision++;
      _notifySoon();
    }
  }

  void endStroke() {
    final before = _strokeSnapshot;
    _strokeSnapshot = null;
    if (before == null) return;
    if (!pattern.matchesSnapshot(before)) {
      _pushUndo(before);
      pattern.updatedAt = DateTime.now();
      revision++;
      _notifyNow();
    }
  }

  void commitLine(int x0, int y0, int x1, int y1) {
    _runEdit(() {
      for (final index in _lineIndexes(x0, y0, x1, y1)) {
        _setIndex(index, currentColor);
      }
    });
  }

  void commitRectangle(int x0, int y0, int x1, int y1) {
    _runEdit(() {
      final left = x0 < x1 ? x0 : x1;
      final right = x0 < x1 ? x1 : x0;
      final top = y0 < y1 ? y0 : y1;
      final bottom = y0 < y1 ? y1 : y0;
      for (var x = left; x <= right; x++) {
        _setCellDirect(x, top, currentColor);
        _setCellDirect(x, bottom, currentColor);
      }
      for (var y = top; y <= bottom; y++) {
        _setCellDirect(left, y, currentColor);
        _setCellDirect(right, y, currentColor);
      }
    });
  }

  void floodFillAt(int x, int y) {
    if (!pattern.inBounds(x, y)) return;
    final target = pattern.cellAt(x, y, frame: currentFrame);
    final replacement = currentColor;
    if (target == replacement) return;

    _runEdit(() {
      final cells = currentCells;
      final stack = <int>[y * pattern.width + x];
      while (stack.isNotEmpty) {
        final index = stack.removeLast();
        if (cells[index] != target) continue;
        final px = index % pattern.width;
        final py = index ~/ pattern.width;
        pattern.setCellAt(px, py, replacement, frame: currentFrame);
        if (px > 0) stack.add(index - 1);
        if (px < pattern.width - 1) stack.add(index + 1);
        if (py > 0) stack.add(index - pattern.width);
        if (py < pattern.height - 1) stack.add(index + pattern.width);
      }
    });
  }

  void pickAt(int x, int y) {
    if (!pattern.inBounds(x, y)) return;
    final color = pattern.cellAt(x, y, frame: currentFrame);
    if (color == 0) return;
    selectColor(color);
  }

  void undo() {
    if (_strokeSnapshot != null || _undo.isEmpty) return;
    final current = pattern.snapshot();
    final previous = _undo.removeLast();
    _redo.add(current);
    pattern.restoreSnapshot(previous);
    if (currentFrame >= pattern.frameCount) {
      currentFrame = pattern.frameCount - 1;
    }
    pattern.updatedAt = DateTime.now();
    revision++;
    _notifyNow();
  }

  void redo() {
    if (_strokeSnapshot != null || _redo.isEmpty) return;
    final current = pattern.snapshot();
    final next = _redo.removeLast();
    _undo.add(current);
    pattern.restoreSnapshot(next);
    if (currentFrame >= pattern.frameCount) {
      currentFrame = pattern.frameCount - 1;
    }
    pattern.updatedAt = DateTime.now();
    revision++;
    _notifyNow();
  }

  void clearCanvas() {
    if (pattern.beadCountFor(currentFrame) == 0) return;
    _finishStrokeIfNeeded();
    _runEdit(() => pattern.clearFrame(currentFrame));
  }

  void _finishStrokeIfNeeded() {
    if (_strokeSnapshot != null) endStroke();
  }

  void _runEdit(void Function() body) {
    final before = pattern.snapshot();
    body();
    if (!pattern.matchesSnapshot(before)) {
      _commitStructuralEdit(before);
    }
  }

  void _commitStructuralEdit(PatternSnapshot before) {
    _pushUndo(before);
    pattern.updatedAt = DateTime.now();
    revision++;
    _notifyNow();
  }

  void _pushUndo(PatternSnapshot snapshot) {
    _undo.add(snapshot);
    if (_undo.length > _historyLimit) _undo.removeAt(0);
    _redo.clear();
  }

  void _setCellDirect(int x, int y, int color) {
    pattern.setCellAt(x, y, color, frame: currentFrame);
  }

  void _setIndex(int index, int color) {
    final x = index % pattern.width;
    final y = index ~/ pattern.width;
    _setCellDirect(x, y, color);
  }

  Iterable<int> _lineIndexes(int x0, int y0, int x1, int y1) sync* {
    var x = x0;
    var y = y0;
    final dx = (x1 - x0).abs();
    final dy = -(y1 - y0).abs();
    final sx = x0 < x1 ? 1 : -1;
    final sy = y0 < y1 ? 1 : -1;
    var error = dx + dy;

    while (true) {
      if (pattern.inBounds(x, y)) yield y * pattern.width + x;
      if (x == x1 && y == y1) break;
      final doubled = 2 * error;
      if (doubled >= dy) {
        error += dy;
        x += sx;
      }
      if (doubled <= dx) {
        error += dx;
        y += sy;
      }
    }
  }

  void _rememberRecent(int color) {
    _recentColors.remove(color);
    _recentColors.insert(0, color);
    if (_recentColors.length > 12) {
      _recentColors.removeRange(12, _recentColors.length);
    }
  }

  BeadColor? _beadFor(int argb) {
    for (final bead in palette.colors) {
      if (bead.argb == argb) return bead;
    }
    return builtInBeadForColor(argb);
  }

  void _notifyNow() {
    if (_disposed) return;
    notifyListeners();
  }

  /// Coalesces high-frequency drawing notifications to at most one per frame.
  void _notifySoon() {
    if (_disposed || _notifyScheduled) return;
    _notifyScheduled = true;
    try {
      SchedulerBinding.instance.scheduleFrameCallback((_) {
        _notifyScheduled = false;
        if (!_disposed) notifyListeners();
      });
      SchedulerBinding.instance.scheduleFrame();
    } on Object {
      _notifyScheduled = false;
      scheduleMicrotask(() {
        if (!_disposed) notifyListeners();
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    colorRevision.dispose();
    super.dispose();
  }
}
