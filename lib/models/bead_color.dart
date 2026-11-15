// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// A single bead colour from a brand's chart.
@immutable
class BeadColor {
  const BeadColor({
    required this.code,
    required this.name,
    required this.argb,
    required this.brand,
  });

  final String code;
  final String name;
  final int argb;
  final String brand;

  Color get color => Color(argb);

  String get hex =>
      '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  /// Transparent, glow, neon and metallic beads are poor automatic-matching
  /// candidates because their screen colour is not their finished look.
  bool get isEffect => _effectPattern.hasMatch(name);

  String get displayName => name == code ? code : '$code · $name';

  static final RegExp _effectPattern = RegExp(
    r'translucent|transparent|clear|glow|neon|fluorescent|pearl|glitter|gold|silver|bronze',
    caseSensitive: false,
  );

  @override
  String toString() => '$brand $code $hex';
}

@immutable
class BeadPalette {
  const BeadPalette({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.colors,
  });

  final String id;
  final String name;
  final String subtitle;
  final List<BeadColor> colors;

  List<BeadColor> get matchableColors =>
      colors.where((c) => !c.isEffect).toList(growable: false);
}
