import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:postgres/postgres.dart';
import 'config.dart';

/// Satu koneksi Neon per app lifecycle (lazy).
/// ponytail: single shared connection — cukup untuk klub kecil (<10 user).
/// Kalau nanti butuh request paralel tinggi, ganti ke Pool.
class Db {
  static Connection? _conn;
  static Completer<Connection>? _connecting;

  static Future<Connection> get instance async {
    if (_conn != null) return _conn!;
    if (_connecting != null) return _connecting!.future;

    final completer = Completer<Connection>();
    _connecting = completer;
    try {
      final url = await resolveUrl();
      final c = await Connection.openFromUrl(url);
      _conn = c;
      completer.complete(c);
      return c;
    } catch (e, st) {
      _connecting = null;
      completer.completeError(e, st);
      rethrow;
    }
  }

  /// URL terbaik: setting lokal user > dart-define > placeholder.
  static Future<String> resolveUrl() async {
    final saved = await SecureStore.read('neon_url');
    final url = (saved?.trim().isNotEmpty ?? false) ? saved!.trim() : kNeonUrlPlaceholder;
    if (url.contains('sslmode=')) return url;
    return '$url${url.contains('?') ? '&' : '?'}sslmode=require';
  }

  static Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, Object?> params = const {},
  }) async {
    final c = await instance;
    final result = await c.execute(Sql.named(sql), parameters: params);
    return result.map((r) => r.toColumnMap()).toList();
  }

  static Future<int> execute(
    String sql, {
    Map<String, Object?> params = const {},
  }) async {
    final c = await instance;
    final result = await c.execute(Sql.named(sql), parameters: params);
    return result.affectedRows;
  }

  /// Jalankan skrip DDL multi-statement (mis. db/schema.sql).
  /// Protokol simple: satu round-trip, aman untuk beberapa perintah sekaligus.
  static Future<void> executeScript(String sql) async {
    final c = await instance;
    await c.execute(sql, ignoreRows: true);
  }

  static Future<void> close() async {
    try {
      await _conn?.close();
    } finally {
      _conn = null;
      _connecting = null;
    }
  }
}

/// Wrapper secure storage sederhana biar import-nya di satu tempat.
class SecureStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static Future<String?> read(String key) => _storage.read(key: key);
  static Future<void> write(String key, String value) => _storage.write(key: key, value: value);
  static Future<void> delete(String key) => _storage.delete(key: key);
}
