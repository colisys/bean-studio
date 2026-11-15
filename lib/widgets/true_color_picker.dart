// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../models/bead_color.dart';
import '../utils/color_utils.dart';

Future<int?> showTrueColorPicker(
  BuildContext context, {
  required int initialColor,
  required BeadPalette palette,
  List<int> recentColors = const <int>[],
}) {
  return showDialog<int>(
    context: context,
    builder: (_) => _TrueColorDialog(
      initialColor: initialColor,
      palette: palette,
      recentColors: recentColors,
    ),
  );
}

class _TrueColorDialog extends StatefulWidget {
  const _TrueColorDialog({
    required this.initialColor,
    required this.palette,
    required this.recentColors,
  });

  final int initialColor;
  final BeadPalette palette;
  final List<int> recentColors;

  @override
  State<_TrueColorDialog> createState() => _TrueColorDialogState();
}

class _TrueColorDialogState extends State<_TrueColorDialog> {
  late HSVColor _hsv;
  late final TextEditingController _hexController;
  late final ColorMatcher _matcher;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(Color(widget.initialColor));
    _hexController = TextEditingController(
      text: formatHex(widget.initialColor).substring(1),
    );
    final colors = widget.palette.matchableColors.isEmpty
        ? widget.palette.colors
        : widget.palette.matchableColors;
    _matcher = ColorMatcher(colors);
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  int get _argb => _hsv.toColor().toARGB32();

  void _update(HSVColor next, {bool syncHex = true}) {
    setState(() {
      _hsv = next;
      if (syncHex) {
        _hexController.text = formatHex(_argb).substring(1);
        _hexController.selection = TextSelection.collapsed(
          offset: _hexController.text.length,
        );
      }
    });
  }

  void _applyHex(String value) {
    final parsed = parseHexColor(value);
    if (parsed == null) return;
    _update(HSVColor.fromColor(Color(parsed)), syncHex: false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nearest = _matcher.colors.isEmpty ? null : _matcher.nearest(_argb);
    final suggestions = _matcher.colors.isEmpty
        ? const <BeadColor>[]
        : _matcher.nearestN(_argb, 6);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Text(
                    '真彩色',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _SaturationValueField(
                hsv: _hsv,
                onChanged: (s, v) =>
                    _update(_hsv.withSaturation(s).withValue(v)),
              ),
              const SizedBox(height: 16),
              _HueSlider(
                hue: _hsv.hue,
                onChanged: (hue) => _update(_hsv.withHue(hue)),
              ),
              const SizedBox(height: 18),
              Row(
                children: <Widget>[
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Color(_argb),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        TextField(
                          controller: _hexController,
                          maxLength: 8,
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9a-fA-F]'),
                            ),
                          ],
                          decoration: const InputDecoration(
                            prefixText: '#',
                            labelText: 'HEX',
                            counterText: '',
                            isDense: true,
                          ),
                          onChanged: _applyHex,
                          onSubmitted: _applyHex,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          nearest == null
                              ? formatHex(_argb)
                              : '最接近 ${nearest.brand} ${nearest.displayName}',
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (widget.recentColors.isNotEmpty) ...<Widget>[
                const SizedBox(height: 18),
                Text(
                  '最近使用',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final color in widget.recentColors)
                      _ColorDot(
                        color: color,
                        selected: color == _argb,
                        onTap: () => _update(HSVColor.fromColor(Color(color))),
                      ),
                  ],
                ),
              ],
              if (suggestions.isNotEmpty) ...<Widget>[
                const SizedBox(height: 18),
                Text(
                  '常用色号',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 58,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: suggestions.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final bead = suggestions[index];
                      final selected = bead.argb == _argb;
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () =>
                            _update(HSVColor.fromColor(Color(bead.argb))),
                        child: Container(
                          width: 62,
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected
                                  ? scheme.primary
                                  : scheme.outlineVariant,
                              width: selected ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            children: <Widget>[
                              Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: Color(bead.argb),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0x22000000),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                bead.code,
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, _argb),
                    child: const Text('使用此颜色'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final int color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(99),
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: Color(color),
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? scheme.primary : const Color(0x33000000),
            width: selected ? 2.5 : 1,
          ),
        ),
      ),
    );
  }
}

class _SaturationValueField extends StatelessWidget {
  const _SaturationValueField({required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final void Function(double saturation, double value) onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 190,
        width: double.infinity,
        child: LayoutBuilder(
          builder: (context, constraints) {
            void handle(Offset local) {
              final s = (local.dx / constraints.maxWidth).clamp(0.0, 1.0);
              final v = (1 - local.dy / constraints.maxHeight).clamp(0.0, 1.0);
              onChanged(s, v);
            }

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanDown: (details) => handle(details.localPosition),
              onPanUpdate: (details) => handle(details.localPosition),
              onTapDown: (details) => handle(details.localPosition),
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: CustomPaint(painter: _SvPainter(hsv.hue)),
                  ),
                  Positioned(
                    left: hsv.saturation * constraints.maxWidth - 10,
                    top: (1 - hsv.value) * constraints.maxHeight - 10,
                    child: IgnorePointer(
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: hsv.toColor(),
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surface.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          formatHex(hsv.toColor().toARGB32()),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SvPainter extends CustomPainter {
  _SvPainter(this.hue);

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final hueColor = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(colors: <Color>[Colors.white, hueColor])
            .createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Colors.transparent, Colors.black],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _SvPainter oldDelegate) =>
      oldDelegate.hue != hue;
}

class _HueSlider extends StatelessWidget {
  const _HueSlider({required this.hue, required this.onChanged});

  final double hue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: LayoutBuilder(
        builder: (context, constraints) {
          void handle(Offset local) {
            onChanged((local.dx / constraints.maxWidth).clamp(0.0, 1.0) * 360);
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanDown: (details) => handle(details.localPosition),
            onPanUpdate: (details) => handle(details.localPosition),
            onTapDown: (details) => handle(details.localPosition),
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: Container(
                    height: 14,
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: <Color>[
                          Color(0xFFFF0000),
                          Color(0xFFFFFF00),
                          Color(0xFF00FF00),
                          Color(0xFF00FFFF),
                          Color(0xFF0000FF),
                          Color(0xFFFF00FF),
                          Color(0xFFFF0000),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: (hue / 360) * constraints.maxWidth - 9,
                  child: IgnorePointer(
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: HSVColor.fromAHSV(1, hue, 1, 1).toColor(),
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
