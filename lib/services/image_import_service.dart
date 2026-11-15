// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/bead_color.dart';
import '../models/pattern.dart';
import '../utils/color_utils.dart';

enum ImageFitMode { cover, contain, stretch }

class ImageImportSettings {
  const ImageImportSettings({
    this.width = 48,
    this.fit = ImageFitMode.cover,
    this.palette,
    this.dither = false,
    this.includeEffects = false,
  });

  final int width;
  final ImageFitMode fit;
  final BeadPalette? palette;
  final bool dither;
  final bool includeEffects;
}

class ImageImportService {
  static img.Image? decode(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    return decoded == null ? null : img.bakeOrientation(decoded);
  }

  static BeadPattern convert(
    img.Image source, {
    required String title,
    required ImageImportSettings settings,
  }) {
    final sourceWidth = source.width;
    final sourceHeight = source.height;
    if (sourceWidth < 1 || sourceHeight < 1) {
      throw const FormatException('图片尺寸无效');
    }

    var width = settings.width.clamp(1, maxPatternDimension);
    var height = (width * sourceHeight / sourceWidth).round().clamp(
      1,
      maxPatternDimension,
    );
    if ((width * sourceHeight / sourceWidth) > maxPatternDimension) {
      height = maxPatternDimension;
      width = (height * sourceWidth / sourceHeight).round().clamp(
        1,
        maxPatternDimension,
      );
    }

    final prepared = _prepare(source, width, height, settings.fit);
    final cells = Uint32List(width * height);

    final paletteColors = settings.palette == null
        ? null
        : (settings.includeEffects
              ? settings.palette!.colors
              : settings.palette!.matchableColors);
    final matcher = (paletteColors != null && paletteColors.isNotEmpty)
        ? ColorMatcher(paletteColors)
        : null;

    if (matcher == null) {
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final pixel = prepared.getPixel(x, y);
          if (pixel.a < 128) continue;
          final argb = _argb(pixel.r, pixel.g, pixel.b);
          cells[y * width + x] = argb;
        }
      }
    } else if (settings.dither) {
      _mapWithDithering(prepared, matcher, cells, width, height);
    } else {
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final pixel = prepared.getPixel(x, y);
          if (pixel.a < 128) continue;
          final argb = _argb(pixel.r, pixel.g, pixel.b);
          cells[y * width + x] = matcher.nearest(argb).argb;
        }
      }
    }

    return BeadPattern(
      id: generatePatternId(),
      title: title.trim().isEmpty ? '导入作品' : title.trim(),
      width: width,
      height: height,
      cells: cells,
    );
  }

  static img.Image _prepare(
    img.Image source,
    int width,
    int height,
    ImageFitMode fit,
  ) {
    img.Image working = source;
    final largestSide = math.max(source.width, source.height);
    if (largestSide > 2400) {
      final scale = 2400 / largestSide;
      working = img.copyResize(
        source,
        width: (source.width * scale).round().clamp(1, source.width),
        height: (source.height * scale).round().clamp(1, source.height),
        interpolation: img.Interpolation.average,
      );
    }

    switch (fit) {
      case ImageFitMode.stretch:
        return img.copyResize(
          working,
          width: width,
          height: height,
          interpolation: img.Interpolation.average,
        );
      case ImageFitMode.cover:
        final targetAspect = width / height;
        final sourceAspect = working.width / working.height;
        final int cropWidth;
        final int cropHeight;
        if (sourceAspect > targetAspect) {
          cropHeight = working.height;
          cropWidth = (working.height * targetAspect).round().clamp(
            1,
            working.width,
          );
        } else {
          cropWidth = working.width;
          cropHeight = (working.width / targetAspect).round().clamp(
            1,
            working.height,
          );
        }
        final cropped = img.copyCrop(
          working,
          x: (working.width - cropWidth) ~/ 2,
          y: (working.height - cropHeight) ~/ 2,
          width: cropWidth,
          height: cropHeight,
        );
        return img.copyResize(
          cropped,
          width: width,
          height: height,
          interpolation: img.Interpolation.average,
        );
      case ImageFitMode.contain:
        final scale = math.min(width / working.width, height / working.height);
        final resizedWidth = math.max(1, (working.width * scale).round());
        final resizedHeight = math.max(1, (working.height * scale).round());
        final resized = img.copyResize(
          working,
          width: resizedWidth,
          height: resizedHeight,
          interpolation: img.Interpolation.average,
        );
        final output = img.Image(width: width, height: height, numChannels: 4);
        img.compositeImage(output, resized, center: true);
        return output;
    }
  }

  static void _mapWithDithering(
    img.Image source,
    ColorMatcher matcher,
    Uint32List cells,
    int width,
    int height,
  ) {
    final red = Float32List(width * height);
    final green = Float32List(width * height);
    final blue = Float32List(width * height);
    final visible = List<bool>.filled(width * height, false);

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final index = y * width + x;
        final pixel = source.getPixel(x, y);
        if (pixel.a < 128) continue;
        visible[index] = true;
        red[index] = pixel.r.toDouble();
        green[index] = pixel.g.toDouble();
        blue[index] = pixel.b.toDouble();
      }
    }

    void spread(
      int x,
      int y,
      double errorR,
      double errorG,
      double errorB,
      double factor,
    ) {
      if (x < 0 || y < 0 || x >= width || y >= height) return;
      final index = y * width + x;
      if (!visible[index]) return;
      red[index] += errorR * factor;
      green[index] += errorG * factor;
      blue[index] += errorB * factor;
    }

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final index = y * width + x;
        if (!visible[index]) continue;
        final r = red[index].clamp(0.0, 255.0);
        final g = green[index].clamp(0.0, 255.0);
        final b = blue[index].clamp(0.0, 255.0);
        final bead = matcher.nearest(_argb(r, g, b));
        cells[index] = bead.argb;
        final beadR = (bead.argb >> 16) & 0xFF;
        final beadG = (bead.argb >> 8) & 0xFF;
        final beadB = bead.argb & 0xFF;
        final errorR = r - beadR;
        final errorG = g - beadG;
        final errorB = b - beadB;
        spread(x + 1, y, errorR, errorG, errorB, 7 / 16);
        spread(x - 1, y + 1, errorR, errorG, errorB, 3 / 16);
        spread(x, y + 1, errorR, errorG, errorB, 5 / 16);
        spread(x + 1, y + 1, errorR, errorG, errorB, 1 / 16);
      }
    }
  }

  static int _argb(num r, num g, num b) =>
      0xFF000000 |
      ((r.clamp(0, 255).round() & 0xFF) << 16) |
      ((g.clamp(0, 255).round() & 0xFF) << 8) |
      (b.clamp(0, 255).round() & 0xFF);
}
