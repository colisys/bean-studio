// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:typed_data';

/// Encodes cell colours as run-length pairs: `count:argbhex;...`.
String encodeRle(Uint32List cells) {
  if (cells.isEmpty) return '';
  final out = StringBuffer();
  var previous = cells[0];
  var run = 1;

  void flush() {
    if (out.isNotEmpty) out.write(';');
    out
      ..write(run)
      ..write(':')
      ..write(previous.toRadixString(16).padLeft(8, '0'));
  }

  for (var i = 1; i < cells.length; i++) {
    final value = cells[i];
    if (value == previous) {
      run++;
    } else {
      flush();
      previous = value;
      run = 1;
    }
  }
  flush();
  return out.toString();
}

Uint32List decodeRle(String source, int expectedLength) {
  if (expectedLength < 0) {
    throw const FormatException('画布尺寸无效');
  }
  if (source.isEmpty) {
    if (expectedLength != 0) {
      throw const FormatException('画布数据为空');
    }
    return Uint32List(0);
  }

  final cells = Uint32List(expectedLength);
  var offset = 0;

  for (final part in source.split(';')) {
    final separator = part.indexOf(':');
    if (separator <= 0) {
      throw const FormatException('画布数据格式错误');
    }
    final count = int.tryParse(part.substring(0, separator));
    final value = int.tryParse(part.substring(separator + 1), radix: 16);
    if (count == null || value == null || count <= 0) {
      throw const FormatException('画布数据格式错误');
    }
    if (offset + count > expectedLength) {
      throw const FormatException('画布数据长度超出画布尺寸');
    }
    for (var i = 0; i < count; i++) {
      cells[offset + i] = value;
    }
    offset += count;
  }

  if (offset != expectedLength) {
    throw const FormatException('画布数据长度与画布尺寸不符');
  }
  return cells;
}
