// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:file_selector/file_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/pattern.dart';

/// In-app project library. SharedPreferences keeps the library working on
/// desktop, mobile and web without a database; single projects can still be
/// exported to and imported from JSON files.
class ProjectStore {
  static const String _prefix = 'bead_studio.project.';
  static const String _lastProjectKey = 'bead_studio.last_project';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<List<BeadPattern>> loadAll() async {
    final prefs = await _prefs;
    final patterns = <BeadPattern>[];
    for (final key in prefs.getKeys().where((key) => key.startsWith(_prefix))) {
      final raw = prefs.getString(key);
      if (raw == null) continue;
      try {
        patterns.add(BeadPattern.fromJsonString(raw));
      } on Object {
        // Ignore a single broken entry rather than losing the whole library.
      }
    }
    patterns.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return patterns;
  }

  Future<BeadPattern?> load(String id) async {
    final prefs = await _prefs;
    final raw = prefs.getString('$_prefix$id');
    if (raw == null) return null;
    try {
      return BeadPattern.fromJsonString(raw);
    } on Object {
      return null;
    }
  }

  Future<bool> save(BeadPattern pattern) async {
    final prefs = await _prefs;
    return prefs.setString('$_prefix${pattern.id}', pattern.toJsonString());
  }

  Future<void> delete(String id) async {
    final prefs = await _prefs;
    await prefs.remove('$_prefix$id');
    if (prefs.getString(_lastProjectKey) == id) {
      await prefs.remove(_lastProjectKey);
    }
  }

  Future<String?> lastProjectId() async {
    final prefs = await _prefs;
    return prefs.getString(_lastProjectKey);
  }

  Future<void> rememberLastProject(String id) async {
    final prefs = await _prefs;
    await prefs.setString(_lastProjectKey, id);
  }

  Future<BeadPattern?> importFromFile() async {
    const typeGroup = XTypeGroup(
      label: '拼豆工坊工程',
      extensions: <String>['json', 'bead'],
      mimeTypes: <String>['application/json'],
    );
    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[typeGroup],
    );
    if (file == null) return null;

    final pattern = BeadPattern.fromJsonString(await file.readAsString());
    // Never trust an id from an external file as a storage key.
    final imported = pattern.copyWithId(generatePatternId());
    if (!await save(imported)) {
      throw StateError('保存工程失败，设备存储空间可能不足');
    }
    return imported;
  }
}
