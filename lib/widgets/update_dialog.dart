// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/update_installer.dart';
import '../services/update_service.dart';
import '../theme.dart';

Future<void> showUpdateDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _UpdateDialog(),
  );
}

enum _Phase { checking, upToDate, available, error }

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog();

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  final UpdateService _service = UpdateService();

  _Phase _phase = _Phase.checking;
  ReleaseInfo? _release;
  UpdateAsset? _asset;
  String? _error;
  bool _downloading = false;
  double? _progress;
  String? _installMessage;
  String? _installError;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() {
      _phase = _Phase.checking;
      _error = null;
      _installMessage = null;
      _installError = null;
      _progress = null;
    });
    try {
      final release = await _service.fetchLatestRelease();
      if (!mounted) return;
      if (release == null) {
        setState(() {
          _phase = _Phase.error;
          _error = '这个仓库还没有发布版本。';
        });
        return;
      }
      if (release.version == null) {
        setState(() {
          _phase = _Phase.error;
          _error = '无法解析最新版本号：${release.tagName}';
        });
        return;
      }
      final available = UpdateService.isNewer(appVersion, release.tagName);
      setState(() {
        _release = release;
        _asset = available ? selectUpdateAsset(release.assets) : null;
        _phase = available ? _Phase.available : _Phase.upToDate;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = _friendly(error);
      });
    }
  }

  String _friendly(Object error) {
    if (error is UpdateException) return error.message;
    final text = error.toString();
    if (text.contains('TimeoutException')) {
      return '连接 GitHub 超时，请检查网络后重试。';
    }
    if (text.contains('SocketException') ||
        text.contains('ClientException')) {
      return '网络连接失败，请检查网络后重试。';
    }
    return '检查更新失败：$text';
  }

  Future<void> _openReleasePage() async {
    final url = (_release?.htmlUrl.isNotEmpty ?? false)
        ? _release!.htmlUrl
        : appReleasesUrl;
    try {
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        setState(() => _installError = '无法打开浏览器，请手动访问 $url');
      }
    } on Object catch (error) {
      if (mounted) setState(() => _installError = '无法打开发布页：$error');
    }
  }

  Future<void> _download() async {
    final asset = _asset;
    if (asset == null || _downloading) return;
    setState(() {
      _downloading = true;
      _progress = 0;
      _installMessage = null;
      _installError = null;
    });
    try {
      final result = await downloadAndInstallUpdate(
        asset,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _progress = progress);
        },
      );
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _installMessage = result.message;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _installError = _friendly(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_downloading,
      child: AlertDialog(
      title: Row(
        children: <Widget>[
          Icon(Icons.system_update_alt_rounded, color: scheme.primary),
          const SizedBox(width: 10),
          const Text('检查更新'),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(child: _buildContent(context)),
      ),
      actions: _buildActions(context),
      actionsOverflowDirection: VerticalDirection.down,
      actionsOverflowButtonSpacing: 6,
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(
      fontSize: 12,
      height: 1.5,
      color: scheme.onSurfaceVariant,
    );
    switch (_phase) {
      case _Phase.checking:
        return SizedBox(
          height: 150,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text('正在检查 GitHub 最新版本…', style: muted),
                const SizedBox(height: 4),
                Text('当前版本 $appVersionLabel', style: muted),
              ],
            ),
          ),
        );
      case _Phase.error:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.cloud_off_rounded, color: scheme.error),
                const SizedBox(width: 10),
                const Text(
                  '暂时无法检查更新',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(_error ?? '未知错误', style: muted),
            if (_installError != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                _installError!,
                style: TextStyle(fontSize: 12, color: scheme.error),
              ),
            ],
            const SizedBox(height: 12),
            Text('当前版本 $appVersionLabel', style: muted),
          ],
        );
      case _Phase.upToDate:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.check_circle_rounded, color: scheme.primary),
                const SizedBox(width: 10),
                const Text(
                  '已是最新版本',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('当前版本 $appVersionLabel', style: muted),
            if (_release != null) ...<Widget>[
              const SizedBox(height: 4),
              Text('GitHub 最新版本：${_release!.tagName}', style: muted),
            ],
          ],
        );
      case _Phase.available:
        final release = _release!;
        final notes = release.body.trim().isEmpty
            ? '此版本没有附加说明。'
            : release.body.trim();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.new_releases_rounded, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '发现新版本 ${release.tagName}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('当前 $appVersionLabel', style: muted),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 180),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: SingleChildScrollView(
                child: SelectableText(notes, style: muted),
              ),
            ),
            const SizedBox(height: 14),
            if (_asset != null) ...<Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    Icons.download_rounded,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${_asset!.name} · ${formatUpdateBytes(_asset!.size)}',
                      style: muted,
                    ),
                  ),
                ],
              ),
            ] else ...<Widget>[
              Text(_noAssetMessage(), style: muted),
            ],
            if (_downloading) ...<Widget>[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: _progress,
                minHeight: 6,
                borderRadius: BorderRadius.circular(99),
              ),
              const SizedBox(height: 8),
              Text(
                _progress == null
                    ? '正在下载…'
                    : '正在下载 ${(_progress! * 100).round()}%',
                style: muted,
              ),
            ],
            if (_installMessage != null) ...<Widget>[
              const SizedBox(height: 14),
              Text(
                _installMessage!,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (_installError != null) ...<Widget>[
              const SizedBox(height: 14),
              Text(
                _installError!,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: scheme.error,
                ),
              ),
            ],
          ],
        );
    }
  }

  String _noAssetMessage() {
    if (!canInstallUpdates) {
      return '当前平台不支持应用内安装；请前往 GitHub 下载，iOS 需要自行签名。';
    }
    return '当前平台暂时没有可自动安装的包，请前往 GitHub Release 手动下载。';
  }

  List<Widget> _buildActions(BuildContext context) {
    switch (_phase) {
      case _Phase.checking:
        return <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ];
      case _Phase.error:
        return <Widget>[
          TextButton(onPressed: _openReleasePage, child: const Text('打开发布页')),
          TextButton(onPressed: _check, child: const Text('重试')),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ];
      case _Phase.upToDate:
        return <Widget>[
          TextButton(onPressed: _openReleasePage, child: const Text('打开发布页')),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ];
      case _Phase.available:
        if (_downloading) {
          return <Widget>[
            TextButton(
              onPressed: null,
              child: Text(
                _progress == null
                    ? '下载中…'
                    : '下载中 ${(_progress! * 100).round()}%',
              ),
            ),
          ];
        }
        if (_installMessage != null) {
          return <Widget>[
            TextButton(
              onPressed: _openReleasePage,
              child: const Text('打开发布页'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('完成'),
            ),
          ];
        }
        return <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('稍后'),
          ),
          TextButton(onPressed: _openReleasePage, child: const Text('打开发布页')),
          if (_asset != null && canInstallUpdates)
            FilledButton.icon(
              onPressed: _download,
              icon: const Icon(Icons.download_rounded, size: 18),
              label: Text(updatePlatformLabel),
            )
          else
            FilledButton(
              onPressed: _openReleasePage,
              child: const Text('前往 GitHub'),
            ),
        ];
    }
  }
}
