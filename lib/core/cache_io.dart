/// Cache offline untuk platform dengan `dart:io` (Android, desktop).
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'cache.dart';

Directory? _dir;

Future<Directory> _cacheDir() async {
  final cached = _dir;
  if (cached != null) return cached;
  final base = await getApplicationSupportDirectory();
  final dir = Directory('${base.path}/query_cache');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  _dir = dir;
  return dir;
}

Future<void> writeCache(String key, List<Map<String, dynamic>> rows) async {
  try {
    final dir = await _cacheDir();
    await File('${dir.path}/$key.json').writeAsString(
      jsonEncode({
        'saved_at': DateTime.now().toIso8601String(),
        'rows': rows,
      }),
    );
  } catch (_) {
    // Cache adalah optimasi: gagal menulis tidak boleh menggagalkan query.
  }
}

Future<CachedRows?> readCache(String key) async {
  try {
    final dir = await _cacheDir();
    final file = File('${dir.path}/$key.json');
    if (!file.existsSync()) return null;
    final raw = jsonDecode(await file.readAsString());
    if (raw is! Map) return null;
    final rows = (raw['rows'] as List?) ?? const [];
    return CachedRows(
      rows.map((r) => Map<String, dynamic>.from(r as Map)).toList(),
      DateTime.tryParse((raw['saved_at'] as String?) ?? '')?.toLocal() ?? DateTime.now(),
    );
  } catch (_) {
    return null;
  }
}

/// Buang seluruh cache (dipakai tombol "Kosongkan cache offline").
Future<int> clearCache() async {
  try {
    final dir = await _cacheDir();
    var n = 0;
    await for (final e in dir.list()) {
      if (e is File) {
        await e.delete();
        n++;
      }
    }
    return n;
  } catch (_) {
    return 0;
  }
}
