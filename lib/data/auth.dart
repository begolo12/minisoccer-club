import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/api.dart';
import '../core/db.dart';
import '../core/db_web.dart' show ApiException;

/// Login/logout + simpan sesi.
///
/// Semua platform memakai `POST /api/auth`: password dicek bcrypt oleh
/// Postgres di server, klien hanya menerima token HMAC (berlaku 12 jam).
class Auth {
  static String? username;
  static String? role;
  static String? token;

  /// Berubah saat login/logout — dipakai root untuk pindah layar.
  static final ValueNotifier<bool> session = ValueNotifier(false);

  static bool get signedIn => username != null;
  static bool get isAdmin => role == 'admin';

  /// Admin dan bendahara boleh menulis data klub; member hanya membaca.
  static bool get canWrite => role == 'admin' || role == 'treasurer';

  /// Pulihkan sesi tersimpan saat app dibuka.
  static Future<void> restore() async {
    final u = await SecureStore.read('auth_user');
    final t = await SecureStore.read('auth_token');
    final r = await SecureStore.read('auth_role');
    if (u == null || u.isEmpty) return;
    username = u;
    role = r;
    token = t;
    Db.authToken = t;
    session.value = true;
  }

  /// Apakah belum ada user sama sekali? (perlu buat admin pertama)
  static Future<bool> needsBootstrap() async {
    final body = await _post({'action': 'status'}, auth: false);
    return body['bootstrap'] == true;
  }

  static Future<void> login(String user, String pass) async {
    final u = user.trim();
    if (u.isEmpty || pass.isEmpty) throw Exception('Username dan password wajib diisi');
    final body = await _post({'action': 'login', 'username': u, 'password': pass}, auth: false);
    await _save(body['username'] as String, body['role'] as String?, body['token'] as String?);
  }

  /// Buat admin pertama (hanya bisa saat belum ada user).
  static Future<void> register(String user, String pass, {String role = 'admin'}) async {
    final u = user.trim();
    if (u.isEmpty || pass.length < 6) throw Exception('Password minimal 6 karakter');
    final body = await _post(
      {'action': 'register', 'username': u, 'password': pass, 'role': role},
      auth: false,
    );
    await _save(body['username'] as String, body['role'] as String?, body['token'] as String?);
  }

  static Future<void> logout() async {
    username = null;
    role = null;
    token = null;
    Db.authToken = null;
    session.value = false;
    await SecureStore.delete('auth_user');
    await SecureStore.delete('auth_role');
    await SecureStore.delete('auth_token');
  }

  /// Dipanggil dari [Db] saat server menolak token: sesi dibuang tanpa
  /// menyentuh jaringan, lalu root kembali ke layar masuk.
  static Future<void> expire() async {
    if (username == null && token == null) return;
    await logout();
  }

  static Future<void> _save(String u, String? r, String? t) async {
    username = u;
    role = r;
    token = t;
    Db.authToken = t;
    session.value = true;
    await SecureStore.write('auth_user', u);
    if (r != null) await SecureStore.write('auth_role', r);
    if (t != null) await SecureStore.write('auth_token', t);
  }

  static Future<Map<String, dynamic>> _post(
    Map<String, Object?> body, {
    bool auth = true,
  }) async {
    late final http.Response res;
    try {
      res = await http
          .post(
            Uri.parse(kAuthEndpoint),
            headers: {
              'content-type': 'application/json',
              if (auth && token != null) 'authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw ApiException('Server tidak merespons. Periksa koneksi lalu coba lagi.');
    } on http.ClientException {
      throw ApiException('Tidak bisa menghubungi server. Periksa koneksi internet.');
    }

    dynamic data;
    try {
      data = jsonDecode(res.body);
    } catch (_) {
      data = null;
    }
    final map = data is Map<String, dynamic> ? data : <String, dynamic>{};
    if (res.statusCode != 200) {
      final message = map['error'];
      throw ApiException(
        message is String && message.isNotEmpty ? message : 'Permintaan gagal (${res.statusCode})',
      );
    }
    return map;
  }

  // ---------- Kelola pengguna (admin) ----------

  static Future<void> createUser(String username, String role, String password) =>
      _post({'action': 'create', 'username': username.trim(), 'role': role, 'password': password});

  static Future<void> resetPassword(int id, String password) =>
      _post({'action': 'reset', 'id': id, 'password': password});

  static Future<void> deleteUser(int id) => _post({'action': 'delete', 'id': id});
}
