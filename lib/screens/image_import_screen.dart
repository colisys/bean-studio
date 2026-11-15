// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../data/palettes.dart';
import '../models/bead_color.dart';
import '../models/pattern.dart';
import '../services/image_import_service.dart';
import '../widgets/pattern_thumbnail.dart';

class ImageImportScreen extends StatefulWidget {
  const ImageImportScreen({super.key});

  @override
  State<ImageImportScreen> createState() => _ImageImportScreenState();
}

class _ImageImportScreenState extends State<ImageImportScreen> {
  Uint8List? _sourceBytes;
  img.Image? _sourceImage;
  String _sourceName = '导入作品';

  int _width = 48;
  ImageFitMode _fit = ImageFitMode.cover;
  BeadPalette? _palette = mardPalette;
  bool _dither = false;
  bool _includeEffects = false;

  BeadPattern? _preview;
  bool _converting = false;
  String? _error;
  int _convertToken = 0;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 3000,
        maxHeight: 3000,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final decoded = ImageImportService.decode(bytes);
      if (decoded == null) {
        throw const FormatException('无法解码这张图片，请换一张试试');
      }
      final stem = _fileStem(picked.name);
      if (!mounted) return;
      setState(() {
        _sourceBytes = bytes;
        _sourceImage = decoded;
        _sourceName = stem.isEmpty ? '导入作品' : stem;
        _width = math.min(48, math.max(8, decoded.width));
        _preview = null;
        _error = null;
      });
      _scheduleConvert(immediate: true);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = '读取图片失败：$error');
      }
    }
  }

  String _fileStem(String name) {
    final dot = name.lastIndexOf('.');
    return (dot > 0 ? name.substring(0, dot) : name).trim();
  }

  void _scheduleConvert({bool immediate = false}) {
    _debounce?.cancel();
    if (immediate) {
      _convert();
    } else {
      _debounce = Timer(const Duration(milliseconds: 280), _convert);
    }
  }

  Future<void> _convert() async {
    final source = _sourceImage;
    if (source == null) return;
    final token = ++_convertToken;
    setState(() {
      _converting = true;
      _error = null;
    });
    await Future<void>.delayed(Duration.zero);
    try {
      final pattern = ImageImportService.convert(
        source,
        title: _sourceName,
        settings: ImageImportSettings(
          width: _width,
          fit: _fit,
          palette: _palette,
          dither: _dither,
          includeEffects: _includeEffects,
        ),
      );
      if (!mounted || token != _convertToken) return;
      setState(() {
        _preview = pattern;
        _converting = false;
      });
    } on Object catch (error) {
      if (!mounted || token != _convertToken) return;
      setState(() {
        _converting = false;
        _error = '转换失败：$error';
      });
    }
  }

  void _update(VoidCallback change, {bool immediate = false}) {
    setState(change);
    _scheduleConvert(immediate: immediate);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('导入图片'),
        actions: <Widget>[
          if (_sourceImage != null)
            TextButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              label: const Text('换一张'),
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: _sourceImage == null
          ? _buildPicker(context)
          : LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 940;
                if (wide) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: SingleChildScrollView(
                            child: _buildPreview(
                              context,
                              scheme,
                              math.max(300, constraints.maxHeight - 120),
                            ),
                          ),
                        ),
                        const SizedBox(width: 24),
                        SizedBox(
                          width: 370,
                          child: SingleChildScrollView(
                            child: _buildSettings(context, scheme),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
                  child: Column(
                    children: <Widget>[
                      _buildPreview(
                        context,
                        scheme,
                        math.min(
                          380,
                          math.max(260, constraints.maxHeight * 0.42),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildSettings(context, scheme),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildPicker(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 38),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 36,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  '把照片变成拼豆图纸',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  '导入照片或像素图，自动匹配常用色号，或保留真彩色。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.6,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('选择图片'),
                ),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: scheme.error),
                  ),
                ],
                const SizedBox(height: 18),
                Text(
                  '支持 JPG、PNG、WebP、GIF 等格式',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreview(
    BuildContext context,
    ColorScheme scheme,
    double height,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          height: height,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (_preview != null)
                PatternThumbnail(
                  pattern: _preview!,
                  padding: 20,
                  background: Colors.transparent,
                )
              else
                Center(
                  child: Text(
                    _converting ? '正在转换…' : '等待转换',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              if (_converting)
                ColoredBox(
                  color: scheme.surface.withValues(alpha: 0.5),
                  child: const Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  ),
                ),
              Positioned(
                left: 12,
                top: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    _preview == null
                        ? '预览'
                        : '${_preview!.width} × ${_preview!.height} · '
                              '${_preview!.beadCount} 颗 · ${_preview!.usedColorCount} 色',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Image.memory(
                  _sourceBytes!,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _sourceName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '原图 ${_sourceImage!.width} × ${_sourceImage!.height}',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (_converting)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(fontSize: 12, color: scheme.error)),
        ],
      ],
    );
  }

  Widget _buildSettings(BuildContext context, ColorScheme scheme) {
    final sectionStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w800,
      color: scheme.onSurfaceVariant,
      letterSpacing: 0.2,
    );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('网格宽度', style: sectionStyle),
              const Spacer(),
              Text(
                '$_width 格',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
          Slider(
            value: _width.toDouble().clamp(8, 160),
            min: 8,
            max: 160,
            divisions: 152,
            label: '$_width',
            onChanged: (value) {
              setState(() => _width = value.round());
              _scheduleConvert();
            },
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final size in const <int>[16, 29, 48, 58, 96])
                ChoiceChip(
                  label: Text('$size'),
                  selected: _width == size,
                  showCheckmark: false,
                  onSelected: (_) =>
                      _update(() => _width = size, immediate: true),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text('构图方式', style: sectionStyle),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              ChoiceChip(
                label: const Text('裁切填充'),
                selected: _fit == ImageFitMode.cover,
                onSelected: (_) => _update(() => _fit = ImageFitMode.cover),
              ),
              ChoiceChip(
                label: const Text('完整留白'),
                selected: _fit == ImageFitMode.contain,
                onSelected: (_) => _update(() => _fit = ImageFitMode.contain),
              ),
              ChoiceChip(
                label: const Text('拉伸'),
                selected: _fit == ImageFitMode.stretch,
                onSelected: (_) => _update(() => _fit = ImageFitMode.stretch),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('色板', style: sectionStyle),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final palette in builtInPalettes)
                ChoiceChip(
                  label: Text(palette.name),
                  selected: _palette?.id == palette.id,
                  onSelected: (_) =>
                      _update(() => _palette = palette, immediate: true),
                ),
              ChoiceChip(
                label: const Text('真彩色'),
                selected: _palette == null,
                onSelected: (_) => _update(() {
                  _palette = null;
                  _dither = false;
                  _includeEffects = false;
                }, immediate: true),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilterChip(
                label: const Text('抖动'),
                selected: _dither,
                onSelected: _palette == null
                    ? null
                    : (value) =>
                          _update(() => _dither = value, immediate: true),
              ),
              FilterChip(
                label: const Text('含特殊色'),
                selected: _includeEffects,
                onSelected: _palette == null
                    ? null
                    : (value) => _update(
                        () => _includeEffects = value,
                        immediate: true,
                      ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '抖动可减少色带，但会让像素更碎；清晰的像素图建议关闭。'
            '宽度上限受画布 400 格限制并自动保持宽高比。',
            style: TextStyle(
              fontSize: 10.5,
              height: 1.55,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _preview == null || _converting || _error != null
                  ? null
                  : () => Navigator.pop(context, _preview),
              icon: const Icon(Icons.brush_rounded, size: 18),
              label: Text(
                _preview == null
                    ? '生成画布'
                    : '生成画布（${_preview!.width} × ${_preview!.height}）',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
