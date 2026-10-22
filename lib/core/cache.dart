/// Cache hasil query untuk mode offline.
///
/// Setiap pembacaan yang berhasil disimpan per kunci `sql + params`. Saat
/// jaringan mati, pembacaan yang sama dikembalikan dari cache sehingga app
/// masih bisa dibuka dan dibaca — hanya tidak bisa menulis.
///
/// Berkas ini hanya berisi kontrak; implementasi platform ada di
/// `cache_io.dart` (Android/desktop, file JSON) dan `cache_stub.dart` (web,
/// memori saja).
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Satu entri cache: baris + waktu penyimpanan.
class CachedRows {
  const CachedRows(this.rows, this.savedAt);

  final List<Map<String, dynamic>> rows;
  final DateTime savedAt;
}

/// Kunci cache: hash isi query, bukan SQL mentah (nama kolom panjang bisa
/// melebihi batas nama berkas).
String cacheKey(String sql, Map<String, Object?> params) {
  final canonical = jsonEncode({
    'sql': sql.trim().replaceAll(RegExp(r'\s+'), ' '),
    'params': {
      for (final k in params.keys.toList()..sort())
        k: params[k] is DateTime
            ? (params[k] as DateTime).toUtc().toIso8601String()
            : params[k],
    },
  });
  return sha256.convert(utf8.encode(canonical)).toString().substring(0, 32);
}
