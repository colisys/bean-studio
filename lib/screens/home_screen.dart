// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';

import '../models/pattern.dart';
import '../services/export_service.dart';
import '../services/project_store.dart';
import '../theme.dart';
import '../widgets/bead_logo.dart';
import '../widgets/pattern_thumbnail.dart';
import '../widgets/update_dialog.dart';
import 'editor_screen.dart';
import 'image_import_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ProjectStore _store = ProjectStore();
  List<BeadPattern> _projects = const <BeadPattern>[];
  String? _lastProjectId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final projects = await _store.loadAll();
      final lastId = await _store.lastProjectId();
      if (!mounted) return;
      setState(() {
        _projects = projects;
        _lastProjectId = lastId;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('读取作品失败：${_errorText(error)}');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _errorText(Object error) {
    if (error is FormatException) return error.message;
    return error.toString();
  }

  Future<void> _startProject(BeadPattern pattern) async {
    final saved = await _store.save(pattern);
    if (!saved) {
      _snack('保存失败，请检查设备可用空间');
      return;
    }
    await _store.rememberLastProject(pattern.id);
    await _openEditor(pattern);
  }

  Future<void> _openEditor(BeadPattern pattern) async {
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => EditorScreen(pattern: pattern)),
    );
    await _refresh();
  }

  Future<void> _openProject(BeadPattern pattern) async {
    await _store.rememberLastProject(pattern.id);
    await _openEditor(pattern);
  }

  Future<void> _newCanvas() async {
    final spec = await showDialog<_CanvasSpec>(
      context: context,
      builder: (_) => const _NewCanvasDialog(),
    );
    if (spec == null) return;
    final pattern = BeadPattern.blank(
      title: spec.title,
      width: spec.width,
      height: spec.height,
    );
    await _startProject(pattern);
  }

  Future<void> _importImage() async {
    if (!mounted) return;
    final pattern = await Navigator.of(context).push<BeadPattern>(
      MaterialPageRoute<BeadPattern>(builder: (_) => const ImageImportScreen()),
    );
    if (pattern == null) return;
    await _startProject(pattern);
  }

  Future<void> _importProjectFile() async {
    try {
      final pattern = await _store.importFromFile();
      if (pattern == null) return;
      await _store.rememberLastProject(pattern.id);
      await _openEditor(pattern);
    } on Object catch (error) {
      _snack('打开工程失败：${_errorText(error)}');
    }
  }

  Future<void> _exportProject(BeadPattern pattern) async {
    try {
      final bytes = ExportService.textBytes(pattern.toJsonString());
      final filename = ExportService.safeFilename(pattern.title, '.bead.json');
      final path = ExportService.isMobile
          ? await ExportService.shareFile(
              bytes: bytes,
              filename: filename,
              mime: 'application/json',
              text: '拼豆工坊工程 · ${pattern.title}',
            )
          : await ExportService.saveFile(
              bytes: bytes,
              filename: filename,
              mime: 'application/json',
              extensions: const <String>['json'],
            );
      if (path != null) _snack('已导出工程文件');
    } on Object catch (error) {
      _snack('导出失败：${_errorText(error)}');
    }
  }

  Future<void> _deleteProject(BeadPattern pattern) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这件作品？'),
        content: Text('「${pattern.title}」将从本机移除，此操作无法撤销。'),
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
    if (confirmed != true) return;
    await _store.delete(pattern.id);
    await _refresh();
    _snack('已删除作品');
  }

  void _showAbout() {
    showAboutDialog(
      context: context,
      applicationName: appName,
      applicationVersion: appVersionLabel,
      applicationIcon: const Padding(
        padding: EdgeInsets.only(right: 12),
        child: BeadLogo(size: 44),
      ),
      applicationLegalese:
          '$appLicense\nCopyright (C) 2026 DawnCall\n$appWebsite',
      children: <Widget>[
        const SizedBox(height: 18),
        Text(
          '把照片或像素稿变成拼豆图纸。支持真彩色板、常用色号、导入导出、'
          '图片分享与摄像头拾色。',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.6),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => launchUrl(
              Uri.parse(appWebsite),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.public_rounded, size: 18),
            label: const Text(appWebsite),
          ),
        ),
        Text(
          'MARD、Hama、Perler 色值为屏幕近似参考，实体豆子可能因批次略有差异，'
          '大批量购买前请以实物色卡为准。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(
                builder: (context, constraints) {
                  final horizontal = constraints.maxWidth > 720 ? 40.0 : 18.0;
                  final contentWidth = math.min(
                    constraints.maxWidth - horizontal * 2,
                    1120.0,
                  );
                  return SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      horizontal,
                      18,
                      horizontal,
                      28,
                    ),
                    child: Center(
                      child: SizedBox(
                        width: contentWidth,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            _buildTopBar(context),
                            const SizedBox(height: 24),
                            _buildHero(context, contentWidth < 680),
                            const SizedBox(height: 36),
                            _buildSectionHeader(context),
                            const SizedBox(height: 16),
                            if (_projects.isEmpty)
                              _buildEmptyState(context)
                            else
                              _buildGrid(contentWidth),
                            const SizedBox(height: 52),
                            _buildFooter(context),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: <Widget>[
        const BeadLogo(size: 34),
        const SizedBox(width: 10),
        Text(
          appName,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            appNameEn.toUpperCase(),
            style: TextStyle(
              fontSize: 9,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        const Spacer(),
        IconButton(
          tooltip: '检查更新',
          onPressed: () => showUpdateDialog(context),
          icon: const Icon(Icons.system_update_alt_rounded),
        ),
        IconButton(
          tooltip: '关于',
          onPressed: _showAbout,
          icon: const Icon(Icons.info_outline_rounded),
        ),
      ],
    );
  }

  Widget _buildHero(BuildContext context, bool narrow) {
    final scheme = Theme.of(context).colorScheme;
    final actions = <Widget>[
      FilledButton.icon(
        onPressed: _newCanvas,
        icon: const Icon(Icons.add_rounded),
        label: const Text('新建画布'),
      ),
      OutlinedButton.icon(
        onPressed: _importImage,
        icon: const Icon(Icons.image_outlined),
        label: const Text('导入图片'),
      ),
      OutlinedButton.icon(
        onPressed: _importProjectFile,
        icon: const Icon(Icons.folder_open_rounded),
        label: const Text('打开工程'),
      ),
    ];

    final lastProject = _projects.isEmpty
        ? null
        : _projects.firstWhere(
            (p) => p.id == _lastProjectId,
            orElse: () => _projects.first,
          );

    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '把灵感，排成一颗颗豆子。',
          style: TextStyle(
            fontSize: narrow ? 26 : 34,
            height: 1.22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '导入照片或画像素图，自动匹配常用色号，一键导出分享图纸。',
          style: TextStyle(
            fontSize: 14.5,
            height: 1.6,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    final logo = Container(
      width: narrow ? 62 : 84,
      height: narrow ? 62 : 84,
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(24),
      ),
      alignment: Alignment.center,
      child: BeadLogo(size: narrow ? 44 : 58),
    );

    final content = narrow
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              logo,
              const SizedBox(height: 20),
              heading,
              const SizedBox(height: 22),
              Wrap(spacing: 10, runSpacing: 10, children: actions),
              if (lastProject != null) ...<Widget>[
                const SizedBox(height: 6),
                _ContinueButton(
                  pattern: lastProject,
                  onPressed: () => _openProject(lastProject),
                ),
              ],
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              logo,
              const SizedBox(width: 26),
              Expanded(child: heading),
              const SizedBox(width: 28),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 10,
                      runSpacing: 10,
                      children: actions,
                    ),
                    if (lastProject != null) ...<Widget>[
                      const SizedBox(height: 6),
                      _ContinueButton(
                        pattern: lastProject,
                        onPressed: () => _openProject(lastProject),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            left: -90,
            top: -130,
            child: _HeroBlob(
              size: 280,
              color: scheme.primaryContainer.withValues(alpha: 0.65),
            ),
          ),
          Positioned(
            right: -60,
            bottom: -150,
            child: _HeroBlob(
              size: 240,
              color: scheme.tertiaryContainer.withValues(alpha: 0.4),
            ),
          ),
          Padding(padding: EdgeInsets.all(narrow ? 24 : 34), child: content),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: <Widget>[
        Text(
          '我的作品',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            '${_projects.length}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        const Spacer(),
        IconButton(
          tooltip: '刷新',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh_rounded, size: 20),
        ),
      ],
    );
  }

  Widget _buildGrid(double width) {
    const spacing = 16.0;
    final columns = (width / 230).floor().clamp(1, 4);
    final cardWidth = (width - spacing * (columns - 1)) / columns;
    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: <Widget>[
        for (final pattern in _projects)
          SizedBox(
            width: cardWidth,
            child: _ProjectCard(
              pattern: pattern,
              onOpen: () => _openProject(pattern),
              onExport: () => _exportProject(pattern),
              onDelete: () => _deleteProject(pattern),
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 44),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: <Widget>[
          Icon(
            Icons.grid_view_rounded,
            size: 44,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 14),
          const Text(
            '还没有作品',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            '从一块空白拼豆板开始，或把喜欢的照片变成图纸。',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant, height: 1.5),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              FilledButton.icon(
                onPressed: _newCanvas,
                icon: const Icon(Icons.add_rounded),
                label: const Text('新建画布'),
              ),
              OutlinedButton.icon(
                onPressed: _importImage,
                icon: const Icon(Icons.image_outlined),
                label: const Text('导入图片'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(
      fontSize: 11,
      color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
      height: 1.6,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Divider(),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          alignment: WrapAlignment.spaceBetween,
          children: <Widget>[
            Text('$appName · $appNameEn · $appVersionLabel', style: style),
            Text(appWebsite, style: style),
            Text(appLicense, style: style),
            Text('色卡为屏幕近似值，请以实物为准', style: style),
          ],
        ),
      ],
    );
  }
}

class _HeroBlob extends StatelessWidget {
  const _HeroBlob({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

class _ContinueButton extends StatelessWidget {
  const _ContinueButton({required this.pattern, required this.onPressed});

  final BeadPattern pattern;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.play_arrow_rounded, size: 18),
      label: Text(
        '继续「${pattern.title}」',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.pattern,
    required this.onOpen,
    required this.onExport,
    required this.onDelete,
  });

  final BeadPattern pattern;
  final VoidCallback onOpen;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AspectRatio(
              aspectRatio: 1.08,
              child: PatternThumbnail(pattern: pattern),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          pattern.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: '更多',
                        padding: EdgeInsets.zero,
                        iconSize: 18,
                        onSelected: (value) {
                          if (value == 'export') onExport();
                          if (value == 'delete') onDelete();
                        },
                        itemBuilder: (context) =>
                            const <PopupMenuEntry<String>>[
                              PopupMenuItem<String>(
                                value: 'export',
                                child: Text('导出工程'),
                              ),
                              PopupMenuItem<String>(
                                value: 'delete',
                                child: Text('删除作品'),
                              ),
                            ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${pattern.width} × ${pattern.height} · '
                    '${pattern.frameCount > 1 ? '${pattern.frameCount} 帧 · ' : ''}'
                    '${pattern.beadCount} 颗 · ${_relativeTime(pattern.updatedAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
      ),
    );
  }
}

class _CanvasSpec {
  const _CanvasSpec(this.title, this.width, this.height);

  final String title;
  final int width;
  final int height;
}

class _NewCanvasDialog extends StatefulWidget {
  const _NewCanvasDialog();

  @override
  State<_NewCanvasDialog> createState() => _NewCanvasDialogState();
}

class _NewCanvasDialogState extends State<_NewCanvasDialog> {
  static const List<int> _presets = <int>[16, 24, 29, 32, 48, 58, 96];

  final TextEditingController _titleController = TextEditingController(
    text: '我的拼豆',
  );
  final TextEditingController _widthController = TextEditingController(
    text: '29',
  );
  final TextEditingController _heightController = TextEditingController(
    text: '29',
  );
  bool _lockAspect = true;
  int? _preset = 29;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  void _applyPreset(int size) {
    setState(() {
      _preset = size;
      _widthController.text = '$size';
      _heightController.text = '$size';
      _error = null;
    });
  }

  void _submit() {
    final width = int.tryParse(_widthController.text);
    final height = int.tryParse(_heightController.text);
    if (width == null || height == null || width < 4 || height < 4) {
      setState(() => _error = '宽高最少 4 格');
      return;
    }
    if (width > maxPatternDimension || height > maxPatternDimension) {
      setState(() => _error = '宽高最多 $maxPatternDimension 格');
      return;
    }
    final title = _titleController.text.trim().isEmpty
        ? '未命名作品'
        : _titleController.text.trim();
    Navigator.pop(context, _CanvasSpec(title, width, height));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('新建拼豆画布'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: _titleController,
                autofocus: true,
                maxLength: 30,
                decoration: const InputDecoration(
                  labelText: '作品名称',
                  counterText: '',
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 18),
              Text(
                '常用尺寸',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final size in _presets)
                    ChoiceChip(
                      label: Text('$size × $size'),
                      selected: _preset == size,
                      onSelected: (_) => _applyPreset(size),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _widthController,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(labelText: '宽（格）'),
                      onChanged: (value) {
                        setState(() => _preset = null);
                        if (_lockAspect) {
                          _heightController.text = value;
                        }
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: _lockAspect ? '解锁比例' : '锁定方形比例',
                    onPressed: () => setState(() => _lockAspect = !_lockAspect),
                    icon: Icon(
                      _lockAspect ? Icons.link_rounded : Icons.link_off_rounded,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _heightController,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(labelText: '高（格）'),
                      onChanged: (_) => setState(() => _preset = null),
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '支持 4–$maxPatternDimension 格；标准方板通常为 29 × 29。',
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(fontSize: 12, color: scheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('创建')),
      ],
    );
  }
}

String _relativeTime(DateTime time) {
  final difference = DateTime.now().difference(time);
  if (difference.inMinutes < 1) return '刚刚';
  if (difference.inHours < 1) return '${difference.inMinutes} 分钟前';
  if (difference.inDays < 1) return '${difference.inHours} 小时前';
  if (difference.inDays < 7) return '${difference.inDays} 天前';
  final month = time.month.toString().padLeft(2, '0');
  final day = time.day.toString().padLeft(2, '0');
  return '${time.year}-$month-$day';
}
