// SPDX-License-Identifier: GPL-3.0-or-later
import 'update_service.dart';

bool get canInstallUpdates => false;

String get updatePlatformLabel => '前往 GitHub';

String get installResultHint => '请在 GitHub Release 页面下载并手动安装。';

UpdateAsset? selectUpdateAsset(List<UpdateAsset> assets) => null;

Future<UpdateInstallResult> downloadAndInstallUpdate(
  UpdateAsset asset, {
  void Function(double? progress)? onProgress,
}) async {
  throw const UpdateException('当前平台不支持应用内安装更新。');
}
