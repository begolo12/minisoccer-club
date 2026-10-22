import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'cache.dart';
import 'cache_stub.dart' if (dart.library.io) 'cache_io.dart';
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

  /// True sejak satu pembacaan jatuh ke cache. Halaman menampilkan banner
  /// "mode offline" selama ini menyala, supaya angka yang terlihat tidak
  /// disangka data terbaru.
  static final ValueNotifier<bool> offline = ValueNotifier(false);

  /// Waktu data cache terakhir dipakai (untuk label banner).
  static DateTime? offlineSince;

  /// Pembacaan yang gagal karena jaringan dikembalikan dari cache. Tulis
  /// tidak pernah di-cache: menulis saat offline akan tampak berhasil padahal
  /// tidak tersimpan di server.
  static Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, Object?> params = const {},
  }) async {
    final key = cacheKey(sql, params);
    try {
      final rows = await driver.query(sql, params: params);
      // INSERT/UPDATE/DELETE ... RETURNING juga lewat query.
      if (_isWrite(sql)) {
        writes.value++;
      } else {
        await writeCache(key, rows);
      }
      if (offline.value) {
        offline.value = false;
        offlineSince = null;
      }
      return rows;
    } on Unauthorized {
      await _expire();
      rethrow;
    } catch (e) {
      // Hanya kegagalan jaringan/ server yang jatuh ke cache; query yang
      // ditolak (400/403) adalah bug atau izin, bukan alasan menampilkan data
      // lama yang mungkin sudah tidak sah.
      if (!_isNetworkFailure(e)) rethrow;
      final hit = await readCache(key);
      if (hit == null) rethrow;
      offline.value = true;
      offlineSince = hit.savedAt;
      return hit.rows;
    }
  }

  /// Kegagalan yang pantas ditutup cache: server tidak terjangkau atau
  /// timeout. `ApiException` dari server (mis. "Query gagal dijalankan")
  /// tidak termasuk — itu jawaban, bukan gangguan jaringan.
  static bool _isNetworkFailure(Object e) {
    if (e is Unauthorized) return false;
    final msg = e.toString();
    return msg.contains('Tidak bisa menghubungi server') ||
        msg.contains('Server tidak merespons') ||
        msg.contains('SocketException') ||
        msg.contains('Failed host lookup') ||
        msg.contains('Connection refused') ||
        msg.contains('ClientException');
  }

  /// Kosongkan cache offline (dipakai Pengaturan).
  static Future<int> clearOfflineCache() async {
    offline.value = false;
    offlineSince = null;
    return clearCache();
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

  /// Nilai yang tidak bisa didekripsi (storage rusak, kunci berubah, atau
  /// sisa versi lama) dibuang supaya app tidak gagal start dengan layar kosong.
  static Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      try {
        await _storage.delete(key: key);
      } catch (_) {}
      return null;
    }
  }

  static Future<void> write(String key, String value) => _storage.write(key: key, value: value);
  static Future<void> delete(String key) => _storage.delete(key: key);
}
