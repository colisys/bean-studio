// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';
import 'dart:typed_data';

import 'package:bead_studio/models/pattern.dart';
import 'package:bead_studio/services/animation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  testWidgets('encodes animated GIF and APNG with all frames', (tester) async {
    final pattern = BeadPattern.blank(title: 'animation', width: 3, height: 2);
    pattern.setCellAt(0, 0, 0xFFE85D75);
    pattern.setCellAt(2, 1, 0xFF2BA39A);
    final second = Uint32List(6);
    second[1] = 0xFFF2B23E;
    second[4] = 0xFF8BDBFA;
    pattern.addFrame(1, cells: second);

    Uint8List? gifBytes;
    Uint8List? apngBytes;
    await tester.runAsync(() async {
      gifBytes = await encodeAnimation(
        pattern,
        format: AnimationFormat.gif,
        fps: 8,
      );
      apngBytes = await encodeAnimation(
        pattern,
        format: AnimationFormat.apng,
        fps: 8,
      );
    });

    expect(gifBytes, isNotNull);
    expect(apngBytes, isNotNull);
    expect(ascii.decode(gifBytes!.sublist(0, 3)), 'GIF');
    expect(
      apngBytes!.sublist(0, 8),
      <int>[137, 80, 78, 71, 13, 10, 26, 10],
    );
    expect(
      latin1.decode(apngBytes!),
      contains('acTL'),
    );

    final gif = img.decodeGif(gifBytes!);
    final apng = img.decodePng(apngBytes!);
    expect(gif?.numFrames, 2);
    expect(apng?.numFrames, 2);
  });
}
