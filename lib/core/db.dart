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

  static Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, Object?> params = const {},
  }) =>
      driver.query(sql, params: params);

  static Future<int> execute(
    String sql, {
    Map<String, Object?> params = const {},
  }) =>
      driver.execute(sql, params: params);

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
