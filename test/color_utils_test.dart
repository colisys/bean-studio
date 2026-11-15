// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:bead_studio/data/palettes.dart';
import 'package:bead_studio/models/bead_color.dart';
import 'package:bead_studio/utils/color_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('colour utilities', () {
    test('parses and formats hex colours', () {
      expect(parseHexColor('#F4D738'), 0xFFF4D738);
      expect(parseHexColor('f4d738'), 0xFFF4D738);
      expect(parseHexColor('0xF4D738'), 0xFFF4D738);
      expect(parseHexColor('#abc'), 0xFFAABBCC);
      expect(parseHexColor('80FF0000'), 0x80FF0000);
      expect(parseHexColor('not-a-colour'), isNull);
      expect(formatHex(0xFFF4D738), '#F4D738');
      expect(formatHex(0x80FF0000, includeAlpha: true), '#80FF0000');
    });

    test('finds the exact palette colour', () {
      final matcher = ColorMatcher(mardColors.take(40));
      for (final bead in mardColors.take(40)) {
        expect(matcher.nearest(bead.argb).code, bead.code);
      }
    });

    test('matches black and white sensibly', () {
      const black = BeadColor(
        code: 'K',
        name: 'Black',
        argb: 0xFF000000,
        brand: 'T',
      );
      const white = BeadColor(
        code: 'W',
        name: 'White',
        argb: 0xFFFFFFFF,
        brand: 'T',
      );
      final matcher = ColorMatcher(<BeadColor>[white, black]);
      expect(matcher.nearest(0xFF101010).code, 'K');
      expect(matcher.nearest(0xFFF0F0F0).code, 'W');
      expect(matcher.nearestN(0xFF202020, 2).length, 2);
    });

    test('marks effect beads separately', () {
      const clear = BeadColor(
        code: 'H19',
        name: 'Clear',
        argb: 0xFFD8D2CE,
        brand: 'Hama',
      );
      const solid = BeadColor(
        code: 'H01',
        name: 'White',
        argb: 0xFFE5ECF1,
        brand: 'Hama',
      );
      expect(clear.isEffect, isTrue);
      expect(solid.isEffect, isFalse);
      final palette = BeadPalette(
        id: 'test',
        name: 'Test',
        subtitle: '',
        colors: const <BeadColor>[whiteBead, clear],
      );
      expect(palette.matchableColors, <BeadColor>[whiteBead]);
    });

    test('mix and value helpers stay in range', () {
      expect(mixColors(0xFF000000, 0xFFFFFFFF, 0), 0xFF000000);
      expect(mixColors(0xFF000000, 0xFFFFFFFF, 1), 0xFFFFFFFF);
      expect(mixColors(0xFF000000, 0xFFFFFFFF, 0.5), 0xFF808080);
      expect((darken(0xFF808080, 0.2) >> 16) & 0xFF, lessThan(0x80));
      expect((lighten(0xFF808080, 0.2) >> 16) & 0xFF, greaterThan(0x80));
    });
  });
}

const BeadColor whiteBead = BeadColor(
  code: 'H01',
  name: 'White',
  argb: 0xFFE5ECF1,
  brand: 'Hama',
);
