import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/db.dart';

/// Login/logout + simpan sesi.
///
/// - Web  → POST /api/auth (server pegang kredensial DB), dapat token HMAC.
/// - HP   → cek langsung ke Postgres pakai `crypt()` dari pgcrypto.
///   Perangkat dipercaya (connection string tersimpan terenkripsi di HP).
class Auth {
  static String? username;
  static String? role;
  static String? token;

  /// Berubah saat login/logout — dipakai root untuk pindah layar.
  static final ValueNotifier<bool> session = ValueNotifier(false);

  static bool get signedIn => username != null;
  static bool get isAdmin => role == 'admin';

  static const _endpoint = String.fromEnvironment('API_URL', defaultValue: '/api/auth');

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
    final rows = await Db.query('SELECT count(*)::int AS n FROM users');
    return (rows.first['n'] as int) == 0;
  }

  static Future<void> login(String user, String pass) async {
    final u = user.trim();
    if (u.isEmpty || pass.isEmpty) throw Exception('Username dan password wajib diisi');

    if (Db.needsUrl) {
      // HP: verifikasi langsung di Postgres (bcrypt oleh pgcrypto).
      final rows = await Db.query(
        '''SELECT username, role FROM users
           WHERE username=@u AND active AND password_hash IS NOT NULL
             AND password_hash = crypt(@p, password_hash)''',
        params: {'u': u, 'p': pass},
      );
      if (rows.isEmpty) throw Exception('Username atau password salah');
      await _save(rows.first['username'] as String, rows.first['role'] as String?, null);
      return;
    }

    final res = await http.post(
      Uri.parse(_endpoint),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'action': 'login', 'username': u, 'password': pass}),
    );
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) throw Exception(body['error'] ?? 'Gagal login');
    await _save(body['username'] as String, body['role'] as String?, body['token'] as String?);
  }

  /// Buat admin pertama (hanya bisa saat belum ada user).
  static Future<void> register(String user, String pass, {String role = 'admin'}) async {
    final u = user.trim();
    if (u.isEmpty || pass.length < 6) throw Exception('Password minimal 6 karakter');

    if (Db.needsUrl) {
      if (!await needsBootstrap()) throw Exception('Sudah ada user. Tambah lewat menu Pengguna.');
      await Db.execute(
        '''INSERT INTO users (username, role, password_hash)
           VALUES (@u, @r, crypt(@p, gen_salt('bf', 10)))''',
        params: {'u': u, 'r': role, 'p': pass},
      );
      await login(u, pass);
      return;
    }

    final res = await http.post(
      Uri.parse(_endpoint),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'action': 'register', 'username': u, 'password': pass, 'role': role}),
    );
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) throw Exception(body['error'] ?? 'Gagal daftar');
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
}
