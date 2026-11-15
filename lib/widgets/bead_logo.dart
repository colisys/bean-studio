// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// A small perler-bead heart used as the app mark.
class BeadLogo extends StatelessWidget {
  const BeadLogo({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _BeadLogoPainter()),
    );
  }
}

class _BeadLogoPainter extends CustomPainter {
  static const List<List<int>> _pattern = <List<int>>[
    <int>[0, 1, 0, 1, 0],
    <int>[1, 2, 1, 2, 1],
    <int>[1, 1, 1, 1, 1],
    <int>[0, 1, 1, 1, 0],
    <int>[0, 0, 1, 0, 0],
  ];

  static const List<Color> _colors = <Color>[
    beadCoral,
    Color(0xFFF07A8A),
    beadAmber,
    beadTeal,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.shortestSide / 5;
    final radius = cell * 0.42;
    for (var y = 0; y < 5; y++) {
      for (var x = 0; x < 5; x++) {
        final value = _pattern[y][x];
        if (value == 0) continue;
        final color = _colors[(x + y + value) % _colors.length];
        final center = Offset((x + 0.5) * cell, (y + 0.5) * cell);
        canvas.drawCircle(center, radius, Paint()..color = color);
        canvas.drawCircle(
          center,
          radius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = cell * 0.06
            ..color = Colors.black.withValues(alpha: 0.12),
        );
        canvas.drawCircle(
          center,
          radius * 0.22,
          Paint()..color = Colors.white.withValues(alpha: 0.5),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
