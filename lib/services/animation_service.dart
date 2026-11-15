// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

import '../models/pattern.dart';

enum AnimationFormat { gif, apng }

const ui.Color _animationBoard = ui.Color(0xFFF7F2E8);

int _darken(int argb, double amount) {
  final r = ((argb >> 16) & 0xFF) * (1 - amount);
  final g = ((argb >> 8) & 0xFF) * (1 - amount);
  final b = (argb & 0xFF) * (1 - amount);
  return 0xFF000000 |
      (r.round().clamp(0, 255) << 16) |
      (g.round().clamp(0, 255) << 8) |
      b.round().clamp(0, 255);
}

Future<Uint8List> encodeAnimation(
  BeadPattern pattern, {
  required AnimationFormat format,
  int fps = 8,
  void Function(double progress)? onProgress,
}) async {
  final frameCount = pattern.frameCount;
  if (frameCount < 1) {
    throw StateError('没有可导出的帧');
  }

  final maxSide = 800.0;
  var cell = math.min(24.0, maxSide / math.max(pattern.width, pattern.height));
  cell = cell.clamp(2.0, 24.0);
  while (cell > 2 &&
      frameCount *
              (pattern.width * cell).ceil() *
              (pattern.height * cell).ceil() >
          50000000) {
    cell *= 0.9;
  }
  cell = cell.clamp(2.0, 24.0);

  final pixelWidth = (pattern.width * cell).round().clamp(1, 2000);
  final pixelHeight = (pattern.height * cell).round().clamp(1, 2000);
  final durationMs = (1000 / fps.clamp(1, 50)).round().clamp(20, 2000);

  img.Image? animation;
  for (var i = 0; i < frameCount; i++) {
    final frame = await _renderFrame(pattern, i, cell, pixelWidth, pixelHeight);
    frame.frameDuration = durationMs;
    frame.loopCount = 0;
    if (animation == null) {
      animation = frame;
    } else {
      animation.addFrame(frame);
    }
    onProgress?.call((i + 1) / frameCount * 0.85);
  }

  onProgress?.call(0.9);
  final bytes = switch (format) {
    AnimationFormat.gif => img.encodeGif(
      animation!,
      samplingFactor: 10,
      dither: img.DitherKernel.none,
    ),
    AnimationFormat.apng => img.encodePng(animation!),
  };
  onProgress?.call(1);
  return bytes;
}

Future<img.Image> _renderFrame(
  BeadPattern pattern,
  int frameIndex,
  double cell,
  int pixelWidth,
  int pixelHeight,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final size = ui.Size(pixelWidth.toDouble(), pixelHeight.toDouble());
  canvas.drawRect(ui.Offset.zero & size, ui.Paint()..color = _animationBoard);

  final cells = pattern.frameAt(frameIndex);
  final bead = cell >= 6;
  for (var y = 0; y < pattern.height; y++) {
    for (var x = 0; x < pattern.width; x++) {
      final argb = cells[y * pattern.width + x];
      if (argb == 0) continue;
      final base = ui.Color(argb);
      if (bead) {
        final center = ui.Offset((x + 0.5) * cell, (y + 0.5) * cell);
        final radius = cell * 0.46;
        canvas.drawCircle(center, radius, ui.Paint()..color = base);
        canvas.drawCircle(
          center,
          radius,
          ui.Paint()
            ..style = ui.PaintingStyle.stroke
            ..strokeWidth = math.max(0.8, cell * 0.04)
            ..color = ui.Color(_darken(argb, 0.18)),
        );
        canvas.drawCircle(
          center - ui.Offset(radius * 0.25, radius * 0.25),
          radius * 0.28,
          ui.Paint()..color = const ui.Color(0x40FFFFFF),
        );
        canvas.drawCircle(
          center,
          radius * 0.16,
          ui.Paint()
            ..color = ui.Color(_darken(argb, 0.35)).withValues(alpha: 0.55),
        );
      } else {
        final inset = cell * 0.08;
        canvas.drawRect(
          ui.Rect.fromLTWH(
            x * cell + inset,
            y * cell + inset,
            cell - inset * 2,
            cell - inset * 2,
          ),
          ui.Paint()..color = base,
        );
      }
    }
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(pixelWidth, pixelHeight);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  picture.dispose();
  image.dispose();
  if (data == null) {
    throw StateError('无法渲染动画帧');
  }
  return img.Image.fromBytes(
    width: pixelWidth,
    height: pixelHeight,
    bytes: data.buffer,
    bytesOffset: data.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
}
