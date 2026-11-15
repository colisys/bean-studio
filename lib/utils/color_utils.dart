// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../models/bead_color.dart';

String formatHex(int argb, {bool includeAlpha = false}) {
  final value = includeAlpha ? argb & 0xFFFFFFFF : argb & 0xFFFFFF;
  final digits = includeAlpha ? 8 : 6;
  return '#${value.toRadixString(16).padLeft(digits, '0').toUpperCase()}';
}

int? parseHexColor(String input) {
  var text = input.trim().replaceAll('#', '').replaceAll('0x', '');
  if (text.length == 3) {
    text = text.split('').map((c) => '$c$c').join();
  }
  if (text.length == 6) {
    text = 'FF$text';
  }
  if (text.length != 8) return null;
  return int.tryParse(text, radix: 16);
}

int opaque(int argb) => 0xFF000000 | (argb & 0xFFFFFF);

Color contrastTextColor(int argb) => Color(argb).computeLuminance() > 0.55
    ? const Color(0xFF201A16)
    : const Color(0xFFFFFFFF);

int darken(int argb, double amount) {
  final color = HSVColor.fromColor(Color(argb));
  return color
      .withValue((color.value * (1 - amount)).clamp(0.0, 1.0))
      .toColor()
      .toARGB32();
}

int lighten(int argb, double amount) {
  final color = HSVColor.fromColor(Color(argb));
  return color
      .withValue((color.value + (1 - color.value) * amount).clamp(0.0, 1.0))
      .toColor()
      .toARGB32();
}

int mixColors(int first, int second, double amount) {
  final t = amount.clamp(0.0, 1.0);
  int channel(int shift) {
    final a = (first >> shift) & 0xFF;
    final b = (second >> shift) & 0xFF;
    return (a + (b - a) * t).round() & 0xFF;
  }

  return 0xFF000000 | (channel(16) << 16) | (channel(8) << 8) | channel(0);
}

class LabColor {
  const LabColor(this.l, this.a, this.b);

  final double l;
  final double a;
  final double b;

  factory LabColor.fromArgb(int argb) {
    final r = _linear((argb >> 16) & 0xFF);
    final g = _linear((argb >> 8) & 0xFF);
    final b = _linear(argb & 0xFF);

    final x = (r * 0.4124564 + g * 0.3575761 + b * 0.1804375) / 0.95047;
    final y = (r * 0.2126729 + g * 0.7151522 + b * 0.0721750);
    final z = (r * 0.0193339 + g * 0.1191920 + b * 0.9503041) / 1.08883;

    final fx = _f(x);
    final fy = _f(y);
    final fz = _f(z);
    return LabColor(116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz));
  }

  double distanceTo(LabColor other) {
    final dl = l - other.l;
    final da = a - other.a;
    final db = b - other.b;
    return dl * dl + da * da + db * db;
  }

  static double _linear(int channel) {
    final value = channel / 255.0;
    return value <= 0.04045
        ? value / 12.92
        : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  }

  static double _f(double value) {
    const epsilon = 216 / 24389.0;
    const kappa = 24389 / 27.0;
    return value > epsilon
        ? math.pow(value, 1 / 3).toDouble()
        : (kappa * value + 16) / 116;
  }
}

/// Cached perceptual nearest-colour lookup for a fixed palette.
class ColorMatcher {
  ColorMatcher(Iterable<BeadColor> colors)
    : colors = List<BeadColor>.unmodifiable(colors),
      _labs = colors.map((c) => LabColor.fromArgb(c.argb)).toList();

  final List<BeadColor> colors;
  final List<LabColor> _labs;
  final Map<int, int> _cache = <int, int>{};

  bool get isEmpty => colors.isEmpty;

  int nearestIndex(int argb) {
    final cached = _cache[argb];
    if (cached != null) return cached;

    final target = LabColor.fromArgb(argb);
    var bestIndex = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < _labs.length; i++) {
      final distance = target.distanceTo(_labs[i]);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }
    _cache[argb] = bestIndex;
    return bestIndex;
  }

  BeadColor nearest(int argb) => colors[nearestIndex(argb)];

  List<BeadColor> nearestN(int argb, int count) {
    if (colors.isEmpty || count <= 0) return const <BeadColor>[];
    final target = LabColor.fromArgb(argb);
    final ranked = List<int>.generate(_labs.length, (i) => i)
      ..sort(
        (a, b) =>
            target.distanceTo(_labs[a]).compareTo(target.distanceTo(_labs[b])),
      );
    return ranked.take(count).map((i) => colors[i]).toList(growable: false);
  }
}
