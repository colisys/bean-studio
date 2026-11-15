// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

class ReferenceOverlay extends StatefulWidget {
  const ReferenceOverlay({
    super.key,
    required this.bytes,
    required this.aspect,
    required this.onClose,
  });

  final Uint8List bytes;
  final double aspect;
  final VoidCallback onClose;

  @override
  State<ReferenceOverlay> createState() => _ReferenceOverlayState();
}

class _ReferenceOverlayState extends State<ReferenceOverlay> {
  static const List<double> _opacities = <double>[0.3, 0.45, 0.6, 0.75, 0.9];
  static const List<double> _widths = <double>[170, 230, 320, 430];

  Offset _offset = const Offset(24, 24);
  int _opacityIndex = 1;
  int _widthIndex = 1;

  double get _targetWidth => _widths[_widthIndex];

  double get _imageWidth {
    final aspect = widget.aspect <= 0 ? 1.0 : widget.aspect;
    final height = _targetWidth / aspect;
    if (height <= 520) return _targetWidth;
    return 520 * aspect;
  }

  double get _imageHeight => _imageWidth / (widget.aspect <= 0 ? 1 : widget.aspect);

  void _cycleOpacity() {
    setState(() => _opacityIndex = (_opacityIndex + 1) % _opacities.length);
  }

  void _cycleSize() {
    setState(() => _widthIndex = (_widthIndex + 1) % _widths.length);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final headerWidth = math.max(150.0, _imageWidth);
    return Positioned(
      left: _offset.dx,
      top: _offset.dy,
      child: SizedBox(
        width: headerWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Material(
              color: scheme.surfaceContainerHigh.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(10),
              elevation: 2,
              shadowColor: Colors.black.withValues(alpha: 0.2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (details) {
                      setState(() => _offset += details.delta);
                    },
                    child: MouseRegion(
                      cursor: SystemMouseCursors.move,
                      child: const Padding(
                        padding: EdgeInsets.fromLTRB(7, 8, 4, 8),
                        child: Icon(Icons.drag_indicator_rounded, size: 17),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '参考图',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip:
                        '不透明度 ${(_opacities[_opacityIndex] * 100).round()}%',
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    onPressed: _cycleOpacity,
                    icon: const Icon(Icons.opacity_rounded),
                  ),
                  IconButton(
                    tooltip: '切换参考图大小',
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    onPressed: _cycleSize,
                    icon: const Icon(Icons.photo_size_select_large_rounded),
                  ),
                  IconButton(
                    tooltip: '移除参考图',
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            IgnorePointer(
              child: Opacity(
                opacity: _opacities[_opacityIndex],
                child: Container(
                  width: _imageWidth,
                  height: _imageHeight,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: 0.55),
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.memory(
                    widget.bytes,
                    fit: BoxFit.contain,
                    cacheWidth: 1200,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
