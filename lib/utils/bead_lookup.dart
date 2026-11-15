// SPDX-License-Identifier: GPL-3.0-or-later
import '../data/palettes.dart';
import '../models/bead_color.dart';

BeadColor? findBeadForColor(int argb, {BeadPalette? preferred}) {
  if (preferred != null) {
    for (final bead in preferred.colors) {
      if (bead.argb == argb) return bead;
    }
  }
  return builtInBeadForColor(argb);
}
