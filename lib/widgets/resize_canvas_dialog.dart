// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../models/pattern.dart';

Future<(int, int, FrameAnchor)?> showResizeCanvasDialog(
  BuildContext context, {
  required int width,
  required int height,
}) {
  return showDialog<(int, int, FrameAnchor)>(
    context: context,
    builder: (_) => _ResizeCanvasDialog(initialWidth: width, initialHeight: height),
  );
}

class _ResizeCanvasDialog extends StatefulWidget {
  const _ResizeCanvasDialog({
    required this.initialWidth,
    required this.initialHeight,
  });

  final int initialWidth;
  final int initialHeight;

  @override
  State<_ResizeCanvasDialog> createState() => _ResizeCanvasDialogState();
}

class _ResizeCanvasDialogState extends State<_ResizeCanvasDialog> {
  late final TextEditingController _widthController;
  late final TextEditingController _heightController;
  late bool _linked;
  FrameAnchor _anchor = FrameAnchor.center;
  String? _error;

  static const List<int> _presets = <int>[16, 29, 32, 48, 58, 96];

  @override
  void initState() {
    super.initState();
    _widthController = TextEditingController(text: '${widget.initialWidth}');
    _heightController = TextEditingController(text: '${widget.initialHeight}');
    _linked = widget.initialWidth == widget.initialHeight;
  }

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  void _applyPreset(int size) {
    setState(() {
      _widthController.text = '$size';
      _heightController.text = '$size';
      _linked = true;
      _error = null;
    });
  }

  void _onWidthChanged(String value) {
    if (_linked) {
      _heightController.text = value;
    }
    setState(() => _error = null);
  }

  int? _parse(TextEditingController controller) {
    final value = int.tryParse(controller.text.trim());
    if (value == null || value < 1 || value > maxPatternDimension) {
      return null;
    }
    return value;
  }

  void _submit() {
    final width = _parse(_widthController);
    final height = _parse(_heightController);
    if (width == null || height == null) {
      setState(() => _error = '宽高需在 1–$maxPatternDimension 之间');
      return;
    }
    if (width == widget.initialWidth && height == widget.initialHeight) {
      Navigator.pop(context);
      return;
    }
    Navigator.pop(context, (width, height, _anchor));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('调整画布尺寸'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '当前 ${widget.initialWidth} × ${widget.initialHeight}',
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _widthController,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(
                        labelText: '宽度',
                        suffixText: '格',
                        isDense: true,
                      ),
                      onChanged: _onWidthChanged,
                    ),
                  ),
                  IconButton(
                    tooltip: _linked ? '已锁定宽高比' : '自由宽高',
                    onPressed: () {
                      setState(() {
                        _linked = !_linked;
                        if (_linked) {
                          _heightController.text = _widthController.text;
                        }
                      });
                    },
                    icon: Icon(
                      _linked ? Icons.link_rounded : Icons.link_off_rounded,
                      size: 20,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _heightController,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(
                        labelText: '高度',
                        suffixText: '格',
                        isDense: true,
                      ),
                      onChanged: (_) {
                        if (_linked) {
                          _linked = false;
                        }
                        setState(() => _error = null);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: <Widget>[
                  for (final size in _presets)
                    ActionChip(
                      label: Text('$size×$size'),
                      onPressed: () => _applyPreset(size),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                '内容锚点',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: <Widget>[
                  ChoiceChip(
                    label: const Text('居中'),
                    selected: _anchor == FrameAnchor.center,
                    onSelected: (_) =>
                        setState(() => _anchor = FrameAnchor.center),
                  ),
                  ChoiceChip(
                    label: const Text('左上角'),
                    selected: _anchor == FrameAnchor.topLeft,
                    onSelected: (_) =>
                        setState(() => _anchor = FrameAnchor.topLeft),
                  ),
                ],
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(fontSize: 12, color: scheme.error),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                '所有动画帧会一起调整尺寸；缩小时超出部分会被裁剪，可用撤销恢复。',
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('应用')),
      ],
    );
  }
}
