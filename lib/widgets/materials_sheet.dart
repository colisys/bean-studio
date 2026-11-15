// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../services/export_service.dart';
import '../state/editor_controller.dart';
import '../utils/bead_lookup.dart';
import '../utils/color_utils.dart';

Future<void> showMaterialsSheet(
  BuildContext context, {
  required EditorController controller,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.78,
      child: _MaterialsSheet(controller: controller),
    ),
  );
}

class _MaterialsSheet extends StatelessWidget {
  const _MaterialsSheet({required this.controller});

  final EditorController controller;

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copy(BuildContext context) async {
    final text = ExportService.materialsText(
      controller.pattern,
      palette: controller.palette,
    );
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) _snack(context, '材料清单已复制');
  }

  Future<void> _exportCsv(BuildContext context) async {
    final pattern = controller.pattern;
    final csv = ExportService.materialsCsv(
      pattern,
      palette: controller.palette,
    );
    final bytes = ExportService.textBytes(csv);
    final filename = ExportService.safeFilename(pattern.title, '.csv');
    try {
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
      if (path != null && context.mounted) {
        _snack(context, ExportService.isMobile ? '已打开分享面板' : '材料清单已导出');
      }
    } on Object catch (error) {
      if (context.mounted) _snack(context, '导出失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pattern = controller.pattern;
    final entries = pattern.colorCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Material(
      color: scheme.surface,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 10, 4),
            child: Row(
              children: <Widget>[
                const Text(
                  '材料清单',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 10),
                Text(
                  '${pattern.beadCount} 颗 · ${pattern.usedColorCount} 色',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Text(
                      '画布还是空的，先拼几颗豆吧。',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 16,
                      color: scheme.outlineVariant.withValues(alpha: 0.6),
                    ),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final bead = findBeadForColor(
                        entry.key,
                        preferred: controller.palette,
                      );
                      return Row(
                        children: <Widget>[
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: Color(entry.key),
                              shape: BoxShape.circle,
                              border: Border.all(color: scheme.outlineVariant),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  bead == null
                                      ? formatHex(entry.key)
                                      : '${bead.brand} ${bead.code}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  bead == null
                                      ? '自定义颜色'
                                      : bead.name == bead.code
                                      ? bead.hex
                                      : '${bead.name} · ${bead.hex}',
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
                          const SizedBox(width: 10),
                          Text(
                            '${entry.value} 颗',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _copy(context),
                      icon: const Icon(Icons.copy_rounded, size: 17),
                      label: const Text('复制清单'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _exportCsv(context),
                      icon: const Icon(Icons.table_view_rounded, size: 17),
                      label: const Text('导出 CSV'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
