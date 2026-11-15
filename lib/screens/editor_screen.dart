// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/pattern.dart';
import '../services/export_service.dart';
import '../services/project_store.dart';
import '../state/editor_controller.dart';
import '../theme.dart';
import '../utils/color_utils.dart';
import '../widgets/bead_canvas.dart';
import '../widgets/animation_export_dialog.dart';
import '../widgets/export_dialog.dart';
import '../widgets/frame_strip.dart';
import '../widgets/materials_sheet.dart';
import '../widgets/palette_panel.dart';
import '../widgets/reference_overlay.dart';
import '../widgets/resize_canvas_dialog.dart';
import '../widgets/update_dialog.dart';
import '../widgets/true_color_picker.dart';
import 'camera_color_picker_screen.dart';
import 'image_import_screen.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.pattern});

  final BeadPattern pattern;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen>
    with WidgetsBindingObserver {
  late final EditorController _controller;
  final ProjectStore _store = ProjectStore();
  Timer? _saveTimer;
  int _lastSeenRevision = 0;
  bool _saving = false;
  bool _exiting = false;
  bool _allowPop = false;
  Future<void> _saveQueue = Future<void>.value();
  Uint8List? _referenceBytes;
  double? _referenceAspect;

  @override
  void initState() {
    super.initState();
    _controller = EditorController(pattern: widget.pattern);
    _lastSeenRevision = _controller.revision;
    _controller.addListener(_onControllerChanged);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadReferenceImage());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _save(silent: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _controller.removeListener(_onControllerChanged);
    if (_controller.isDirty) {
      unawaited(_save(silent: true));
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _save(silent: true);
    }
  }

  void _onControllerChanged() {
    if (_controller.revision == _lastSeenRevision) return;
    _lastSeenRevision = _controller.revision;
    _saveTimer?.cancel();
    if (!_controller.isDirty) return;
    _saveTimer = Timer(const Duration(milliseconds: 1500), () {
      _save(silent: true);
    });
  }

  Future<void> _save({bool silent = false}) {
    _saveTimer?.cancel();
    final next = _saveQueue.then((_) => _performSave(silent: silent));
    _saveQueue = next;
    return next;
  }

  Future<void> _performSave({required bool silent}) async {
    final revision = _controller.revision;
    final pattern = _controller.pattern;
    if (mounted) setState(() => _saving = true);
    try {
      final saved = await _store.save(pattern);
      if (!saved) throw StateError('设备存储空间不足');
      if (!mounted) return;
      _controller.markSaved(revision);
      if (!silent) _snack('已保存到本机');
    } on Object catch (error) {
      if (mounted) _snack('保存失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _handleExit() async {
    if (_exiting) return;
    _exiting = true;
    await _save(silent: true);
    if (!mounted) return;
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _rename() async {
    final textController = TextEditingController(
      text: _controller.pattern.title,
    );
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名作品'),
        content: TextField(
          controller: textController,
          autofocus: true,
          maxLength: 30,
          decoration: const InputDecoration(labelText: '作品名称', counterText: ''),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, textController.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    textController.dispose();
    if (result != null) _controller.rename(result);
  }

  Future<void> _clearCanvas() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空当前帧？'),
        content: const Text('当前帧上的所有豆子都会被移除，可以用撤销恢复。'),
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
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed == true) _controller.clearCanvas();
  }

  Future<void> _resizeCanvas() async {
    final result = await showResizeCanvasDialog(
      context,
      width: _controller.pattern.width,
      height: _controller.pattern.height,
    );
    if (result == null) return;
    final (width, height, anchor) = result;
    if (_controller.resizeCanvas(width, height, anchor: anchor)) {
      _snack('画布尺寸已更新为 $width × $height');
    }
  }

  Future<void> _exportProjectFile() async {
    try {
      final pattern = _controller.pattern;
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
      if (path != null) {
        _snack(ExportService.isMobile ? '已打开分享面板' : '工程文件已导出');
      }
    } on Object catch (error) {
      _snack('导出失败：$error');
    }
  }

  Future<void> _exportMaterialsCsv() async {
    try {
      final pattern = _controller.pattern;
      final bytes = ExportService.textBytes(
        ExportService.materialsCsv(
          pattern,
          palette: _controller.palette,
          frameIndex: _controller.currentFrame,
        ),
      );
      final filename = ExportService.safeFilename(pattern.title, '.csv');
      final path = ExportService.isMobile
          ? await ExportService.shareFile(
              bytes: bytes,
              filename: filename,
              mime: 'text/csv',
              text: '拼豆材料清单 · ${pattern.title}',
            )
          : await ExportService.saveFile(
              bytes: bytes,
              filename: filename,
              mime: 'text/csv',
              extensions: const <String>['csv'],
            );
      if (path != null) {
        _snack(ExportService.isMobile ? '已打开分享面板' : '材料清单已导出');
      }
    } on Object catch (error) {
      _snack('导出失败：$error');
    }
  }

  Future<void> _importImageAsNew() async {
    final pattern = await Navigator.of(context).push<BeadPattern>(
      MaterialPageRoute<BeadPattern>(builder: (_) => const ImageImportScreen()),
    );
    if (pattern == null) return;
    await _save(silent: true);
    final saved = await _store.save(pattern);
    if (!saved) {
      _snack('保存新作品失败');
      return;
    }
    await _store.rememberLastProject(pattern.id);
    if (!mounted) return;
    await Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute<void>(builder: (_) => EditorScreen(pattern: pattern)),
    );
  }

  Future<void> _loadReferenceImage() async {
    try {
      final bytes = await _store.loadReferenceImage(_controller.pattern.id);
      if (bytes == null || !mounted) return;
      final decoded = img.decodeImage(bytes);
      if (decoded == null || !mounted) return;
      setState(() {
        _referenceBytes = bytes;
        _referenceAspect = decoded.width / decoded.height;
      });
    } on Object {
      // A missing or corrupt reference image should never block editing.
    }
  }

  Future<void> _pickReferenceImage() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2200,
        maxHeight: 2200,
      );
      if (picked == null) return;
      final raw = await picked.readAsBytes();
      var image = img.decodeImage(raw);
      if (image == null) throw const FormatException('无法读取该图片');
      image = img.bakeOrientation(image);
      final maxSide = math.max(image.width, image.height);
      if (maxSide > 1400) {
        final scale = 1400 / maxSide;
        image = img.copyResize(
          image,
          width: (image.width * scale).round(),
          height: (image.height * scale).round(),
          interpolation: img.Interpolation.average,
        );
      }
      final bytes = Uint8List.fromList(img.encodeJpg(image, quality: 85));
      await _store.saveReferenceImage(_controller.pattern.id, bytes);
      if (!mounted) return;
      setState(() {
        _referenceBytes = bytes;
        _referenceAspect = image!.width / image.height;
      });
    } on Object catch (error) {
      _snack('添加参考图失败：$error');
    }
  }

  Future<void> _removeReferenceImage() async {
    await _store.deleteReferenceImage(_controller.pattern.id);
    if (!mounted) return;
    setState(() {
      _referenceBytes = null;
      _referenceAspect = null;
    });
  }

  Widget _buildCanvasArea() {
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: <Widget>[
        Positioned.fill(child: BeadCanvas(controller: _controller)),
        if (_referenceBytes != null && _referenceAspect != null)
          ReferenceOverlay(
            bytes: _referenceBytes!,
            aspect: _referenceAspect!,
            onClose: _removeReferenceImage,
          ),
      ],
    );
  }

  Future<void> _openPaletteSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: FractionallySizedBox(
          heightFactor: 0.85,
          child: PalettePanel(controller: _controller, showClose: true),
        ),
      ),
    );
  }

  Future<void> _pickTrueColor() async {
    final color = await showTrueColorPicker(
      context,
      initialColor: _controller.currentColor,
      palette: _controller.palette,
      recentColors: _controller.recentColors,
    );
    if (color != null) _controller.selectColor(color);
  }

  Future<void> _openCamera() async {
    final color = await Navigator.of(context).push<int>(
      MaterialPageRoute<int>(
        builder: (_) => CameraColorPickerScreen(palette: _controller.palette),
      ),
    );
    if (color != null) _controller.selectColor(color);
  }

  Future<void> _exportAnimation() {
    return showAnimationExportDialog(context, controller: _controller);
  }

  void _showAbout() {
    showAboutDialog(
      context: context,
      applicationName: appName,
      applicationVersion: appVersionLabel,
      applicationIcon: const Icon(Icons.grid_view_rounded, size: 36),
      applicationLegalese:
          '$appLicense\nCopyright (C) 2026 DawnCall\n$appWebsite',
      children: <Widget>[
        const SizedBox(height: 12),
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
          'MARD、Hama、Perler 色值为屏幕近似参考，实体豆子可能因批次略有差异。',
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
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleExit();
      },
      child: Scaffold(
        appBar: _EditorAppBar(
          controller: _controller,
          saving: _saving,
          onRename: _rename,
          onSave: () => _save(),
          onImportImage: _importImageAsNew,
          onPickReferenceImage: _pickReferenceImage,
          onExportAnimation: _exportAnimation,
          onExportImage: () =>
              showExportDialog(context, controller: _controller),
          onExportProject: _exportProjectFile,
          onExportMaterials: () =>
              showMaterialsSheet(context, controller: _controller),
          onExportCsv: _exportMaterialsCsv,
          onResizeCanvas: _resizeCanvas,
          onClear: _clearCanvas,
          onCheckUpdate: () => showUpdateDialog(context),
          onAbout: _showAbout,
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 980;
            if (wide) {
              return Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      children: <Widget>[
                        Expanded(child: _buildCanvasArea()),
                        const Divider(height: 1),
                        FrameStrip(
                          controller: _controller,
                          onExportAnimation: _exportAnimation,
                        ),
                        const Divider(height: 1),
                        _ToolStrip(controller: _controller, compact: false),
                        const Divider(height: 1),
                        _StatusBar(controller: _controller),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  SizedBox(
                    width: 342,
                    child: PalettePanel(controller: _controller),
                  ),
                ],
              );
            }
            return Column(
              children: <Widget>[
                Expanded(child: _buildCanvasArea()),
                const Divider(height: 1),
                FrameStrip(
                  controller: _controller,
                  onExportAnimation: _exportAnimation,
                ),
                const Divider(height: 1),
                _ToolStrip(controller: _controller, compact: true),
                const Divider(height: 1),
                SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _MobilePaletteBar(
                        controller: _controller,
                        onOpenPalette: _openPaletteSheet,
                        onTrueColor: _pickTrueColor,
                        onCamera: _openCamera,
                      ),
                      _StatusBar(controller: _controller),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EditorAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _EditorAppBar({
    required this.controller,
    required this.saving,
    required this.onRename,
    required this.onSave,
    required this.onImportImage,
    required this.onPickReferenceImage,
    required this.onExportAnimation,
    required this.onExportImage,
    required this.onExportProject,
    required this.onExportMaterials,
    required this.onExportCsv,
    required this.onResizeCanvas,
    required this.onClear,
    required this.onCheckUpdate,
    required this.onAbout,
  });

  final EditorController controller;
  final bool saving;
  final VoidCallback onRename;
  final VoidCallback onSave;
  final VoidCallback onImportImage;
  final VoidCallback onPickReferenceImage;
  final VoidCallback onExportAnimation;
  final VoidCallback onExportImage;
  final VoidCallback onExportProject;
  final VoidCallback onExportMaterials;
  final VoidCallback onExportCsv;
  final VoidCallback onResizeCanvas;
  final VoidCallback onClear;
  final VoidCallback onCheckUpdate;
  final VoidCallback onAbout;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  void _onMenu(String value) {
    switch (value) {
      case 'import':
        onImportImage();
        break;
      case 'reference':
        onPickReferenceImage();
        break;
      case 'animation':
        onExportAnimation();
        break;
      case 'image':
        onExportImage();
        break;
      case 'project':
        onExportProject();
        break;
      case 'materials':
        onExportMaterials();
        break;
      case 'csv':
        onExportCsv();
        break;
      case 'resize':
        onResizeCanvas();
        break;
      case 'clear':
        onClear();
        break;
      case 'update':
        onCheckUpdate();
        break;
      case 'about':
        onAbout();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final pattern = controller.pattern;
        return AppBar(
          titleSpacing: 0,
          title: Tooltip(
            message: '点击重命名',
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onRename,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      pattern.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${pattern.width} × ${pattern.height} · '
                      '${controller.currentBeadCount} 颗豆 · '
                      '${controller.currentColorCount} 色'
                      '${controller.frameCount > 1 ? ' · 帧 ${controller.currentFrame + 1}/${controller.frameCount}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: <Widget>[
            IconButton(
              tooltip: '撤销',
              onPressed: controller.canUndo ? controller.undo : null,
              icon: const Icon(Icons.undo_rounded),
            ),
            IconButton(
              tooltip: '重做',
              onPressed: controller.canRedo ? controller.redo : null,
              icon: const Icon(Icons.redo_rounded),
            ),
            IconButton(
              tooltip: '保存',
              onPressed: saving ? null : onSave,
              icon: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Stack(
                      clipBehavior: Clip.none,
                      children: <Widget>[
                        const Icon(Icons.save_outlined),
                        if (controller.isDirty)
                          Positioned(
                            right: -2,
                            top: -1,
                            child: Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
            PopupMenuButton<String>(
              tooltip: '更多',
              onSelected: _onMenu,
              itemBuilder: (context) => const <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'import',
                  child: _MenuRow(
                    icon: Icons.add_photo_alternate_outlined,
                    label: '导入图片为新作品',
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'reference',
                  child: _MenuRow(
                    icon: Icons.image_outlined,
                    label: '添加 / 更换参考图',
                  ),
                ),
                PopupMenuDivider(),
                PopupMenuItem<String>(
                  value: 'animation',
                  child: _MenuRow(
                    icon: Icons.gif_box_outlined,
                    label: '导出动画（GIF / APNG）',
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'image',
                  child: _MenuRow(
                    icon: Icons.ios_share_rounded,
                    label: '导出 / 分享图片',
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'project',
                  child: _MenuRow(
                    icon: Icons.file_download_outlined,
                    label: '导出工程文件',
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'materials',
                  child: _MenuRow(
                    icon: Icons.checklist_rounded,
                    label: '查看材料清单',
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'csv',
                  child: _MenuRow(
                    icon: Icons.table_view_outlined,
                    label: '导出材料 CSV',
                  ),
                ),
                PopupMenuDivider(),
                PopupMenuItem<String>(
                  value: 'resize',
                  child: _MenuRow(
                    icon: Icons.crop_free_rounded,
                    label: '调整画布尺寸',
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'clear',
                  child: _MenuRow(
                    icon: Icons.delete_sweep_outlined,
                    label: '清空当前帧',
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'update',
                  child: _MenuRow(
                    icon: Icons.system_update_alt_rounded,
                    label: '检查更新',
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'about',
                  child: _MenuRow(
                    icon: Icons.info_outline_rounded,
                    label: '关于',
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 19),
        const SizedBox(width: 10),
        Text(label),
      ],
    );
  }
}

class _ToolStrip extends StatelessWidget {
  const _ToolStrip({required this.controller, required this.compact});

  final EditorController controller;
  final bool compact;

  static const List<(EditorTool, IconData, String)> _tools =
      <(EditorTool, IconData, String)>[
        (EditorTool.pen, Icons.edit_rounded, '画笔'),
        (EditorTool.eraser, Icons.cleaning_services_rounded, '橡皮'),
        (EditorTool.fill, Icons.format_color_fill_rounded, '填充'),
        (EditorTool.line, Icons.show_chart_rounded, '直线'),
        (EditorTool.rectangle, Icons.crop_square_rounded, '方框'),
        (EditorTool.eyedropper, Icons.colorize_rounded, '吸管'),
        (EditorTool.pan, Icons.pan_tool_alt_rounded, '移动'),
      ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Container(
          color: scheme.surface,
          padding: EdgeInsets.fromLTRB(compact ? 6 : 12, 6, compact ? 4 : 8, 6),
          child: Row(
            children: <Widget>[
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: <Widget>[
                      for (final (tool, icon, label) in _tools)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: _ToolChip(
                            icon: icon,
                            label: label,
                            compact: compact,
                            selected: controller.tool == tool,
                            onTap: () => controller.setTool(tool),
                          ),
                        ),
                      Container(
                        width: 1,
                        height: 24,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        color: scheme.outlineVariant,
                      ),
                      Tooltip(
                        message: '切换拼豆 / 像素显示',
                        child: _ToolChip(
                          icon: controller.canvasStyle == CanvasStyle.bead
                              ? Icons.blur_circular_rounded
                              : Icons.grid_view_rounded,
                          label: controller.canvasStyle == CanvasStyle.bead
                              ? '拼豆'
                              : '像素',
                          compact: compact,
                          selected: false,
                          onTap: () => controller.setCanvasStyle(
                            controller.canvasStyle == CanvasStyle.bead
                                ? CanvasStyle.pixel
                                : CanvasStyle.bead,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Tooltip(
                message: controller.showGrid ? '隐藏网格' : '显示网格',
                child: _SquareIconButton(
                  icon: Icons.grid_on_rounded,
                  selected: controller.showGrid,
                  onPressed: controller.toggleGrid,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ToolChip extends StatelessWidget {
  const _ToolChip({
    required this.icon,
    required this.label,
    required this.compact,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool compact;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;
    return Tooltip(
      message: label,
      child: Material(
        color: selected ? scheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 9 : 11,
              vertical: 9,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 18, color: foreground),
                if (!compact) ...<Widget>[
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: foreground,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SquareIconButton extends StatelessWidget {
  const _SquareIconButton({
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      iconSize: 19,
      style: IconButton.styleFrom(
        backgroundColor: selected
            ? scheme.primaryContainer
            : scheme.surfaceContainerHigh,
        foregroundColor: selected
            ? scheme.onPrimaryContainer
            : scheme.onSurfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: Icon(icon),
    );
  }
}

class _MobilePaletteBar extends StatelessWidget {
  const _MobilePaletteBar({
    required this.controller,
    required this.onOpenPalette,
    required this.onTrueColor,
    required this.onCamera,
  });

  final EditorController controller;
  final VoidCallback onOpenPalette;
  final VoidCallback onTrueColor;
  final VoidCallback onCamera;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<int>(
      valueListenable: controller.colorRevision,
      builder: (context, _, _) {
        return Container(
          color: scheme.surface,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: <Widget>[
              Tooltip(
                message: '真彩色',
                child: InkWell(
                  borderRadius: BorderRadius.circular(99),
                  onTap: onTrueColor,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Color(controller.currentColor),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: scheme.outlineVariant,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: controller.recentColors.length <= 1
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '点开色板选择颜色',
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: controller.recentColors.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 7),
                          itemBuilder: (context, index) {
                            final color = controller.recentColors[index];
                            final selected = color == controller.currentColor;
                            return InkWell(
                              borderRadius: BorderRadius.circular(99),
                              onTap: () => controller.selectColor(color),
                              child: Container(
                                width: 28,
                                height: 28,
                                margin: const EdgeInsets.symmetric(vertical: 2),
                                decoration: BoxDecoration(
                                  color: Color(color),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: selected
                                        ? scheme.onSurface
                                        : const Color(0x33000000),
                                    width: selected ? 2.2 : 1,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
              IconButton(
                tooltip: '摄像头拾色',
                onPressed: onCamera,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.center_focus_strong_rounded, size: 21),
              ),
              const SizedBox(width: 2),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
                onPressed: onOpenPalette,
                icon: const Icon(Icons.palette_outlined, size: 18),
                label: const Text('色板'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(
      fontSize: 10,
      color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
    );
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final pattern = controller.pattern;
        final bead = controller.selectedBead;
        return Container(
          height: 28,
          color: scheme.surfaceContainerLow,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: <Widget>[
              Text('${pattern.width} × ${pattern.height}', style: muted),
              const SizedBox(width: 8),
              Text('·', style: muted),
              const SizedBox(width: 8),
              Text('${controller.currentBeadCount} 颗豆', style: muted),
              const SizedBox(width: 8),
              Text('·', style: muted),
              const SizedBox(width: 8),
              Text('${controller.currentColorCount} 色', style: muted),
              if (controller.frameCount > 1) ...<Widget>[
                const SizedBox(width: 8),
                Text('·', style: muted),
                const SizedBox(width: 8),
                Text(
                  '帧 ${controller.currentFrame + 1}/${controller.frameCount}',
                  style: muted,
                ),
              ],
              const Spacer(),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: Color(controller.currentColor),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0x33000000)),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                bead == null
                    ? formatHex(controller.currentColor)
                    : '${bead.brand} ${bead.code}',
                style: muted.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );
      },
    );
  }
}
