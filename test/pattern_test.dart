// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:typed_data';

import 'package:bead_studio/models/pattern.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BeadPattern', () {
    test('creates a blank canvas with cached counts', () {
      final pattern = BeadPattern.blank(title: '小蘑菇', width: 6, height: 4);
      expect(pattern.width, 6);
      expect(pattern.height, 4);
      expect(pattern.cells.length, 24);
      expect(pattern.beadCount, 0);
      expect(pattern.usedColorCount, 0);
      expect(pattern.title, '小蘑菇');
    });

    test('updates counts incrementally and after replacements', () {
      final pattern = BeadPattern.blank(title: '计数', width: 2, height: 2);
      expect(pattern.beadCount, 0);

      pattern.setCellAt(0, 0, 0xFF112233);
      pattern.setCellAt(1, 0, 0xFF112233);
      expect(pattern.beadCount, 2);
      expect(pattern.colorCounts[0xFF112233], 2);

      pattern.setCellAt(0, 0, 0xFF445566);
      expect(pattern.colorCounts[0xFF112233], 1);
      expect(pattern.colorCounts[0xFF445566], 1);
      expect(pattern.beadCount, 2);

      pattern.setCellAt(1, 0, 0);
      expect(pattern.beadCount, 1);
      expect(pattern.usedColorCount, 1);

      pattern.replaceCells(Uint32List.fromList(<int>[0, 0, 0, 0xFF778899]));
      expect(pattern.beadCount, 1);
      expect(pattern.colorCounts[0xFF778899], 1);

      pattern.clear();
      expect(pattern.beadCount, 0);
    });

    test('round-trips through JSON and keeps cell data', () {
      final pattern = BeadPattern.blank(title: '测试图案', width: 5, height: 3);
      pattern.setCellAt(0, 0, 0xFFE85D75);
      pattern.setCellAt(4, 2, 0xFF2BA39A);

      final restored = BeadPattern.fromJsonString(pattern.toJsonString());
      expect(restored.id, pattern.id);
      expect(restored.title, pattern.title);
      expect(restored.width, pattern.width);
      expect(restored.height, pattern.height);
      expect(restored.cellAt(0, 0), 0xFFE85D75);
      expect(restored.cellAt(4, 2), 0xFF2BA39A);
      expect(restored.beadCount, 2);
    });

    test('copies with a new id without sharing cell storage', () {
      final pattern = BeadPattern.blank(title: '复制', width: 2, height: 2);
      pattern.setCellAt(0, 0, 0xFF112233);
      final copy = pattern.copyWithId('new-id');
      expect(copy.id, 'new-id');
      copy.setCellAt(0, 0, 0xFF445566);
      expect(pattern.cellAt(0, 0), 0xFF112233);
    });

    test('rejects invalid project files', () {
      expect(
        () => BeadPattern.fromJson(<String, dynamic>{'format': 'other'}),
        throwsFormatException,
      );
      expect(
        () => BeadPattern.fromJson(<String, dynamic>{
          'format': patternFormatId,
          'version': 1,
          'width': 2,
          'height': 2,
          'cells': '1:00000000',
        }),
        throwsFormatException,
      );
      expect(
        () => BeadPattern.fromJson(<String, dynamic>{
          'format': patternFormatId,
          'version': 99,
          'width': 2,
          'height': 2,
          'cells': '',
        }),
        throwsFormatException,
      );
    });
  });
}
