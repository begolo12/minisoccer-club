/// Cache hasil query + antrean tulis untuk mode offline.
///
/// Model offline-first:
///   * **Baca** — setiap pembacaan yang berhasil disimpan per kunci
///     `sql + params`. Saat jaringan mati, pembacaan yang sama dikembalikan
///     dari cache.
///   * **Tulis** — saat jaringan mati, tulis masuk antrean (`offline.dart`),
///     lalu cache di atas **ditambal** supaya hasilnya langsung terlihat
///     (`row_patch.dart`). Saat online, antrean dikirim ulang dan menimpa
///     data cloud — data lokal yang diutamakan.
///
/// Karena penambalan butuh tahu query apa yang tersimpan, entri cache
/// menyimpan `sql` dan `params` aslinya, bukan hanya hash kuncinya.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Satu entri cache: query asal, baris hasil, dan waktu penyimpanan.
class CacheEntry {
  const CacheEntry({
    required this.key,
    required this.sql,
    required this.params,
    required this.rows,
    required this.savedAt,
  });

  final String key;
  final String sql;
  final Map<String, Object?> params;
  final List<Map<String, dynamic>> rows;
  final DateTime savedAt;

  CacheEntry copyWith({List<Map<String, dynamic>>? rows}) => CacheEntry(
        key: key,
        sql: sql,
        params: params,
        rows: rows ?? this.rows,
        savedAt: savedAt,
      );
}

/// Hasil pembacaan cache.
class CachedRows {
  const CachedRows(this.rows, this.savedAt);

  final List<Map<String, dynamic>> rows;
  final DateTime savedAt;
}

/// Kunci cache: hash isi query, bukan SQL mentah (nama kolom panjang bisa
/// melebihi batas nama berkas).
///
/// [scope] membedakan cache per role. Tanpa itu, hasil query yang dibaca
/// admin (yang boleh melihat nomor HP anggota) tersimpan di kunci yang sama
/// dengan yang dibaca tamu — dan tamu bisa membacanya dari cache, melewati
/// penyaringan privasi di server. Scope membuat tiap role punya salinannya
/// sendiri.
String cacheKey(String sql, Map<String, Object?> params, {String scope = ''}) {
  final canonical = jsonEncode({
    'sql': sql.trim().replaceAll(RegExp(r'\s+'), ' '),
    'scope': scope,
    'params': {
      for (final k in params.keys.toList()..sort())
        k: params[k] is DateTime
            ? (params[k] as DateTime).toUtc().toIso8601String()
            : params[k],
    },
  });
  return sha256.convert(utf8.encode(canonical)).toString().substring(0, 32);
}

/// Penyimpanan cache. Implementasi per platform ada di `cache_io.dart`
/// (Android/desktop) dan `cache_stub.dart` (web); tes memakai versi memori.
abstract interface class CacheStore {
  Future<void> writeEntry(CacheEntry entry);
  Future<List<CacheEntry>> listEntries();
  Future<CachedRows?> readRows(String key);
  Future<int> clear();
}
