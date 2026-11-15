// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:material_ui/material_ui.dart';

import '../data/palettes.dart';
import '../models/bead_color.dart';
import '../screens/camera_color_picker_screen.dart';
import '../state/editor_controller.dart';
import '../utils/color_utils.dart';
import 'true_color_picker.dart';

class PalettePanel extends StatefulWidget {
  const PalettePanel({
    super.key,
    required this.controller,
    this.showHeader = true,
    this.showClose = false,
  });

  final EditorController controller;
  final bool showHeader;
  final bool showClose;

  @override
  State<PalettePanel> createState() => _PalettePanelState();
}

class _PalettePanelState extends State<PalettePanel> {
  final TextEditingController _searchController = TextEditingController();
  late String _brandId = widget.controller.palette.id;
  String _query = '';

  EditorController get _controller => widget.controller;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<BeadColor> get _colors {
    final source = _brandId == 'all'
        ? allBuiltInColors
        : _controller.palette.colors;
    if (_query.trim().isEmpty) return source;
    final query = _query.trim().toLowerCase();
    return source
        .where(
          (bead) =>
              bead.code.toLowerCase().contains(query) ||
              bead.name.toLowerCase().contains(query) ||
              bead.brand.toLowerCase().contains(query) ||
              bead.hex.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  void _selectBrand(String id) {
    if (id == _brandId) return;
    setState(() => _brandId = id);
    if (id != 'all') {
      final palette = builtInPalettes.firstWhere((p) => p.id == id);
      _controller.setPalette(palette);
    }
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

  Future<void> _pickFromCamera() async {
    final color = await Navigator.of(context).push<int>(
      MaterialPageRoute<int>(
        builder: (_) => CameraColorPickerScreen(palette: _controller.palette),
      ),
    );
    if (color != null) _controller.selectColor(color);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final colors = _colors;
        final selected = _controller.selectedBead;
        final current = Color(_controller.currentColor);

        return Material(
          color: scheme.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (widget.showHeader)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 12, 0),
                  child: Row(
                    children: <Widget>[
                      const Text(
                        '色板',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '真彩色 + 常用色号',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      if (widget.showClose)
                        IconButton(
                          tooltip: '关闭',
                          onPressed: () => Navigator.maybePop(context),
                          icon: const Icon(Icons.close_rounded, size: 20),
                        ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: current,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: scheme.outlineVariant,
                          width: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            formatHex(_controller.currentColor),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                            ),
                          ),
                          Text(
                            selected == null
                                ? '自定义颜色'
                                : '${selected.brand} ${selected.displayName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '真彩色',
                      onPressed: _pickTrueColor,
                      icon: const Icon(Icons.palette_outlined, size: 20),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: <Widget>[
                    for (final palette in builtInPalettes) ...<Widget>[
                      ChoiceChip(
                        label: Text(palette.name),
                        selected: _brandId == palette.id,
                        onSelected: (_) => _selectBrand(palette.id),
                        showCheckmark: false,
                      ),
                      const SizedBox(width: 6),
                    ],
                    ChoiceChip(
                      label: const Text('全部'),
                      selected: _brandId == 'all',
                      onSelected: (_) => _selectBrand('all'),
                      showCheckmark: false,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: '搜索色号或名称',
                    isDense: true,
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清除',
                            icon: const Icon(Icons.close_rounded, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          ),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 2, 18, 4),
                child: Row(
                  children: <Widget>[
                    Text(
                      '${colors.length} 色',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '屏幕近似色',
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: colors.isEmpty
                    ? Center(
                        child: Text(
                          '没有匹配的色号',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 58,
                              mainAxisExtent: 52,
                              crossAxisSpacing: 2,
                              mainAxisSpacing: 2,
                            ),
                        itemCount: colors.length,
                        itemBuilder: (context, index) {
                          final bead = colors[index];
                          final isSelected =
                              selected != null &&
                              selected.brand == bead.brand &&
                              selected.code == bead.code;
                          return Tooltip(
                            message:
                                '${bead.brand} ${bead.code}\n${bead.name}\n${bead.hex}',
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => _controller.selectBead(bead),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: <Widget>[
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 120),
                                    width: 31,
                                    height: 31,
                                    decoration: BoxDecoration(
                                      color: Color(bead.argb),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isSelected
                                            ? scheme.onSurface
                                            : const Color(0x33000000),
                                        width: isSelected ? 2.4 : 1,
                                      ),
                                      boxShadow: isSelected
                                          ? <BoxShadow>[
                                              BoxShadow(
                                                color: scheme.primary
                                                    .withValues(alpha: 0.25),
                                                blurRadius: 6,
                                              ),
                                            ]
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    bead.code,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 8.5,
                                      height: 1,
                                      fontWeight: isSelected
                                          ? FontWeight.w800
                                          : FontWeight.w500,
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
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickTrueColor,
                        icon: const Icon(Icons.palette_outlined, size: 18),
                        label: const Text('真彩色'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickFromCamera,
                        icon: const Icon(
                          Icons.center_focus_strong_rounded,
                          size: 18,
                        ),
                        label: const Text('摄像头'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
