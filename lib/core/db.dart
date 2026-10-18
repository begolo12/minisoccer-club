import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'db_web.dart' as driver;

/// Dilempar driver saat token ditolak server (sesi habis).
class Unauthorized implements Exception {
  @override
  String toString() => 'Sesi habis, silakan login ulang';
}

/// Akses DB dari UI. Semua platform lewat `/api/sql` (Vercel Function),
/// jadi tidak ada kredensial Postgres di HP maupun browser.
class Db {
  /// Token sesi (diisi `Auth` setelah login).
  static String? authToken;

  /// Dipanggil sekali saat server menolak token. Root memakainya untuk
  /// kembali ke layar masuk, jadi user tidak melihat error di tiap halaman.
  static Future<void> Function()? onSessionExpired;

  /// Naik setiap tulis berhasil. Halaman yang dibuka lagi setelah angka ini
  /// berubah memuat ulang datanya, jadi tab lain tidak menampilkan data basi.
  static final ValueNotifier<int> writes = ValueNotifier(0);

  static Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, Object?> params = const {},
  }) async {
    try {
      final rows = await driver.query(sql, params: params);
      // INSERT/UPDATE/DELETE ... RETURNING juga lewat query.
      if (_isWrite(sql)) writes.value++;
      return rows;
    } on Unauthorized {
      await _expire();
      rethrow;
    }
  }

  static Future<int> execute(
    String sql, {
    Map<String, Object?> params = const {},
  }) async {
    try {
      final n = await driver.execute(sql, params: params);
      if (_isWrite(sql)) writes.value++;
      return n;
    } on Unauthorized {
      await _expire();
      rethrow;
    }
  }

  static bool _isWrite(String sql) {
    final head = sql.trimLeft().toUpperCase();
    return head.startsWith('INSERT') || head.startsWith('UPDATE') || head.startsWith('DELETE');
  }

  static Future<void> _expire() async {
    final handler = onSessionExpired;
    if (handler != null) await handler();
  }

  static Future<void> close() async => driver.close();
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
