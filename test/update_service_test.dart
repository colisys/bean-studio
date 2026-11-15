// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:bead_studio/services/update_installer.dart' as installer;
import 'package:bead_studio/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('version comparison', () {
    test('detects a newer patch release', () {
      expect(UpdateService.isNewer('1.0.0', 'v1.0.1'), isTrue);
      expect(UpdateService.isNewer('1.0.0+gabc1234', 'v1.0.1'), isTrue);
    });

    test('ignores build metadata and equal versions', () {
      expect(UpdateService.isNewer('1.0.1+gabc1234', 'v1.0.1'), isFalse);
      expect(UpdateService.isNewer('1.0.1', 'v1.0.1'), isFalse);
    });

    test('does not downgrade to prerelease or older versions', () {
      expect(UpdateService.isNewer('1.0.1', 'v1.0.1-beta.1'), isFalse);
      expect(UpdateService.isNewer('1.0.2', 'v1.0.1'), isFalse);
    });

    test('invalid tags are ignored', () {
      expect(UpdateService.isNewer('1.0.0', 'latest'), isFalse);
    });
  });

  test('parses release metadata and assets', () {
    final release = ReleaseInfo.fromJson(<String, dynamic>{
      'tag_name': 'v1.0.1',
      'name': 'v1.0.1',
      'html_url': 'https://github.com/colisys/bean-studio/releases/tag/v1.0.1',
      'body': 'notes',
      'published_at': '2026-11-16T00:00:00Z',
      'assets': <Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'BeadStudio-1.0.1+g123-android.apk',
          'browser_download_url': 'https://example.test/app.apk',
          'size': 123,
        },
        <String, dynamic>{
          'name': 'SHA256SUMS',
          'browser_download_url': 'https://example.test/SHA256SUMS',
          'size': 42,
        },
      ],
    });
    expect(release.tagName, 'v1.0.1');
    expect(release.version.toString(), '1.0.1');
    expect(release.assets.length, 2);
    expect(release.assets.first.size, 123);
    expect(release.publishedAt, isNotNull);
  });

  test('selects an AppImage on Linux', () {
    final asset = installer.selectUpdateAsset(const <UpdateAsset>[
      UpdateAsset(
        name: 'BeadStudio-android.apk',
        downloadUrl: 'https://example.test/app.apk',
        size: 1,
      ),
      UpdateAsset(
        name: 'BeadStudio-linux-x86_64.AppImage',
        downloadUrl: 'https://example.test/app.AppImage',
        size: 2,
      ),
    ]);
    expect(installer.canInstallUpdates, isTrue);
    expect(asset?.name, 'BeadStudio-linux-x86_64.AppImage');
  });

  test('formats download sizes', () {
    expect(formatUpdateBytes(0), '大小未知');
    expect(formatUpdateBytes(512 * 1024), '512 KB');
    expect(formatUpdateBytes(2 * 1024 * 1024), '2.0 MB');
  });
}
