// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:typed_data';

import 'package:bead_studio/utils/rle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RLE', () {
    test('round-trips cell data', () {
      final cells = Uint32List.fromList(<int>[
        0,
        0,
        0xFF112233,
        0xFF112233,
        0xFF445566,
      ]);
      final encoded = encodeRle(cells);
      expect(encoded, '2:00000000;2:ff112233;1:ff445566');
      expect(decodeRle(encoded, cells.length), cells);
    });

    test('handles empty canvases', () {
      expect(encodeRle(Uint32List(0)), '');
      expect(decodeRle('', 0), Uint32List(0));
      expect(() => decodeRle('', 3), throwsFormatException);
    });

    test('rejects malformed data', () {
      expect(() => decodeRle('3:00000000', 4), throwsFormatException);
      expect(() => decodeRle('4:00000000', 3), throwsFormatException);
      expect(() => decodeRle('0:ff000000', 1), throwsFormatException);
      expect(() => decodeRle('x:ff000000', 1), throwsFormatException);
      expect(() => decodeRle('1:zz', 1), throwsFormatException);
    });
  });
}
