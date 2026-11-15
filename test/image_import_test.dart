// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:bead_studio/models/bead_color.dart';
import 'package:bead_studio/services/image_import_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

img.Image _solid(int width, int height, int r, int g, int b, {int a = 255}) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(r, g, b, a));
  return image;
}

void main() {
  group('ImageImportService', () {
    test('keeps true colour when no palette is selected', () {
      final pattern = ImageImportService.convert(
        _solid(8, 4, 255, 0, 0),
        title: '红色',
        settings: const ImageImportSettings(
          width: 4,
          fit: ImageFitMode.stretch,
        ),
      );
      expect(pattern.width, 4);
      expect(pattern.height, 2);
      expect(pattern.beadCount, 8);
      expect(pattern.usedColorCount, 1);
      expect(pattern.cellAt(0, 0), 0xFFFF0000);
    });

    test('maps pixels to the nearest palette bead', () {
      const palette = BeadPalette(
        id: 'test',
        name: 'Test',
        subtitle: '',
        colors: <BeadColor>[
          BeadColor(code: 'R', name: 'Red', argb: 0xFFFF0000, brand: 'Test'),
          BeadColor(code: 'B', name: 'Blue', argb: 0xFF0000FF, brand: 'Test'),
        ],
      );
      final pattern = ImageImportService.convert(
        _solid(4, 4, 250, 5, 5),
        title: '红色',
        settings: const ImageImportSettings(
          width: 2,
          fit: ImageFitMode.stretch,
          palette: palette,
        ),
      );
      expect(pattern.beadCount, 4);
      expect(pattern.cellAt(0, 0), 0xFFFF0000);
    });

    test('transparent pixels become empty cells', () {
      final image = img.Image(width: 4, height: 4, numChannels: 4);
      final pattern = ImageImportService.convert(
        image,
        title: '透明',
        settings: const ImageImportSettings(
          width: 2,
          fit: ImageFitMode.stretch,
        ),
      );
      expect(pattern.beadCount, 0);
    });

    test('supports Floyd-Steinberg dithering', () {
      const palette = BeadPalette(
        id: 'test',
        name: 'Test',
        subtitle: '',
        colors: <BeadColor>[
          BeadColor(code: 'K', name: 'Black', argb: 0xFF000000, brand: 'Test'),
          BeadColor(code: 'W', name: 'White', argb: 0xFFFFFFFF, brand: 'Test'),
        ],
      );
      final pattern = ImageImportService.convert(
        _solid(8, 8, 128, 128, 128),
        title: '灰色',
        settings: const ImageImportSettings(
          width: 8,
          fit: ImageFitMode.stretch,
          palette: palette,
          dither: true,
        ),
      );
      expect(pattern.beadCount, greaterThan(0));
      expect(
        pattern.colorCounts.keys.every(
          (color) => color == 0xFF000000 || color == 0xFFFFFFFF,
        ),
        isTrue,
      );
    });
  });
}
