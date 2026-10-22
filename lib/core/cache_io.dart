/// Cache offline untuk platform dengan `dart:io` (Android, desktop).
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'cache.dart';

class FileCacheStore implements CacheStore {
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

  /// Simpan satu entri. `sql` dan `params` ikut ditulis: penambal offline butuh
  /// tahu query asalnya untuk menentukan baris mana yang harus diubah.
  @override
  Future<void> writeEntry(CacheEntry entry) async {
    try {
      final dir = await _cacheDir();
      await File('${dir.path}/${entry.key}.json').writeAsString(
        jsonEncode({
          'sql': entry.sql,
          'params': entry.params,
          'saved_at': entry.savedAt.toIso8601String(),
          'rows': entry.rows,
        }),
      );
    } catch (_) {
      // Cache adalah optimasi: gagal menulis tidak boleh menggagalkan query.
    }
  }

  /// Semua entri cache. Entri lama (tanpa `sql`) dilewati karena tidak bisa
  /// ditambal — lebih baik hilang dari cache daripada menampilkan data basi.
  @override
  Future<List<CacheEntry>> listEntries() async {
    final out = <CacheEntry>[];
    try {
      final dir = await _cacheDir();
      await for (final e in dir.list()) {
        if (e is! File) continue;
        try {
          final raw = jsonDecode(await e.readAsString());
          if (raw is! Map) continue;
          final sql = raw['sql'];
          if (sql is! String || sql.isEmpty) continue;
          final rows = (raw['rows'] as List?) ?? const [];
          out.add(CacheEntry(
            key: e.uri.pathSegments.last.replaceAll('.json', ''),
            sql: sql,
            params: (raw['params'] as Map?)?.cast<String, Object?>() ?? const {},
            rows: rows.map((r) => Map<String, dynamic>.from(r as Map)).toList(),
            savedAt: DateTime.tryParse((raw['saved_at'] as String?) ?? '')?.toLocal() ??
                DateTime.now(),
          ));
        } catch (_) {
          // Satu berkas rusak tidak boleh menggagalkan penambalan entri lain.
        }
      }
    } catch (_) {
      // Direktori belum ada / tidak bisa dibaca.
    }
    return out;
  }

  @override
  Future<CachedRows?> readRows(String key) async {
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
  @override
  Future<int> clear() async {
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
}

CacheStore createCacheStore() => FileCacheStore();
