// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

bool get canSaveToDisk => !(Platform.isAndroid || Platform.isIOS);

bool get isMobilePlatform => Platform.isAndroid || Platform.isIOS;

Future<String?> saveBytesToDisk({
  required Uint8List bytes,
  required String filename,
  required String mime,
  required List<String> extensions,
}) async {
  final location = await getSaveLocation(
    suggestedName: filename,
    acceptedTypeGroups: <XTypeGroup>[
      XTypeGroup(
        label: '导出文件',
        extensions: extensions,
        mimeTypes: <String>[mime],
      ),
    ],
  );
  if (location == null) return null;
  final file = File(location.path);
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

Future<String?> shareBytesFile({
  required Uint8List bytes,
  required String filename,
  required String mime,
  String? text,
}) async {
  final directory = await getTemporaryDirectory();
  final file = File('${directory.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);

  try {
    final result = await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(file.path, mimeType: mime)],
        text: text,
      ),
    );
    if (result.status == ShareResultStatus.unavailable) {
      return await _fallbackSave(bytes, filename, mime);
    }
    return result.status == ShareResultStatus.success ? file.path : null;
  } on Object {
    if (!canSaveToDisk) rethrow;
    return await _fallbackSave(bytes, filename, mime);
  }
}

Future<String?> _fallbackSave(
  Uint8List bytes,
  String filename,
  String mime,
) async {
  if (!canSaveToDisk) return null;
  final dot = filename.lastIndexOf('.');
  final extension = dot >= 0 ? filename.substring(dot + 1) : 'dat';
  return saveBytesToDisk(
    bytes: bytes,
    filename: filename,
    mime: mime,
    extensions: <String>[extension],
  );
}
