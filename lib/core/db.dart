import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'config.dart';
import 'db_io.dart' if (dart.library.js_interop) 'db_web.dart' as driver;

/// Akses DB dari UI. Driver dipilih saat compile:
/// - Android/desktop → TCP langsung ke Neon (`db_io.dart`)
/// - Web → Vercel Function `/api/sql` (`db_web.dart`)
class Db {
  static String? _url;

  /// Web tidak perlu URL: kredensial dipegang server.
  static bool get needsUrl => !driver.usesProxy;

  static Future<String> resolveUrl() async {
    final cached = _url;
    if (cached != null) return cached;
    final saved = await SecureStore.read('neon_url');
    final url = (saved?.trim().isNotEmpty ?? false) ? saved!.trim() : kNeonUrlPlaceholder;
    return _url = url.contains('sslmode=') ? url : '$url${url.contains('?') ? '&' : '?'}sslmode=require';
  }

  static Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, Object?> params = const {},
  }) async =>
      driver.query(sql, url: needsUrl ? await resolveUrl() : '', params: params);

  static Future<int> execute(
    String sql, {
    Map<String, Object?> params = const {},
  }) async =>
      driver.execute(sql, url: needsUrl ? await resolveUrl() : '', params: params);

  static Future<void> close() async {
    _url = null;
    await driver.close();
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
