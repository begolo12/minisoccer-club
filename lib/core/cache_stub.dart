/// Cache offline untuk web: localStorage.
///
/// Bertahan saat halaman dimuat ulang dan saat jaringan putus, sama seperti
/// berkas cache di Android. Batas localStorage ~5 MB, jadi entri juga dibatasi
/// seperti di Android (`cache_io.dart`): tanpa batas, pemakaian berbulan-bulan
/// menabrak kuota, penulisan cache gagal SENYAP, dan halaman terus menampilkan
/// data basi tanpa ada yang tahu.
library;

import 'dart:convert';

import 'package:web/web.dart' as web;

import 'cache.dart';

const _prefix = 'qcache:';

/// Batas cache di localStorage.
///
/// Jumlah berkas dibatasi lebih dulu karena pemindaian `listEntries` (dipakai
/// penambal offline) berjalan O(n) di tiap tulis. Batas karakter dipakai
/// sebagai pengaman kuota: localStorage menghitung UTF-16, dan 3 juta karakter
/// sudah menyisakan ruang untuk kunci serta data lain di origin yang sama.
const _maxEntries = 400;
const _maxChars = 3000000;

class LocalStorageCacheStore implements CacheStore {
  web.Storage get _store => web.window.localStorage;

  @override
  Future<void> writeEntry(CacheEntry entry) async {
    final key = '$_prefix${entry.key}';
    final value = jsonEncode({
      'sql': entry.sql,
      'params': entry.params,
      'saved_at': entry.savedAt.toIso8601String(),
      'rows': entry.rows,
    });
    try {
      _store.setItem(key, value);
    } catch (_) {
      // Kuota penuh / mode privat. Buang entri tertua lalu coba sekali lagi:
      // tanpa percobaan kedua, cache berhenti diperbarui selamanya dan
      // pengguna melihat data lama tanpa tanda apa pun.
      try {
        _evict(keep: key, target: 0);
        _store.setItem(key, value);
      } catch (_) {
        // Tetap gagal (mode privat): cache dilewati, query tetap jalan.
        return;
      }
    }
    try {
      _evict(keep: key);
    } catch (_) {
      // Pemangkasan adalah kenyamanan; kegagalannya tidak boleh menggagalkan
      // penyimpanan yang sudah berhasil.
    }
  }

  /// Buang entri tertua sampai jumlah dan ukuran di bawah batas.
  ///
  /// [keep] tidak pernah dibuang: itu entri yang baru saja ditulis.
  /// [target] menurunkan batas sementara (dipakai saat kuota sudah penuh).
  void _evict({required String keep, int? target}) {
    final keys = <String>[];
    for (var i = 0; i < _store.length; i++) {
      final k = _store.key(i);
      if (k != null && k.startsWith(_prefix)) keys.add(k);
    }

    final limitCount = target ?? _maxEntries;
    var totalChars = 0;
    for (final k in keys) {
      totalChars += k.length + (_store.getItem(k)?.length ?? 0);
    }
    if (keys.length <= limitCount && totalChars <= _maxChars) return;

    // Urutkan menurut `saved_at` yang tersimpan di dalam entri, bukan urutan
    // kunci: kunci adalah hash SQL+params, jadi tidak mencerminkan umur.
    final aged = <({String key, DateTime at, int size})>[];
    for (final k in keys) {
      if (k == keep) continue;
      final raw = _store.getItem(k);
      if (raw == null) continue;
      DateTime at;
      try {
        final decoded = jsonDecode(raw);
        at = DateTime.tryParse((decoded is Map ? decoded['saved_at'] : null) as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
      } catch (_) {
        // Entri rusak: paling layak dibuang lebih dulu.
        at = DateTime.fromMillisecondsSinceEpoch(0);
      }
      aged.add((key: k, at: at, size: k.length + raw.length));
    }
    aged.sort((a, b) => a.at.compareTo(b.at));

    var count = keys.length;
    for (final e in aged) {
      if (count <= limitCount && totalChars <= _maxChars) break;
      _store.removeItem(e.key);
      count--;
      totalChars -= e.size;
    }
  }

  @override
  Future<List<CacheEntry>> listEntries() async {
    final out = <CacheEntry>[];
    try {
      final store = _store;
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
      final raw = _store.getItem('$_prefix$key');
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
      final store = _store;
      final doomed = <String>[];
      for (var i = 0; i < store.length; i++) {
        final k = store.key(i);
        if (k != null && k.startsWith(_prefix)) doomed.add(k);
      }
      for (final k in doomed) {
        store.removeItem(k);
      }
      return doomed.length;
    } catch (_) {
      return 0;
    }
  }
}

CacheStore createCacheStore() => LocalStorageCacheStore();