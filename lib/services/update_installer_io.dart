// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:ffi';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'update_service.dart';

bool get canInstallUpdates =>
    Platform.isAndroid ||
    Platform.isLinux ||
    Platform.isMacOS ||
    Platform.isWindows;

String get updatePlatformLabel {
  if (Platform.isAndroid) return '下载 APK';
  if (Platform.isLinux) return '下载 AppImage';
  if (Platform.isMacOS) return '下载 DMG';
  if (Platform.isWindows) return '下载安装包';
  return '前往 GitHub';
}

String get installResultHint {
  if (Platform.isAndroid) {
    return '已打开系统安装器。若提示签名不一致，请先卸载旧版本再安装。';
  }
  if (Platform.isLinux) {
    return '新版本 AppImage 已下载并启动，可用它替换旧文件。';
  }
  if (Platform.isMacOS) {
    return '已打开 DMG，请把应用拖入「应用程序」覆盖旧版本。';
  }
  if (Platform.isWindows) {
    return '安装包已打开，请按照提示完成安装。';
  }
  return '请前往 GitHub Release 手动下载。';
}

UpdateAsset? selectUpdateAsset(List<UpdateAsset> assets) {
  if (Platform.isIOS) return null;
  if (Platform.isAndroid) {
    return _firstWithExtension(assets, '.apk');
  }
  if (Platform.isLinux) {
    return _firstWithExtension(assets, '.AppImage');
  }
  if (Platform.isMacOS) {
    final dmgAssets = assets
        .where((asset) => asset.name.toLowerCase().endsWith('.dmg'))
        .toList(growable: false);
    if (dmgAssets.isEmpty) return null;
    final arch = switch (Abi.current()) {
      Abi.macosArm64 => 'arm64',
      Abi.macosX64 => 'x86_64',
      _ => '',
    };
    if (arch.isNotEmpty) {
      for (final asset in dmgAssets) {
        if (asset.name.contains('macos-$arch')) return asset;
      }
    }
    return dmgAssets.first;
  }
  if (Platform.isWindows) {
    return _firstWithExtension(assets, '.exe') ??
        _firstWithExtension(assets, '.msix') ??
        _firstWithExtension(assets, '.zip');
  }
  return null;
}

UpdateAsset? _firstWithExtension(List<UpdateAsset> assets, String extension) {
  final lower = extension.toLowerCase();
  for (final asset in assets) {
    if (asset.name.toLowerCase().endsWith(lower)) return asset;
  }
  return null;
}

Future<UpdateInstallResult> downloadAndInstallUpdate(
  UpdateAsset asset, {
  void Function(double? progress)? onProgress,
}) async {
  if (!canInstallUpdates) {
    throw const UpdateException('当前平台不支持应用内安装更新。');
  }
  final directory = await _downloadDirectory();
  final filename = p.basename(asset.name);
  final file = File(p.join(directory.path, filename));
  final client = http.Client();
  var completed = false;
  try {
    final request = http.Request('GET', Uri.parse(asset.downloadUrl));
    request.headers['User-Agent'] = 'bead-studio';
    request.headers['Accept'] = 'application/octet-stream';
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw UpdateException('下载失败（HTTP ${response.statusCode}）。');
    }
    final total = response.contentLength ?? asset.size;
    final sink = file.openWrite();
    var received = 0;
    var lastProgress = -1.0;
    try {
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 60),
      )) {
        sink.add(chunk);
        received += chunk.length;
        final progress = total > 0 ? received / total : null;
        if (progress == null ||
            progress - lastProgress >= 0.01 ||
            progress >= 1) {
          lastProgress = progress ?? lastProgress;
          onProgress?.call(progress);
        }
      }
    } finally {
      await sink.close();
    }
    if (received == 0) {
      throw const UpdateException('下载的文件为空。');
    }
    completed = true;
    if (Platform.isLinux) {
      final chmod = await Process.run('chmod', <String>['+x', file.path]);
      if (chmod.exitCode != 0) {
        throw const UpdateException('无法为新版 AppImage 添加执行权限。');
      }
    }
    OpenResult result;
    try {
      result = await OpenFilex.open(
        file.path,
        type: Platform.isAndroid
            ? 'application/vnd.android.package-archive'
            : null,
      );
    } on Object {
      return UpdateInstallResult(
        opened: false,
        filePath: file.path,
        message: _openFailedMessage(file.path),
      );
    }
    if (result.type != ResultType.done) {
      return UpdateInstallResult(
        opened: false,
        filePath: file.path,
        message: _openFailedMessage(file.path),
      );
    }
    return UpdateInstallResult(
      filePath: file.path,
      message: installResultHint,
    );
  } on UpdateException {
    rethrow;
  } on Object catch (error) {
    throw UpdateException('下载或安装失败：$error');
  } finally {
    client.close();
    if (!completed && await file.exists()) {
      try {
        await file.delete();
      } on Object {
        // Ignore cleanup failures.
      }
    }
  }
}

String _openFailedMessage(String path) {
  if (Platform.isAndroid) {
    return '安装包已下载，但系统安装器没有打开。请允许本应用安装未知应用后重试。\n文件：$path';
  }
  if (Platform.isMacOS) {
    return '安装包已下载，但无法自动打开。\n文件：$path';
  }
  if (Platform.isWindows) {
    return '安装包已下载，但无法自动打开。\n文件：$path';
  }
  return '新版本已下载，但无法自动启动。\n文件：$path\n请手动运行或替换旧版本。';
}

Future<Directory> _downloadDirectory() async {
  if (Platform.isAndroid) {
    final base = await getTemporaryDirectory();
    final directory = Directory(p.join(base.path, 'bead-studio-updates'));
    await directory.create(recursive: true);
    return directory;
  }
  Directory? base;
  try {
    base = await getDownloadsDirectory();
  } on Object {
    base = null;
  }
  base ??= await getTemporaryDirectory();
  final directory = Directory(p.join(base.path, 'bead-studio-updates'));
  await directory.create(recursive: true);
  return directory;
}
