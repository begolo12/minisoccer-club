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

Future<void> writeCache(String key, List<Map<String, dynamic>> rows) async {
  try {
    web.window.localStorage.setItem(
      '$_prefix$key',
      jsonEncode({'saved_at': DateTime.now().toIso8601String(), 'rows': rows}),
    );
  } catch (_) {
    // Kuota penuh / mode privat: cache dilewati, query tetap jalan.
  }
}

Future<CachedRows?> readCache(String key) async {
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

Future<int> clearCache() async {
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
