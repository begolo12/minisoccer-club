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

  /// Id akun yang sedang masuk.
  ///
  /// Dipakai untuk mengenali baris "kamu" di daftar pengguna — jadi saat
  /// admin mengubah username-nya sendiri, baris itu ikut berubah.
  static int? userId;

  /// Id anggota yang tertaut dengan akun ini.
  ///
  /// Terisi hanya untuk akun anggota yang dibuat lewat pendaftaran (nama
  /// depan jadi username, akunnya tertaut ke baris anggota). Admin dan
  /// bendahara tidak punya tautan — mereka 관리 klub, bukan cumaplaying.
  ///
  /// Dipakai supaya role anggota bisa membuka "Akun saya" tanpa mencari
  /// namanya di daftar anggota.
  static int? memberId;

  /// Berubah saat login/logout — dipakai root untuk pindah layar.
  static final ValueNotifier<bool> session = ValueNotifier(false);

  static bool get signedIn => username != null;

  /// Tamu: belum masuk. Aplikasi tetap terbuka dalam mode baca-saja.
  static bool get isGuest => username == null;
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
    // Scope cache ikut role yang dipulihkan — cache lama dari role lain
    // tidak boleh dipakai (lihat `Db.cacheScope`).
    Db.cacheScope = r ?? 'signed-in';
    // Id anggota ikut dipulihkan: disimpan terpisah karena hanya sebagian
    // akun yang punya (anggota klub yang mendaftar sendiri).
    final m = await SecureStore.read('auth_member');
    memberId = m == null ? null : int.tryParse(m);
    // Id akun juga: dipakai untuk mengenali baris "kamu" di daftar pengguna.
    final uid = await SecureStore.read('auth_uid');
    userId = uid == null ? null : int.tryParse(uid);
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
    await _save(
      body['username'] as String,
      body['role'] as String?,
      body['token'] as String?,
      _memberIdOf(body),
      _intOf(body),
    );
  }

  /// Id anggota dari balasan server (null kalau akun ini bukan anggota).
  static int? _memberIdOf(Map<String, dynamic> body) {
    final v = body['member_id'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  /// Id akun dari balasan server.
  static int? _intOf(Map<String, dynamic> body) {
    final v = body['id'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  /// Buat admin pertama (hanya bisa saat belum ada user).
  static Future<void> register(String user, String pass, {String role = 'admin'}) async {
    final u = user.trim();
    if (u.isEmpty || pass.length < 6) throw Exception('Password minimal 6 karakter');
    final body = await _post(
      {'action': 'register', 'username': u, 'password': pass, 'role': role},
      auth: false,
    );
    await _save(
      body['username'] as String,
      body['role'] as String?,
      body['token'] as String?,
      _memberIdOf(body),
      _intOf(body),
    );
  }

  static Future<void> logout() async {
    username = null;
    role = null;
    token = null;
    memberId = null;
    userId = null;
    Db.authToken = null;
    Db.cacheScope = 'public';
    session.value = false;
    // Sama seperti saat login: cache role lama dibuang, supaya data yang
    // hanya boleh dilihat anggota (nomor HP) tidak tinggal di perangkat
    // setelah keluar.
    await Db.clearOfflineCache();
    await SecureStore.delete('auth_user');
    await SecureStore.delete('auth_role');
    await SecureStore.delete('auth_token');
    await SecureStore.delete('auth_member');
    await SecureStore.delete('auth_uid');
  }

  /// Dipanggil dari [Db] saat server menolak token: sesi dibuang tanpa
  /// menyentuh jaringan, lalu root kembali ke layar masuk.
  static Future<void> expire() async {
    if (username == null && token == null) return;
    await logout();
  }

  static Future<void> _save(
    String u,
    String? r,
    String? t, [
    int? member,
    int? userId,
  ]) async {
    username = u;
    role = r;
    token = t;
    memberId = member;
    Auth.userId = userId;
    Db.authToken = t;
    // Scope cache ikut role: admin melihat nomor HP dan alamat anggota,
    // anggota hanya nomor HP, tamu tidak. Cache tiap role terpisah, jadi
    // hasil yang dibaca admin tidak bisa dibaca tamu dari cache lokal.
    Db.cacheScope = r ?? 'signed-in';
    session.value = true;
    // Cache dibaca per role (lihat `Db.cacheScope`). Ganti role berarti isi
    // cache yang lama tidak boleh dipakai: kalau admin membaca daftar
    // anggota lengkap dengan nomor HP, lalu keluar, cache itu masih ada
    // dan mode publik bisa membacanya.
    await Db.clearOfflineCache();
    await SecureStore.write('auth_user', u);
    if (r != null) await SecureStore.write('auth_role', r);
    if (t != null) await SecureStore.write('auth_token', t);
    if (member != null) {
      await SecureStore.write('auth_member', '$member');
    } else {
      await SecureStore.delete('auth_member');
    }
    if (userId != null) {
      await SecureStore.write('auth_uid', '$userId');
    } else {
      await SecureStore.delete('auth_uid');
    }
  }

  /// Perbarui nama pengguna sesi di tempat.
  ///
  /// Dipakai setelah admin mengubah username-nya sendiri: tanpa ini, app
  /// masih menampilkan nama lama (dan "kamu" di daftar pengguna) sampai
  /// aplikasi ditutup — padahal server sudah menerima nama baru.
  static Future<void> renameSelf(String username) async {
    username = username.trim();
    if (username.isEmpty) return;
    await SecureStore.write('auth_user', username);
    Auth.username = username;
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

  // ---------- Pendaftaran anggota (publik) ----------

  /// Kirim formulir pendaftaran ke `/api/register`.
  ///
  /// Server membuat anggota DAN akunnya (nama depan jadi username), lalu
  /// mengembalikan username beserta password awalnya untuk ditampilkan sekali
  /// di layar berhasil.
  static Future<RegistrationResult> registerMember({
    required String name,
    required String phone,
    required String address,
    required String position,
  }) async {
    late final http.Response res;
    try {
      res = await http
          .post(
            Uri.parse('$kApiBase/api/register'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'name': name,
              'phone': phone,
              'address': address,
              'position': position,
            }),
          )
          .timeout(const Duration(seconds: 25));
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
        message is String && message.isNotEmpty
            ? message
            : 'Pendaftaran gagal (${res.statusCode})',
      );
    }
    return RegistrationResult(
      username: (map['username'] as String?) ?? '',
      password: (map['password'] as String?) ?? '',
      name: (map['name'] as String?) ?? name,
    );
  }

  /// Ganti password akun sendiri. Password lama diminta supaya token yang
  /// bocor tidak bisa dipakai mengunci pemilik akun.
  static Future<void> changePassword({
    required String current,
    required String next,
  }) =>
      _post({'action': 'change', 'current': current, 'next': next});

  // ---------- Kelola pengguna (admin) ----------

  static Future<void> createUser(String username, String role, String password) =>
      _post({'action': 'create', 'username': username.trim(), 'role': role, 'password': password});

  static Future<void> resetPassword(int id, String password) =>
      _post({'action': 'reset', 'id': id, 'password': password});

  static Future<void> deleteUser(int id) => _post({'action': 'delete', 'id': id});

  /// Daftar akun + status kredensial (admin).
  ///
  /// Mengembalikan baris apa adanya dari server supaya `AppUser.fromMap`
  /// memakai satu bentuk data yang sama untuk daftar dan hasil ubahan.
  static Future<List<Map<String, dynamic>>> listUsers() async {
    final body = await _post({'action': 'list'});
    final rows = body['users'];
    if (rows is! List) return const [];
    return [for (final r in rows) Map<String, dynamic>.from(r as Map)];
  }

  /// Nonaktifkan/aktifkan akun (admin). Untuk anggota yang keluar klub:
  /// riwayatnya tetap dipakai, jadi akunnya tidak perlu dihapus.
  static Future<void> setUserActive(int id, bool active) =>
      _post({'action': 'setActive', 'id': id, 'active': active});

  /// Ubah username dan/atau role (admin).
  ///
  /// Username anggota dibuat otomatis dari nama depan ("irvan", "irvan2"),
  /// jadi koreksi nama atau perbaikan role yang keliru perlu jalan ini —
  /// tanpa itu satu-satunya cara adalah hapus lalu buat ulang, dan menghapus
  /// akun anggota memutus tautannya ke baris anggota.
  static Future<void> updateUser(
    int id, {
    String? username,
    String? role,
    int? memberId,
    bool touchMember = false,
  }) =>
      _post({
        'action': 'update',
        'id': id,
        'username': ?username?.trim(),
        'role': ?role,
        if (touchMember) 'member_id': memberId,
      });
}

/// Hasil pendaftaran: username dan password awal yang harus ditunjukkan ke
/// pendaftar SEKALI, karena password tidak disimpan dalam bentuk terbaca.
class RegistrationResult {
  const RegistrationResult({
    required this.name,
    required this.username,
    required this.password,
  });

  final String name;
  final String username;
  final String password;
}
