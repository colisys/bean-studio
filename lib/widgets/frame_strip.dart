// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../state/editor_controller.dart';
import 'pattern_thumbnail.dart';

class FrameStrip extends StatefulWidget {
  const FrameStrip({
    super.key,
    required this.controller,
    this.onExportAnimation,
  });

  final EditorController controller;
  final VoidCallback? onExportAnimation;

  @override
  State<FrameStrip> createState() => _FrameStripState();
}

class _FrameStripState extends State<FrameStrip> {
  Timer? _timer;
  bool _playing = false;

  EditorController get _controller => widget.controller;

  @override
  void dispose() {
    _stopPlayback(notify: false);
    super.dispose();
  }

  void _togglePlayback() {
    if (_playing) {
      _stopPlayback();
      return;
    }
    if (_controller.frameCount < 2) return;
    setState(() => _playing = true);
    _timer = Timer.periodic(
      const Duration(milliseconds: 125),
      (_) {
        if (!mounted) return;
        final next = (_controller.currentFrame + 1) % _controller.frameCount;
        _controller.switchFrame(next);
      },
    );
  }

  void _stopPlayback({bool notify = true}) {
    _timer?.cancel();
    _timer = null;
    if (_playing && notify && mounted) {
      setState(() => _playing = false);
    } else {
      _playing = false;
    }
  }

  void _addFrame() {
    _stopPlayback();
    if (!_controller.addFrame()) {
      _snack('最多支持 120 帧');
    }
  }

  void _duplicateFrame() {
    _stopPlayback();
    if (!_controller.duplicateCurrentFrame()) {
      _snack('最多支持 120 帧');
    }
  }

  Future<void> _deleteFrame() async {
    _stopPlayback();
    if (_controller.frameCount <= 1) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除当前帧？'),
        content: Text('第 ${_controller.currentFrame + 1} 帧将被删除，可用撤销恢复。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) _controller.deleteCurrentFrame();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _onMenu(String value) {
    switch (value) {
      case 'duplicate':
        _duplicateFrame();
        break;
      case 'delete':
        _deleteFrame();
        break;
      case 'left':
        _stopPlayback();
        _controller.moveCurrentFrame(-1);
        break;
      case 'right':
        _stopPlayback();
        _controller.moveCurrentFrame(1);
        break;
      case 'animate':
        _stopPlayback();
        widget.onExportAnimation?.call();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        return Container(
          height: 68,
          color: scheme.surface,
          padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
          child: Row(
            children: <Widget>[
              Text(
                '帧 ${_controller.currentFrame + 1}/${_controller.frameCount}',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _controller.frameCount,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (context, index) {
                    final selected = index == _controller.currentFrame;
                    return Tooltip(
                      message: '第 ${index + 1} 帧',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(9),
                        onTap: () {
                          _stopPlayback();
                          _controller.switchFrame(index);
                        },
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                              color: selected
                                  ? scheme.primary
                                  : scheme.outlineVariant,
                              width: selected ? 2.2 : 1,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: <Widget>[
                              PatternThumbnail(
                                pattern: _controller.pattern,
                                frameIndex: index,
                                padding: 2,
                                background: scheme.surfaceContainerHigh,
                              ),
                              Positioned(
                                left: 2,
                                bottom: 1,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: scheme.surface.withValues(
                                      alpha: 0.8,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 3,
                                      vertical: 0.5,
                                    ),
                                    child: Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        fontSize: 8,
                                        fontWeight: FontWeight.w800,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              IconButton(
                tooltip: '添加空白帧',
                visualDensity: VisualDensity.compact,
                iconSize: 19,
                onPressed: _addFrame,
                icon: const Icon(Icons.add_rounded),
              ),
              IconButton(
                tooltip: _playing ? '暂停动画' : '播放动画',
                visualDensity: VisualDensity.compact,
                iconSize: 19,
                onPressed: _controller.frameCount > 1 ? _togglePlayback : null,
                icon: Icon(
                  _playing
                      ? Icons.pause_circle_outline_rounded
                      : Icons.play_circle_outline_rounded,
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '帧操作',
                onSelected: _onMenu,
                iconSize: 20,
                itemBuilder: (context) => <PopupMenuEntry<String>>[
                  const PopupMenuItem<String>(
                    value: 'duplicate',
                    child: _FrameMenuRow(
                      icon: Icons.copy_rounded,
                      label: '复制当前帧',
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'delete',
                    enabled: _controller.frameCount > 1,
                    child: const _FrameMenuRow(
                      icon: Icons.delete_outline_rounded,
                      label: '删除当前帧',
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem<String>(
                    value: 'left',
                    enabled: _controller.currentFrame > 0,
                    child: const _FrameMenuRow(
                      icon: Icons.arrow_back_rounded,
                      label: '左移当前帧',
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'right',
                    enabled:
                        _controller.currentFrame <
                        _controller.frameCount - 1,
                    child: const _FrameMenuRow(
                      icon: Icons.arrow_forward_rounded,
                      label: '右移当前帧',
                    ),
                  ),
                  if (widget.onExportAnimation != null) ...<PopupMenuEntry<String>>[
                    const PopupMenuDivider(),
                    const PopupMenuItem<String>(
                      value: 'animate',
                      child: _FrameMenuRow(
                        icon: Icons.gif_box_outlined,
                        label: '导出动画…',
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FrameMenuRow extends StatelessWidget {
  const _FrameMenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 18),
        const SizedBox(width: 10),
        Text(label),
      ],
    );
  }
}
