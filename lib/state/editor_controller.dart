// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../data/palettes.dart';
import '../models/bead_color.dart';
import '../models/pattern.dart';
import '../utils/color_utils.dart';

enum EditorTool { pen, eraser, fill, line, rectangle, eyedropper, pan }

enum CanvasStyle { bead, pixel }

/// Mutable editor state for one pattern, including undo/redo and tool state.
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

  int revision = 0;
  int _savedRevision = 0;

  final List<int> _recentColors = <int>[];
  final List<Uint32List> _undo = <Uint32List>[];
  final List<Uint32List> _redo = <Uint32List>[];
  Uint32List? _strokeSnapshot;

  Uint32List get cells => pattern.cells;
  List<int> get recentColors => List<int>.unmodifiable(_recentColors);
  bool get isDirty => revision != _savedRevision;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  bool get isStroking => _strokeSnapshot != null;

  int get _historyLimit =>
      cells.length > 60000 ? 20 : (cells.length > 20000 ? 40 : 80);

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
    notifyListeners();
  }

  void rename(String title) {
    final next = title.trim();
    if (next.isEmpty || next == pattern.title) return;
    pattern.title = next;
    pattern.updatedAt = DateTime.now();
    revision++;
    notifyListeners();
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
    notifyListeners();
  }

  void setPalette(BeadPalette next) {
    if (next.id == palette.id) return;
    palette = next;
    selectedBead = _beadFor(currentColor);
    notifyListeners();
  }

  void setTool(EditorTool next) {
    if (tool == next) return;
    tool = next;
    notifyListeners();
  }

  void setCanvasStyle(CanvasStyle next) {
    if (canvasStyle == next) return;
    canvasStyle = next;
    notifyListeners();
  }

  void toggleGrid() {
    showGrid = !showGrid;
    notifyListeners();
  }

  void beginStroke() {
    _strokeSnapshot ??= Uint32List.fromList(cells);
  }

  void paintAt(int x, int y) {
    final color = tool == EditorTool.eraser ? 0 : currentColor;
    if (pattern.setCellAt(x, y, color)) {
      revision++;
      notifyListeners();
    }
  }

  /// Paints an interpolated segment during a drag and notifies once.
  void paintSegment(int x0, int y0, int x1, int y1) {
    final color = tool == EditorTool.eraser ? 0 : currentColor;
    var changed = false;
    for (final index in _lineIndexes(x0, y0, x1, y1)) {
      final x = index % pattern.width;
      final y = index ~/ pattern.width;
      if (pattern.setCellAt(x, y, color)) changed = true;
    }
    if (changed) {
      revision++;
      notifyListeners();
    }
  }

  void endStroke() {
    final before = _strokeSnapshot;
    _strokeSnapshot = null;
    if (before == null) return;
    if (_cellsDiffer(before, cells)) {
      _pushUndo(before);
      pattern.updatedAt = DateTime.now();
      revision++;
      notifyListeners();
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
    final target = pattern.cellAt(x, y);
    final replacement = currentColor;
    if (target == replacement) return;

    _runEdit(() {
      final stack = <int>[y * pattern.width + x];
      while (stack.isNotEmpty) {
        final index = stack.removeLast();
        if (cells[index] != target) continue;
        final px = index % pattern.width;
        final py = index ~/ pattern.width;
        pattern.setCellAt(px, py, replacement);
        if (px > 0) stack.add(index - 1);
        if (px < pattern.width - 1) stack.add(index + 1);
        if (py > 0) stack.add(index - pattern.width);
        if (py < pattern.height - 1) stack.add(index + pattern.width);
      }
    });
  }

  void pickAt(int x, int y) {
    if (!pattern.inBounds(x, y)) return;
    final color = pattern.cellAt(x, y);
    if (color == 0) return;
    selectColor(color);
  }

  void undo() {
    if (_strokeSnapshot != null || _undo.isEmpty) return;
    final current = Uint32List.fromList(cells);
    final previous = _undo.removeLast();
    _redo.add(current);
    pattern.replaceCells(previous);
    pattern.updatedAt = DateTime.now();
    revision++;
    notifyListeners();
  }

  void redo() {
    if (_strokeSnapshot != null || _redo.isEmpty) return;
    final current = Uint32List.fromList(cells);
    final next = _redo.removeLast();
    _undo.add(current);
    pattern.replaceCells(next);
    pattern.updatedAt = DateTime.now();
    revision++;
    notifyListeners();
  }

  void clearCanvas() {
    if (pattern.beadCount == 0) return;
    _runEdit(() => pattern.clear());
  }

  void _runEdit(void Function() body) {
    final before = Uint32List.fromList(cells);
    body();
    if (_cellsDiffer(before, cells)) {
      _pushUndo(before);
      pattern.updatedAt = DateTime.now();
      revision++;
      notifyListeners();
    }
  }

  void _pushUndo(Uint32List snapshot) {
    _undo.add(snapshot);
    if (_undo.length > _historyLimit) _undo.removeAt(0);
    _redo.clear();
  }

  void _setCellDirect(int x, int y, int color) {
    pattern.setCellAt(x, y, color);
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

  static bool _cellsDiffer(Uint32List a, Uint32List b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return true;
    }
    return false;
  }
}
