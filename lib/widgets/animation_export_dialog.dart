// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../services/animation_service.dart';
import '../services/export_service.dart';
import '../state/editor_controller.dart';

Future<void> showAnimationExportDialog(
  BuildContext context, {
  required EditorController controller,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _AnimationExportDialog(controller: controller),
  );
}

class _AnimationExportDialog extends StatefulWidget {
  const _AnimationExportDialog({required this.controller});

  final EditorController controller;

  @override
  State<_AnimationExportDialog> createState() => _AnimationExportDialogState();
}

class _AnimationExportDialogState extends State<_AnimationExportDialog> {
  AnimationFormat _format = AnimationFormat.gif;
  int _fps = 8;
  Uint8List? _bytes;
  bool _generating = false;
  double _progress = 0;
  String? _error;

  EditorController get _controller => widget.controller;

  String get _extension =>
      _format == AnimationFormat.gif ? '.gif' : '.apng';

  String get _mime =>
      _format == AnimationFormat.gif ? 'image/gif' : 'image/apng';

  Future<void> _generate() async {
    setState(() {
      _generating = true;
      _progress = 0;
      _error = null;
    });
    try {
      final bytes = await encodeAnimation(
        _controller.pattern,
        format: _format,
        fps: _fps,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _progress = progress);
        },
      );
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _generating = false;
        _progress = 1;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _generating = false;
        _error = '生成动画失败：$error';
      });
    }
  }

  Future<void> _save() async {
    final bytes = _bytes;
    if (bytes == null) return;
    final filename = ExportService.safeFilename(
      '${_controller.pattern.title}-动画',
      _extension,
    );
    try {
      final String? path;
      if (ExportService.isMobile) {
        path = await ExportService.shareFile(
          bytes: bytes,
          filename: filename,
          mime: _mime,
          text: '拼豆动画 · ${_controller.pattern.title}',
        );
      } else {
        path = await ExportService.saveFile(
          bytes: bytes,
          filename: filename,
          mime: _mime,
          extensions: <String>[_extension.substring(1)],
        );
      }
      if (!mounted) return;
      if (path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ExportService.isMobile ? '已打开分享面板' : '动画已保存')),
        );
      }
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存动画失败：$error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pattern = _controller.pattern;
    return AlertDialog(
      title: const Row(
        children: <Widget>[
          Icon(Icons.animation_rounded),
          SizedBox(width: 10),
          Text('导出动画'),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                '${pattern.frameCount} 帧 · ${pattern.width} × ${pattern.height} · '
                '${_fps}fps',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: <Widget>[
                  ChoiceChip(
                    label: const Text('GIF'),
                    selected: _format == AnimationFormat.gif,
                    onSelected: _generating
                        ? null
                        : (_) => setState(() {
                            _format = AnimationFormat.gif;
                            _bytes = null;
                          }),
                  ),
                  ChoiceChip(
                    label: const Text('APNG'),
                    selected: _format == AnimationFormat.apng,
                    onSelected: _generating
                        ? null
                        : (_) => setState(() {
                            _format = AnimationFormat.apng;
                            _bytes = null;
                          }),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: <Widget>[
                  const Text('帧率'),
                  Expanded(
                    child: Slider(
                      value: _fps.toDouble(),
                      min: 2,
                      max: 24,
                      divisions: 22,
                      label: '$_fps fps',
                      onChanged: _generating
                          ? null
                          : (value) => setState(() {
                              _fps = value.round();
                              _bytes = null;
                            }),
                    ),
                  ),
                  SizedBox(
                    width: 52,
                    child: Text(
                      '$_fps fps',
                      textAlign: TextAlign.end,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
              Text(
                _format == AnimationFormat.gif
                    ? 'GIF 最多 256 色，适合快速预览和分享。'
                    : 'APNG 保留真彩色和透明度，画质更好。',
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              if (_generating) ...<Widget>[
                LinearProgressIndicator(value: _progress),
                const SizedBox(height: 6),
                Text(
                  '正在生成 ${(_progress * 100).round()}%',
                  style: const TextStyle(fontSize: 11),
                ),
                const SizedBox(height: 12),
              ],
              if (_bytes != null && !_generating)
                Container(
                  height: 240,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.all(10),
                  child: Image.memory(
                    _bytes!,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
                ),
              if (_bytes != null && !_generating) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  '${(_bytes!.length / 1024).toStringAsFixed(1)} KB · '
                  '无限循环 · 无标题/材料图例',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (_error != null) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(color: scheme.error, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
        if (_bytes != null && !_generating)
          FilledButton.icon(
            onPressed: _save,
            icon: Icon(
              ExportService.isMobile
                  ? Icons.ios_share_rounded
                  : Icons.download_rounded,
            ),
            label: Text(ExportService.isMobile ? '分享动画' : '保存动画'),
          ),
        FilledButton.icon(
          onPressed: _generating ? null : _generate,
          icon: const Icon(Icons.movie_creation_outlined),
          label: Text(_bytes == null ? '生成动画' : '重新生成'),
        ),
      ],
    );
  }
}
