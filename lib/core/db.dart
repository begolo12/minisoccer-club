import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'config.dart';
import 'db_io.dart' if (dart.library.js_interop) 'db_web.dart' as driver;

/// Akses DB dari UI. Driver dipilih saat compile:
/// - Android/desktop → koneksi TCP langsung ke Neon (`db_io.dart`)
/// - Web → Vercel Function `/api/sql` (`db_web.dart`)
class Db {
  static Future<String> resolveUrl() async {
    final saved = await SecureStore.read('neon_url');
    final url = (saved?.trim().isNotEmpty ?? false) ? saved!.trim() : kNeonUrlPlaceholder;
    if (url.contains('sslmode=')) return url;
    return '$url${url.contains('?') ? '&' : '?'}sslmode=require';
  }

  /// Web tidak butuh URL DB (server yang pegang kredensial).
  static bool get needsUrl => !driver.usesProxy;

  static Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, Object?> params = const {},
  }) async =>
      driver.query(sql, url: await resolveUrl(), params: params);

  static Future<int> execute(
    String sql, {
    Map<String, Object?> params = const {},
  }) async =>
      driver.execute(sql, url: await resolveUrl(), params: params);

  static Future<void> close() => driver.close();
}

/// Wrapper secure storage sederhana biar import-nya di satu tempat.
/// Web: aman-aman saja, nilainya cuma dipakai untuk preferensi.
class SecureStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static Future<String?> read(String key) => _storage.read(key: key);
  static Future<void> write(String key, String value) => _storage.write(key: key, value: value);
  static Future<void> delete(String key) => _storage.delete(key: key);
}
