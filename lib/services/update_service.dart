// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pub_semver/pub_semver.dart';

import '../theme.dart';

class UpdateAsset {
  const UpdateAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
  });

  factory UpdateAsset.fromJson(Map<String, dynamic> json) => UpdateAsset(
    name: json['name'] as String? ?? '',
    downloadUrl: json['browser_download_url'] as String? ?? '',
    size: (json['size'] as num?)?.toInt() ?? 0,
  );

  final String name;
  final String downloadUrl;
  final int size;
}

class ReleaseInfo {
  const ReleaseInfo({
    required this.tagName,
    required this.name,
    required this.htmlUrl,
    required this.body,
    required this.publishedAt,
    required this.assets,
  });

  factory ReleaseInfo.fromJson(Map<String, dynamic> json) {
    final rawAssets = json['assets'];
    final assets = <UpdateAsset>[];
    if (rawAssets is List) {
      for (final entry in rawAssets) {
        if (entry is Map<String, dynamic>) {
          final asset = UpdateAsset.fromJson(entry);
          if (asset.name.isNotEmpty && asset.downloadUrl.isNotEmpty) {
            assets.add(asset);
          }
        }
      }
    }
    return ReleaseInfo(
      tagName: json['tag_name'] as String? ?? '',
      name: json['name'] as String? ?? '',
      htmlUrl: json['html_url'] as String? ?? '',
      body: json['body'] as String? ?? '',
      publishedAt: DateTime.tryParse(json['published_at'] as String? ?? ''),
      assets: List<UpdateAsset>.unmodifiable(assets),
    );
  }

  final String tagName;
  final String name;
  final String htmlUrl;
  final String body;
  final DateTime? publishedAt;
  final List<UpdateAsset> assets;

  Version? get version {
    try {
      return UpdateService.parseVersion(tagName);
    } on FormatException {
      return null;
    }
  }
}

class UpdateException implements Exception {
  const UpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

class UpdateInstallResult {
  const UpdateInstallResult({
    required this.message,
    this.filePath,
    this.opened = true,
  });

  final String message;
  final String? filePath;
  final bool opened;
}

class UpdateService {
  UpdateService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _latestReleaseUrl =
      'https://api.github.com/repos/$appRepository/releases/latest';

  static Version parseVersion(String raw) {
    var value = raw.trim();
    if (value.startsWith('v') || value.startsWith('V')) {
      value = value.substring(1);
    }
    return Version.parse(value);
  }

  static bool isNewer(String current, String latest) {
    try {
      return parseVersion(latest) > parseVersion(current);
    } on FormatException {
      return false;
    }
  }

  Future<ReleaseInfo?> fetchLatestRelease() async {
    final response = await _client
        .get(
          Uri.parse(_latestReleaseUrl),
          headers: const <String, String>{
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
            'User-Agent': 'bead-studio',
          },
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 404) return null;
    if (response.statusCode == 403) {
      throw const UpdateException('GitHub API 请求受限，请稍后再试。');
    }
    if (response.statusCode != 200) {
      throw UpdateException('检查更新失败（HTTP ${response.statusCode}）。');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const UpdateException('GitHub 返回了无法识别的数据。');
    }
    final release = ReleaseInfo.fromJson(decoded);
    if (release.tagName.isEmpty) {
      throw const UpdateException('最新版本缺少标签信息。');
    }
    return release;
  }

  void dispose() => _client.close();
}

String formatUpdateBytes(int bytes) {
  if (bytes <= 0) return '大小未知';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}
