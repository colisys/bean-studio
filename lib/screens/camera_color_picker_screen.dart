// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:material_ui/material_ui.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../models/bead_color.dart';
import '../utils/color_utils.dart';
import '../widgets/true_color_picker.dart';

class CameraColorPickerScreen extends StatefulWidget {
  const CameraColorPickerScreen({super.key, required this.palette});

  final BeadPalette palette;

  @override
  State<CameraColorPickerScreen> createState() =>
      _CameraColorPickerScreenState();
}

class _CameraColorPickerScreenState extends State<CameraColorPickerScreen> {
  CameraController? _camera;
  bool _initializing = true;
  String? _cameraError;
  bool _capturing = false;
  int? _pickedColor;

  Offset _cameraFocus = const Offset(0.5, 0.5);
  Offset _photoFocus = const Offset(0.5, 0.5);

  Uint8List? _photoBytes;
  img.Image? _photo;
  bool _photoMode = false;

  late final ColorMatcher _matcher = ColorMatcher(
    widget.palette.matchableColors.isEmpty
        ? widget.palette.colors
        : widget.palette.matchableColors,
  );

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    setState(() {
      _initializing = true;
      _cameraError = null;
    });
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError('未检测到可用摄像头');
      }
      final selected = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        selected,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _initializing = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _cameraError = _friendlyError(error);
        _initializing = false;
      });
    }
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('permission') || text.contains('Permission')) {
      return '没有摄像头权限，请在系统设置中允许访问摄像头。';
    }
    if (text.contains('MissingPlugin') || text.contains('Unimplemented')) {
      return '当前平台不支持实时摄像头，可从照片中拾取颜色。';
    }
    return '无法启动摄像头：$text';
  }

  @override
  void dispose() {
    _camera?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final camera = _camera;
    if (camera == null || _capturing) return;
    setState(() => _capturing = true);
    try {
      final file = await camera.takePicture();
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) throw const FormatException('无法读取摄像头照片');
      final image = img.bakeOrientation(decoded);
      final color = _sample(image, _cameraFocus.dx, _cameraFocus.dy);
      if (!mounted) return;
      setState(() {
        _pickedColor = color;
        _capturing = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _capturing = false);
      _snack('拾取失败：$error');
    }
  }

  Future<void> _pickPhoto() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2400,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) throw const FormatException('无法读取图片');
      final image = img.bakeOrientation(decoded);
      final color = _sample(image, 0.5, 0.5);
      await _camera?.dispose();
      if (!mounted) return;
      setState(() {
        _camera = null;
        _photoBytes = bytes;
        _photo = image;
        _photoMode = true;
        _photoFocus = const Offset(0.5, 0.5);
        _pickedColor = color;
        _initializing = false;
      });
    } on Object catch (error) {
      if (mounted) _snack('读取图片失败：$error');
    }
  }

  void _pickFromPhotoAt(Offset normalized) {
    final photo = _photo;
    if (photo == null) return;
    final color = _sample(photo, normalized.dx, normalized.dy);
    setState(() {
      _photoFocus = normalized;
      _pickedColor = color;
    });
  }

  int _sample(img.Image image, double nx, double ny) {
    final centerX = (nx.clamp(0.0, 1.0) * (image.width - 1)).round();
    final centerY = (ny.clamp(0.0, 1.0) * (image.height - 1)).round();
    var sumR = 0;
    var sumG = 0;
    var sumB = 0;
    var count = 0;
    for (var oy = -2; oy <= 2; oy++) {
      for (var ox = -2; ox <= 2; ox++) {
        final x = (centerX + ox).clamp(0, image.width - 1);
        final y = (centerY + oy).clamp(0, image.height - 1);
        final pixel = image.getPixel(x, y);
        if (pixel.a < 16) continue;
        sumR += pixel.r.toInt();
        sumG += pixel.g.toInt();
        sumB += pixel.b.toInt();
        count++;
      }
    }
    if (count == 0) return 0xFF808080;
    return 0xFF000000 |
        ((sumR ~/ count) << 16) |
        ((sumG ~/ count) << 8) |
        (sumB ~/ count);
  }

  Future<void> _manualColor() async {
    final color = await showTrueColorPicker(
      context,
      initialColor: _pickedColor ?? 0xFFFFFFFF,
      palette: widget.palette,
    );
    if (color != null && mounted) {
      setState(() => _pickedColor = color);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('摄像头拾色'),
        actions: <Widget>[
          if (_photoMode)
            IconButton(
              tooltip: '重新选择照片',
              onPressed: _pickPhoto,
              icon: const Icon(Icons.photo_library_outlined),
            ),
          IconButton(
            tooltip: '手动调色',
            onPressed: _manualColor,
            icon: const Icon(Icons.palette_outlined),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(child: _buildPreview()),
          _buildResultPanel(context),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    if (_photoMode && _photo != null && _photoBytes != null) {
      return _buildPhotoPreview();
    }
    if (_initializing) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircularProgressIndicator(),
            SizedBox(height: 14),
            Text('正在启动摄像头…'),
          ],
        ),
      );
    }
    if (_camera != null) {
      return _buildCameraPreview();
    }
    return _buildCameraFallback();
  }

  Widget _buildCameraPreview() {
    final camera = _camera!;
    final scheme = Theme.of(context).colorScheme;
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final previewRatio = isLandscape
        ? camera.value.aspectRatio
        : 1 / camera.value.aspectRatio;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: AspectRatio(
          aspectRatio: previewRatio,
          child: LayoutBuilder(
            builder: (context, constraints) {
              void move(Offset local) {
                final normalized = Offset(
                  (local.dx / constraints.maxWidth).clamp(0.0, 1.0),
                  (local.dy / constraints.maxHeight).clamp(0.0, 1.0),
                );
                setState(() => _cameraFocus = normalized);
              }

              return GestureDetector(
                onTapDown: (details) => move(details.localPosition),
                onPanUpdate: (details) => move(details.localPosition),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      CameraPreview(camera),
                      CustomPaint(
                        painter: _CrosshairPainter(
                          focus: _cameraFocus,
                          color: Color(_pickedColor ?? 0xFFFFFFFF),
                        ),
                      ),
                      Positioned(
                        left: 12,
                        top: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.surface.withValues(alpha: 0.82),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: const Text(
                            '移动取景框，点击下方「拾取颜色」',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoPreview() {
    final image = _photo!;
    final bytes = _photoBytes!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: AspectRatio(
          aspectRatio: image.width / image.height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              void pick(Offset local) {
                final normalized = Offset(
                  (local.dx / constraints.maxWidth).clamp(0.0, 1.0),
                  (local.dy / constraints.maxHeight).clamp(0.0, 1.0),
                );
                _pickFromPhotoAt(normalized);
              }

              return GestureDetector(
                onTapDown: (details) => pick(details.localPosition),
                onPanUpdate: (details) => pick(details.localPosition),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      Image.memory(
                        bytes,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      ),
                      CustomPaint(
                        painter: _CrosshairPainter(
                          focus: _photoFocus,
                          color: Color(_pickedColor ?? 0xFFFFFFFF),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCameraFallback() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.videocam_off_outlined,
                size: 38,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              '此设备无法使用实时摄像头',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              _cameraError ?? '可以从照片中拾取颜色，或使用手动调色板。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.55,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: _pickPhoto,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('从照片拾色'),
                ),
                OutlinedButton.icon(
                  onPressed: _manualColor,
                  icon: const Icon(Icons.palette_outlined),
                  label: const Text('手动调色'),
                ),
                TextButton(onPressed: _initCamera, child: const Text('重试摄像头')),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '桌面端通常没有摄像头插件支持；手机端请允许相机权限。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10.5,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultPanel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final picked = _pickedColor;
    if (_camera == null && !_photoMode && picked == null) {
      return const SizedBox.shrink();
    }
    final nearest = picked == null ? null : _matcher.nearest(picked);
    final suggestions = picked == null
        ? const <BeadColor>[]
        : _matcher.nearestN(picked, 6);

    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (picked == null)
              Text(
                _photoMode ? '点击照片中的任意位置来取样颜色。' : '把取景框对准颜色，然后点击「拾取颜色」。',
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              )
            else
              Row(
                children: <Widget>[
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Color(picked),
                      shape: BoxShape.circle,
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          formatHex(picked),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          nearest == null
                              ? '未匹配到常用色号'
                              : '最接近 ${nearest.brand} ${nearest.displayName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            if (suggestions.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              SizedBox(
                height: 42,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: suggestions.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final bead = suggestions[index];
                    final selected = bead.argb == picked;
                    return ActionChip(
                      avatar: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: Color(bead.argb),
                          shape: BoxShape.circle,
                        ),
                      ),
                      label: Text('${bead.code}  ${bead.hex}'),
                      side: BorderSide(
                        color: selected
                            ? scheme.primary
                            : scheme.outlineVariant,
                        width: selected ? 1.6 : 1,
                      ),
                      onPressed: () => setState(() => _pickedColor = bead.argb),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                if (!_photoMode && _camera != null)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _camera == null || _capturing
                          ? null
                          : _capture,
                      icon: _capturing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.center_focus_strong_rounded),
                      label: Text(_capturing ? '拾取中…' : '拾取颜色'),
                    ),
                  )
                else
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickPhoto,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text(_photoMode ? '换一张照片' : '从照片拾色'),
                    ),
                  ),
                if (!_photoMode && _camera != null) ...<Widget>[
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickPhoto,
                      icon: const Icon(Icons.photo_outlined),
                      label: const Text('从照片拾色'),
                    ),
                  ),
                ],
              ],
            ),
            if (picked != null) ...<Widget>[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context, picked),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('使用这个颜色'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  _CrosshairPainter({required this.focus, required this.color});

  final Offset focus;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(focus.dx * size.width, focus.dy * size.height);
    final radius = math.min(size.width, size.height) * 0.16;

    final outer = Path()..addRect(Offset.zero & size);
    final hole = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    canvas.drawPath(
      Path.combine(PathOperation.difference, outer, hole),
      Paint()..color = Colors.black.withValues(alpha: 0.18),
    );

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = Colors.black.withValues(alpha: 0.45),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );

    final linePaint = Paint()
      ..strokeWidth = 3
      ..color = Colors.white;
    canvas.drawLine(
      center.translate(-radius * 0.55, 0),
      center.translate(radius * 0.55, 0),
      linePaint,
    );
    canvas.drawLine(
      center.translate(0, -radius * 0.55),
      center.translate(0, radius * 0.55),
      linePaint,
    );
    canvas.drawCircle(
      center,
      5,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      5,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _CrosshairPainter oldDelegate) =>
      oldDelegate.focus != focus || oldDelegate.color != color;
}
