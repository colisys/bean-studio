// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

bool get canSaveToDisk => true;

bool get isMobilePlatform => false;

Future<String?> saveBytesToDisk({
  required Uint8List bytes,
  required String filename,
  required String mime,
  required List<String> extensions,
}) async {
  final parts = <JSAny>[bytes.toJS].toJS;
  final blob = web.Blob(parts, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
  anchor.href = url;
  anchor.download = filename;
  anchor.style.display = 'none';
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  await Future<void>.delayed(const Duration(milliseconds: 100));
  web.URL.revokeObjectURL(url);
  return filename;
}

Future<String?> shareBytesFile({
  required Uint8List bytes,
  required String filename,
  required String mime,
  String? text,
}) => saveBytesToDisk(
  bytes: bytes,
  filename: filename,
  mime: mime,
  extensions: const <String>[],
);
