// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../services/export_service.dart';
import '../state/editor_controller.dart';

Future<void> showExportDialog(
  BuildContext context, {
  required EditorController controller,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ExportDialog(controller: controller),
  );
}

class _ExportDialog extends StatefulWidget {
  const _ExportDialog({required this.controller});

  final EditorController controller;

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  late CanvasStyle _style = widget.controller.canvasStyle;
  bool _showGrid = true;
  bool _showLegend = true;
  bool _showHeader = true;

  Uint8List? _preview;
  bool _rendering = true;
  String? _error;
  int _renderToken = 0;

  String get _filename {
    final controller = widget.controller;
    final suffix = controller.frameCount > 1
        ? '-帧${controller.currentFrame + 1}'
        : '';
    return ExportService.safeFilename(
      '${controller.pattern.title}$suffix',
      '.png',
    );
  }

  @override
  void initState() {
    super.initState();
    _render();
  }

  Future<void> _render() async {
    final token = ++_renderToken;
    setState(() {
      _rendering = true;
      _error = null;
    });
    try {
      final bytes = await ExportService.renderPattern(
        pattern: widget.controller.pattern,
        style: _style,
        showGrid: _showGrid,
        showLegend: _showLegend,
        showHeader: _showHeader,
        palette: widget.controller.palette,
        frameIndex: widget.controller.currentFrame,
      );
      if (!mounted || token != _renderToken) return;
      setState(() {
        _preview = bytes;
        _rendering = false;
      });
    } on Object catch (error) {
      if (!mounted || token != _renderToken) return;
      setState(() {
        _rendering = false;
        _error = '生成图片失败：$error';
      });
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    final bytes = _preview;
    if (bytes == null) return;
    try {
      final path = await ExportService.saveFile(
        bytes: bytes,
        filename: _filename,
        mime: 'image/png',
        extensions: const <String>['png'],
      );
      if (path != null) _snack('图片已保存');
    } on Object catch (error) {
      _snack('保存失败：$error');
    }
  }

  Future<void> _share() async {
    final bytes = _preview;
    if (bytes == null) return;
    try {
      final pattern = widget.controller.pattern;
      final path = await ExportService.shareFile(
        bytes: bytes,
        filename: _filename,
        mime: 'image/png',
        text: '拼豆图纸 · ${pattern.title} · ${pattern.width} × ${pattern.height}',
      );
      if (path != null) {
        _snack(ExportService.isMobile ? '已打开分享面板' : '图片已保存');
      }
    } on Object catch (error) {
      _snack('分享失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pattern = widget.controller.pattern;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Text(
                    '导出图片',
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
              Text(
                '${pattern.title} · ${pattern.width} × ${pattern.height} · '
                '${widget.controller.frameCount > 1 ? '帧 ${widget.controller.currentFrame + 1}/${widget.controller.frameCount} · ' : ''}'
                '${widget.controller.currentBeadCount} 颗豆',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                height: 340,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    if (_preview != null)
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Image.memory(
                          _preview!,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        ),
                      )
                    else if (_error != null)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: scheme.error, fontSize: 12),
                          ),
                        ),
                      ),
                    if (_rendering)
                      ColoredBox(
                        color: scheme.surface.withValues(alpha: 0.55),
                        child: const Center(
                          child: SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  ChoiceChip(
                    label: const Text('拼豆样式'),
                    selected: _style == CanvasStyle.bead,
                    onSelected: (_) {
                      setState(() => _style = CanvasStyle.bead);
                      _render();
                    },
                  ),
                  ChoiceChip(
                    label: const Text('像素样式'),
                    selected: _style == CanvasStyle.pixel,
                    onSelected: (_) {
                      setState(() => _style = CanvasStyle.pixel);
                      _render();
                    },
                  ),
                  FilterChip(
                    label: const Text('网格'),
                    selected: _showGrid,
                    onSelected: (value) {
                      setState(() => _showGrid = value);
                      _render();
                    },
                  ),
                  FilterChip(
                    label: const Text('材料图例'),
                    selected: _showLegend,
                    onSelected: (value) {
                      setState(() => _showLegend = value);
                      _render();
                    },
                  ),
                  FilterChip(
                    label: const Text('标题'),
                    selected: _showHeader,
                    onSelected: (value) {
                      setState(() => _showHeader = value);
                      _render();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '图片最长边约 3000px，宽度随画布比例自动适配。',
                style: TextStyle(
                  fontSize: 10.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: <Widget>[
                  const Spacer(),
                  if (ExportService.canSaveToDisk) ...<Widget>[
                    OutlinedButton.icon(
                      onPressed: _rendering || _preview == null ? null : _save,
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text('保存图片'),
                    ),
                    const SizedBox(width: 10),
                  ],
                  FilledButton.icon(
                    onPressed: _rendering || _preview == null ? null : _share,
                    icon: const Icon(Icons.ios_share_rounded, size: 18),
                    label: const Text('分享图片'),
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
