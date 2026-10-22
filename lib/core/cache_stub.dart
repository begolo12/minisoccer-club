/// Cache offline untuk web: localStorage.
///
/// Bertahan saat halaman dimuat ulang dan saat jaringan putus, sama seperti
/// berkas cache di Android. Batas localStorage ~5 MB; data klub jauh di bawah
/// itu, tapi penulisan tetap dibungkus try/catch supaya kuota penuh tidak
/// menggagalkan query.
library;

import 'dart:convert';

import 'package:web/web.dart' as web;

import 'cache.dart';

const _prefix = 'qcache:';

class LocalStorageCacheStore implements CacheStore {
  @override
  Future<void> writeEntry(CacheEntry entry) async {
    try {
      web.window.localStorage.setItem(
        '$_prefix${entry.key}',
        jsonEncode({
          'sql': entry.sql,
          'params': entry.params,
          'saved_at': entry.savedAt.toIso8601String(),
          'rows': entry.rows,
        }),
      );
    } catch (_) {
      // Kuota penuh / mode privat: cache dilewati, query tetap jalan.
    }
  }

  @override
  Future<List<CacheEntry>> listEntries() async {
    final out = <CacheEntry>[];
    try {
      final store = web.window.localStorage;
      for (var i = 0; i < store.length; i++) {
        final k = store.key(i);
        if (k == null || !k.startsWith(_prefix)) continue;
        try {
          final decoded = jsonDecode(store.getItem(k) ?? '');
          if (decoded is! Map) continue;
          final sql = decoded['sql'];
          if (sql is! String || sql.isEmpty) continue;
          final rows = (decoded['rows'] as List?) ?? const [];
          out.add(CacheEntry(
            key: k.substring(_prefix.length),
            sql: sql,
            params: (decoded['params'] as Map?)?.cast<String, Object?>() ?? const {},
            rows: rows.map((r) => Map<String, dynamic>.from(r as Map)).toList(),
            savedAt:
                DateTime.tryParse((decoded['saved_at'] as String?) ?? '')?.toLocal() ??
                    DateTime.now(),
          ));
        } catch (_) {
          // Satu entri rusak tidak boleh menggagalkan penambalan entri lain.
        }
      }
    } catch (_) {
      // localStorage tidak tersedia (mode privat).
    }
    return out;
  }

  @override
  Future<CachedRows?> readRows(String key) async {
    try {
      final raw = web.window.localStorage.getItem('$_prefix$key');
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final rows = (decoded['rows'] as List?) ?? const [];
      return CachedRows(
        rows.map((r) => Map<String, dynamic>.from(r as Map)).toList(),
        DateTime.tryParse((decoded['saved_at'] as String?) ?? '')?.toLocal() ?? DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<int> clear() async {
    try {
      final store = web.window.localStorage;
      final keys = <String>[];
      for (var i = 0; i < store.length; i++) {
        final k = store.key(i);
        if (k != null && k.startsWith(_prefix)) keys.add(k);
      }
      for (final k in keys) {
        store.removeItem(k);
      }
      return keys.length;
    } catch (_) {
      return 0;
    }
  }
}

CacheStore createCacheStore() => LocalStorageCacheStore();
