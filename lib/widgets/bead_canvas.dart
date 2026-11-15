// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../models/pattern.dart';
import '../state/editor_controller.dart';
import '../theme.dart';
import '../utils/color_utils.dart';

class BeadCanvas extends StatefulWidget {
  const BeadCanvas({super.key, required this.controller});

  final EditorController controller;

  @override
  State<BeadCanvas> createState() => _BeadCanvasState();
}

class _BeadCanvasState extends State<BeadCanvas> {
  static const double _cell = 26;
  static const double _minScale = 0.02;
  static const double _maxScale = 8;

  final TransformationController _transform = TransformationController();
  final Set<int> _pointers = <int>{};
  final GlobalKey _viewportKey = GlobalKey();

  Size _viewport = Size.zero;
  double _scale = 1;
  bool _didInitialFit = false;
  (int, int)? _hover;
  (int, int)? _strokeLastCell;
  (int, int)? _dragStart;
  (int, int)? _dragEnd;
  bool _strokeActive = false;

  EditorController get _controller => widget.controller;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  double get _contentWidth => _controller.pattern.width * _cell;
  double get _contentHeight => _controller.pattern.height * _cell;

  void _scheduleInitialFit() {
    if (_didInitialFit || _viewport.isEmpty) return;
    _didInitialFit = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitToView();
    });
  }

  void _fitToView() {
    if (_viewport.isEmpty) return;
    final scale = math.min(
      _viewport.width / _contentWidth,
      _viewport.height / _contentHeight,
    );
    final fitted = (scale * 0.92).clamp(_minScale, 2.0);
    final dx = (_viewport.width - _contentWidth * fitted) / 2;
    final dy = (_viewport.height - _contentHeight * fitted) / 2;
    _transform.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(fitted, fitted, 1, 1);
    setState(() => _scale = fitted);
  }

  void _zoomBy(double factor) {
    if (_viewport.isEmpty) return;
    final current = _transform.value.getMaxScaleOnAxis();
    final next = (current * factor).clamp(_minScale, _maxScale);
    if ((next - current).abs() < 0.0001) return;
    final focal = Offset(_viewport.width / 2, _viewport.height / 2);
    final zoom = next / current;
    final matrix = Matrix4.identity()
      ..translateByDouble(focal.dx, focal.dy, 0, 1)
      ..scaleByDouble(zoom, zoom, 1, 1)
      ..translateByDouble(-focal.dx, -focal.dy, 0, 1)
      ..multiply(_transform.value);
    _transform.value = matrix;
    setState(() => _scale = next);
  }

  (int, int)? _cellAt(Offset local) {
    final x = (local.dx / _cell).floor();
    final y = (local.dy / _cell).floor();
    if (!_controller.pattern.inBounds(x, y)) return null;
    return (x, y);
  }

  bool get _canDraw => _controller.tool != EditorTool.pan;

  void _onPanDown(DragDownDetails details) {
    if (_pointers.length > 1) return;
    final cell = _cellAt(details.localPosition);
    if (cell == null) return;
    _hover = cell;
    final tool = _controller.tool;

    if (tool == EditorTool.pen || tool == EditorTool.eraser) {
      _controller.beginStroke();
      _strokeActive = true;
      _strokeLastCell = cell;
      _controller.paintAt(cell.$1, cell.$2);
    } else if (tool == EditorTool.line || tool == EditorTool.rectangle) {
      setState(() {
        _dragStart = cell;
        _dragEnd = cell;
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_pointers.length > 1) return;
    final cell = _cellAt(details.localPosition);
    if (cell == null) return;
    _hover = cell;
    final tool = _controller.tool;

    if (tool == EditorTool.pen || tool == EditorTool.eraser) {
      if (!_strokeActive) {
        _controller.beginStroke();
        _strokeActive = true;
      }
      final last = _strokeLastCell;
      if (last != null) {
        _controller.paintSegment(last.$1, last.$2, cell.$1, cell.$2);
      } else {
        _controller.paintAt(cell.$1, cell.$2);
      }
      _strokeLastCell = cell;
    } else if (tool == EditorTool.line || tool == EditorTool.rectangle) {
      if (cell != _dragEnd) {
        setState(() => _dragEnd = cell);
      }
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (_strokeActive) {
      _controller.endStroke();
      _strokeActive = false;
      _strokeLastCell = null;
    }

    final start = _dragStart;
    final end = _dragEnd;
    if (start != null && end != null) {
      final tool = _controller.tool;
      if (tool == EditorTool.line) {
        _controller.commitLine(start.$1, start.$2, end.$1, end.$2);
      } else if (tool == EditorTool.rectangle) {
        _controller.commitRectangle(start.$1, start.$2, end.$1, end.$2);
      }
    }
    if (_dragStart != null || _dragEnd != null) {
      setState(() {
        _dragStart = null;
        _dragEnd = null;
      });
    }
  }

  void _onPanCancel() {
    if (_strokeActive) {
      _controller.endStroke();
      _strokeActive = false;
      _strokeLastCell = null;
    }
    if (_dragStart != null || _dragEnd != null) {
      setState(() {
        _dragStart = null;
        _dragEnd = null;
      });
    }
  }

  void _onTapUp(TapUpDetails details) {
    if (_pointers.length > 1) return;
    final cell = _cellAt(details.localPosition);
    if (cell == null) return;
    if (_controller.tool == EditorTool.fill) {
      _controller.floodFillAt(cell.$1, cell.$2);
    } else if (_controller.tool == EditorTool.eyedropper) {
      _controller.pickAt(cell.$1, cell.$2);
    }
  }

  void _onLongPress(LongPressStartDetails details) {
    final cell = _cellAt(details.localPosition);
    if (cell == null) return;
    HapticFeedback.selectionClick();
    _controller.pickAt(cell.$1, cell.$2);
  }

  void _onHover(PointerHoverEvent event) {
    final cell = _cellAt(event.localPosition);
    if (cell != _hover) setState(() => _hover = cell);
  }

  Rect _visibleSceneRect(Matrix4 matrix) {
    if (_viewport.isEmpty) return Rect.zero;
    final inverse = Matrix4.tryInvert(matrix);
    if (inverse == null) return Rect.zero;
    final topLeft = MatrixUtils.transformPoint(inverse, Offset.zero);
    final bottomRight = MatrixUtils.transformPoint(
      inverse,
      Offset(_viewport.width, _viewport.height),
    );
    return Rect.fromLTRB(
      math.min(topLeft.dx, bottomRight.dx),
      math.min(topLeft.dy, bottomRight.dy),
      math.max(topLeft.dx, bottomRight.dx),
      math.max(topLeft.dy, bottomRight.dy),
    );
  }

  MouseCursor get _cursor {
    if (_controller.tool == EditorTool.pan) return SystemMouseCursors.grab;
    return SystemMouseCursors.precise;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        if (viewport != _viewport) {
          _viewport = viewport;
          _scheduleInitialFit();
        }
        return ColoredBox(
          key: _viewportKey,
          color: scheme.surfaceContainerLow,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: Listener(
                  onPointerDown: (event) => _pointers.add(event.pointer),
                  onPointerUp: (event) => _pointers.remove(event.pointer),
                  onPointerCancel: (event) => _pointers.remove(event.pointer),
                  child: InteractiveViewer(
                    transformationController: _transform,
                    constrained: false,
                    minScale: _minScale,
                    maxScale: _maxScale,
                    panEnabled: _controller.tool == EditorTool.pan,
                    scaleEnabled: true,
                    clipBehavior: Clip.hardEdge,
                    boundaryMargin: const EdgeInsets.all(800),
                    onInteractionEnd: (_) {
                      final scale = _transform.value.getMaxScaleOnAxis();
                      if ((scale - _scale).abs() > 0.001) {
                        setState(() => _scale = scale);
                      }
                    },
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanDown: _canDraw ? _onPanDown : null,
                      onPanUpdate: _canDraw ? _onPanUpdate : null,
                      onPanEnd: _canDraw ? _onPanEnd : null,
                      onPanCancel: _canDraw ? _onPanCancel : null,
                      onTapUp:
                          _canDraw &&
                              (_controller.tool == EditorTool.fill ||
                                  _controller.tool == EditorTool.eyedropper)
                          ? _onTapUp
                          : null,
                      onLongPressStart: _canDraw ? _onLongPress : null,
                      child: MouseRegion(
                        cursor: _cursor,
                        onHover: _onHover,
                        onExit: (_) {
                          if (_hover != null) setState(() => _hover = null);
                        },
                        child: SizedBox(
                          width: _contentWidth,
                          height: _contentHeight,
                          child: RepaintBoundary(
                            child: ListenableBuilder(
                              listenable: _controller,
                              builder: (context, _) {
                                return ValueListenableBuilder<Matrix4>(
                                  valueListenable: _transform,
                                  builder: (context, matrix, _) {
                                    final scale = matrix
                                        .getMaxScaleOnAxis()
                                        .clamp(_minScale, _maxScale);
                                    return CustomPaint(
                                      painter: _BeadCanvasPainter(
                                        pattern: _controller.pattern,
                                        revision: _controller.revision,
                                        style: _controller.canvasStyle,
                                        showGrid: _controller.showGrid,
                                        cell: _cell,
                                        screenCell: _cell * scale,
                                        scale: scale,
                                        visible: _visibleSceneRect(matrix),
                                        hover: _hover,
                                        tool: _controller.tool,
                                        currentColor: _controller.currentColor,
                                        dragStart: _dragStart,
                                        dragEnd: _dragEnd,
                                      ),
                                      child: const SizedBox.expand(),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 12,
                bottom: 12,
                child: _ZoomControls(
                  scale: _scale,
                  onZoomIn: () => _zoomBy(1.25),
                  onZoomOut: () => _zoomBy(1 / 1.25),
                  onFit: _fitToView,
                ),
              ),
              Positioned(
                left: 12,
                top: 12,
                child: ListenableBuilder(
                  listenable: _controller,
                  builder: (context, _) {
                    if (_controller.pattern.beadCount > 0) {
                      return const SizedBox.shrink();
                    }
                    return IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surface.withValues(alpha: 0.86),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          '选择颜色，点击画布拼下第一颗豆',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ZoomControls extends StatelessWidget {
  const _ZoomControls({
    required this.scale,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
  });

  final double scale;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(99),
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IconButton(
              tooltip: '缩小',
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              onPressed: onZoomOut,
              icon: const Icon(Icons.remove_rounded),
            ),
            Text(
              '${(scale * 100).round()}%',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
            IconButton(
              tooltip: '放大',
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              onPressed: onZoomIn,
              icon: const Icon(Icons.add_rounded),
            ),
            IconButton(
              tooltip: '适应窗口',
              visualDensity: VisualDensity.compact,
              iconSize: 17,
              onPressed: onFit,
              icon: const Icon(Icons.fit_screen_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _BeadCanvasPainter extends CustomPainter {
  _BeadCanvasPainter({
    required this.pattern,
    required this.revision,
    required this.style,
    required this.showGrid,
    required this.cell,
    required this.screenCell,
    required this.scale,
    required this.visible,
    required this.hover,
    required this.tool,
    required this.currentColor,
    required this.dragStart,
    required this.dragEnd,
  });

  final BeadPattern pattern;
  final int revision;
  final CanvasStyle style;
  final bool showGrid;
  final double cell;
  final double screenCell;
  final double scale;
  final Rect visible;
  final (int, int)? hover;
  final EditorTool tool;
  final int currentColor;
  final (int, int)? dragStart;
  final (int, int)? dragEnd;

  @override
  void paint(Canvas canvas, Size size) {
    final boardRect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(boardRect, Paint()..color = boardCream);

    final startX = math.max(0, ((visible.left - cell * 2) / cell).floor());
    final endX = math.min(
      pattern.width - 1,
      ((visible.right + cell * 2) / cell).ceil(),
    );
    final startY = math.max(0, ((visible.top - cell * 2) / cell).floor());
    final endY = math.min(
      pattern.height - 1,
      ((visible.bottom + cell * 2) / cell).ceil(),
    );
    final detailed = screenCell >= 5;

    final pegPaint = Paint()..color = const Color(0xFFE2D7C5);
    for (var y = startY; y <= endY; y++) {
      for (var x = startX; x <= endX; x++) {
        final argb = pattern.cellAt(x, y);
        final rect = Rect.fromLTWH(x * cell, y * cell, cell, cell);
        if (argb == 0) {
          if (detailed && style == CanvasStyle.bead) {
            canvas.drawCircle(rect.center, cell * 0.08, pegPaint);
          }
          continue;
        }
        _paintBead(canvas, rect, argb);
      }
    }

    if (showGrid && screenCell >= 5) {
      final thin = Paint()
        ..color = const Color(0x13000000)
        ..strokeWidth = math.max(0.5, screenCell * 0.02);
      final thick = Paint()
        ..color = const Color(0x2A000000)
        ..strokeWidth = math.max(0.8, screenCell * 0.035);
      for (var x = 0; x <= pattern.width; x++) {
        final dx = x * cell;
        canvas.drawLine(
          Offset(dx, 0),
          Offset(dx, size.height),
          x % 10 == 0 ? thick : thin,
        );
      }
      for (var y = 0; y <= pattern.height; y++) {
        final dy = y * cell;
        canvas.drawLine(
          Offset(0, dy),
          Offset(size.width, dy),
          y % 10 == 0 ? thick : thin,
        );
      }
    }

    _paintDragPreview(canvas);
    _paintHover(canvas);

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 / scale
        ..color = const Color(0xFFD4C8B4),
    );
  }

  void _paintBead(Canvas canvas, Rect rect, int argb) {
    if (style == CanvasStyle.pixel || screenCell < 5) {
      canvas.drawRect(
        rect.deflate(math.max(0.2, cell * 0.04)),
        Paint()..color = Color(argb),
      );
      return;
    }

    final center = rect.center;
    final radius = cell * 0.46;
    canvas.drawCircle(center, radius, Paint()..color = Color(argb));
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, cell * 0.04)
        ..color = Color(darken(argb, 0.2)).withValues(alpha: 0.55),
    );
    if (screenCell >= 8) {
      canvas.drawCircle(
        center + Offset(-radius * 0.27, -radius * 0.27),
        radius * 0.3,
        Paint()..color = const Color(0x45FFFFFF),
      );
      canvas.drawCircle(
        center,
        radius * 0.16,
        Paint()..color = Color(darken(argb, 0.32)).withValues(alpha: 0.42),
      );
    }
  }

  void _paintHover(Canvas canvas) {
    final cellPos = hover;
    if (cellPos == null || tool == EditorTool.pan) return;
    final (x, y) = cellPos;
    if (!pattern.inBounds(x, y)) return;
    final rect = Rect.fromLTWH(x * cell, y * cell, cell, cell);
    final isEraser = tool == EditorTool.eraser;
    if (tool == EditorTool.pen || isEraser) {
      final fill = isEraser ? const Color(0xFFFFFFFF) : Color(currentColor);
      if (style == CanvasStyle.bead && screenCell >= 5) {
        canvas.drawCircle(
          rect.center,
          cell * 0.46,
          Paint()..color = fill.withValues(alpha: 0.4),
        );
      } else {
        canvas.drawRect(
          rect.deflate(1.5),
          Paint()..color = fill.withValues(alpha: 0.4),
        );
      }
    }
    final stroke = math.max(1.2, 2.0 / scale.clamp(0.1, 8));
    if (style == CanvasStyle.bead && screenCell >= 5) {
      canvas.drawCircle(
        rect.center,
        cell * 0.46 + stroke * 0.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = const Color(0xFFFFFFFF),
      );
      canvas.drawCircle(
        rect.center,
        cell * 0.46 + stroke,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * 0.7
          ..color = const Color(0x99000000),
      );
    } else {
      canvas.drawRect(
        rect.deflate(stroke / 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = const Color(0xFFFFFFFF),
      );
      canvas.drawRect(
        rect.deflate(stroke),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * 0.7
          ..color = const Color(0x99000000),
      );
    }
  }

  void _paintDragPreview(Canvas canvas) {
    final start = dragStart;
    final end = dragEnd;
    if (start == null || end == null) return;
    final previewPaint = Paint()
      ..color = Color(currentColor).withValues(alpha: 0.55);
    final cellRectPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, 1.5 / scale.clamp(0.1, 8))
      ..color = const Color(0xAAFFFFFF);

    if (tool == EditorTool.rectangle) {
      final left = math.min(start.$1, end.$1);
      final right = math.max(start.$1, end.$1);
      final top = math.min(start.$2, end.$2);
      final bottom = math.max(start.$2, end.$2);
      final rect = Rect.fromLTRB(
        left * cell,
        top * cell,
        (right + 1) * cell,
        (bottom + 1) * cell,
      );
      canvas.drawRect(
        rect,
        previewPaint..color = Color(currentColor).withValues(alpha: 0.14),
      );
      canvas.drawRect(rect, cellRectPaint);
      return;
    }

    if (tool == EditorTool.line) {
      for (final point in _linePoints(start, end)) {
        final rect = Rect.fromLTWH(
          point.$1 * cell,
          point.$2 * cell,
          cell,
          cell,
        );
        if (screenCell >= 5 && style == CanvasStyle.bead) {
          canvas.drawCircle(rect.center, cell * 0.46, previewPaint);
          canvas.drawCircle(
            rect.center,
            cell * 0.46,
            cellRectPaint..style = PaintingStyle.stroke,
          );
        } else {
          canvas.drawRect(rect.deflate(1), previewPaint);
        }
      }
    }
  }

  Iterable<(int, int)> _linePoints((int, int) from, (int, int) to) sync* {
    var x = from.$1;
    var y = from.$2;
    final dx = (to.$1 - from.$1).abs();
    final dy = -(to.$2 - from.$2).abs();
    final sx = from.$1 < to.$1 ? 1 : -1;
    final sy = from.$2 < to.$2 ? 1 : -1;
    var error = dx + dy;
    while (true) {
      if (pattern.inBounds(x, y)) yield (x, y);
      if (x == to.$1 && y == to.$2) break;
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

  @override
  bool shouldRepaint(covariant _BeadCanvasPainter oldDelegate) =>
      oldDelegate.revision != revision ||
      oldDelegate.pattern != pattern ||
      oldDelegate.style != style ||
      oldDelegate.showGrid != showGrid ||
      oldDelegate.cell != cell ||
      oldDelegate.screenCell != screenCell ||
      oldDelegate.scale != scale ||
      oldDelegate.visible != visible ||
      oldDelegate.hover != hover ||
      oldDelegate.tool != tool ||
      oldDelegate.currentColor != currentColor ||
      oldDelegate.dragStart != dragStart ||
      oldDelegate.dragEnd != dragEnd;
}
