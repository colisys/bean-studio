// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../models/pattern.dart';
import '../state/editor_controller.dart';

/// Fast pattern preview used in galleries and import previews. Large patterns
/// are sampled so a thumbnail never draws hundreds of thousands of rectangles.
class PatternThumbnail extends StatelessWidget {
  const PatternThumbnail({
    super.key,
    required this.pattern,
    this.style = CanvasStyle.pixel,
    this.background,
    this.padding = 8,
    this.frameIndex = 0,
  });

  final BeadPattern pattern;
  final CanvasStyle style;
  final Color? background;
  final double padding;
  final int frameIndex;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: background ?? scheme.surfaceContainerHigh,
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: SizedBox.expand(
          child: CustomPaint(
            painter: _PatternThumbnailPainter(
              pattern: pattern,
              style: style,
              frameIndex: frameIndex,
            ),
          ),
        ),
      ),
    );
  }
}

class _PatternThumbnailPainter extends CustomPainter {
  _PatternThumbnailPainter({
    required this.pattern,
    required this.style,
    required this.frameIndex,
  }) : updatedAt = pattern.updatedAt,
       frame = pattern.frameAt(frameIndex),
       beadCount = pattern.beadCountFor(frameIndex);

  final BeadPattern pattern;
  final CanvasStyle style;
  final int frameIndex;
  final DateTime updatedAt;
  final Uint32List frame;
  final int beadCount;

  int _at(int x, int y) => frame[y * pattern.width + x];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || pattern.width == 0 || pattern.height == 0) return;
    final scale = math.min(
      size.width / pattern.width,
      size.height / pattern.height,
    );
    if (scale <= 0) return;
    final drawWidth = pattern.width * scale;
    final drawHeight = pattern.height * scale;
    final origin = Offset(
      (size.width - drawWidth) / 2,
      (size.height - drawHeight) / 2,
    );

    final step = pattern.length > 12000
        ? math.max(1, math.sqrt(pattern.length / 12000).ceil())
        : 1;
    final paint = Paint()..style = PaintingStyle.fill;

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (var y = 0; y < pattern.height; y += step) {
      for (var x = 0; x < pattern.width; x += step) {
        final argb = _at(x, y);
        if (argb == 0) continue;
        paint.color = Color(argb);
        final rect = Rect.fromLTWH(
          origin.dx + x * scale,
          origin.dy + y * scale,
          scale * step + 0.25,
          scale * step + 0.25,
        );
        if (style == CanvasStyle.bead && scale * step >= 4) {
          canvas.drawCircle(rect.center, scale * step * 0.47, paint);
        } else {
          canvas.drawRect(rect, paint);
        }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PatternThumbnailPainter oldDelegate) =>
      oldDelegate.pattern != pattern ||
      oldDelegate.updatedAt != updatedAt ||
      oldDelegate.frameIndex != frameIndex ||
      !identical(oldDelegate.frame, frame) ||
      oldDelegate.beadCount != beadCount ||
      oldDelegate.style != style;
}
