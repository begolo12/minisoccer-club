// Privasi data anggota — sisi klien.
//
// Dua hal yang diuji di sini:
//   1. Cache dibaca per role. Tanpa itu, hasil query yang dibaca admin
//      (lengkap dengan nomor HP) tersimpan di kunci yang sama dengan yang
//      dibaca tamu, dan tamu membacanya dari cache tanpa melewati
//      penyaringan server.
//   2. Scope cache ikut berubah saat role berubah.
import 'package:flutter_test/flutter_test.dart';

import 'package:minisoccer_club/core/cache.dart';
import 'package:minisoccer_club/core/db.dart';

void main() {
  test('kunci cache berbeda untuk role berbeda', () {
    const sql = 'SELECT * FROM members ORDER BY name';
    final params = <String, Object?>{};

    final tamu = cacheKey(sql, params, scope: 'public');
    final anggota = cacheKey(sql, params, scope: 'member');
    final admin = cacheKey(sql, params, scope: 'admin');

    expect(tamu, isNot(anggota),
        reason: 'tamu dan anggota tidak boleh berbagi cache');
    expect(anggota, isNot(admin));
    expect(tamu, isNot(admin));
  });

  test('kunci cache tetap sama untuk role yang sama', () {
    const sql = 'SELECT * FROM members ORDER BY name';
    expect(
      cacheKey(sql, const {}, scope: 'public'),
      cacheKey(sql, const {}, scope: 'public'),
    );
  });

  test('scope cache default = publik, dan bisa diganti role', () {
    // Default-nya publik: sebelum login, tidak ada yang boleh melihat
    // data yang lebih pribadi.
    expect(Db.cacheScope, 'public');
    Db.cacheScope = 'admin';
    expect(Db.cacheScope, 'admin');
    Db.cacheScope = 'public';
  });
}
