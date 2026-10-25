// Bentuk baris dari server → model.
//
// Bug yang ditutup di sini (ditemukan dari layar "Lainnya" di HP):
// server pernah mengirim kolom tanggal sebagai `{}` — penyaring privasi
// membangun ulang objek `Date` menjadi objek kosong. `DateTime.parse('{}')`
// melempar FormatException, dan karena satu kolom itu, SELURUH daftar
// anggota gagal dimuat: halaman menampilkan "Anggota: FormatException:
// Invalid date format" dan "0 aktif" padahal anggotanya ada.
//
// Dua lapis yang diuji:
//   1. Server: scrubRows tidak merusak Date (lihat api/_privacy.test.mjs).
//   2. Klien: nilai tanggal yang rusak tidak menggagalkan barisnya.
import 'package:flutter_test/flutter_test.dart';

import 'package:minisoccer_club/data/models.dart';

void main() {
  test('tanggal rusak tidak menggagalkan anggota', () {
    final m = Member.fromMap({
      'id': 1,
      'name': 'Irvan',
      'position': 'Bek',
      'active': true,
      'joined_at': <String, dynamic>{}, // bentuk yang dulu dikirim server
    });
    expect(m.name, 'Irvan');
    expect(m.joinedAt.year, 1970);
  });

  test('tanggal ISO dari server dibaca sebagai waktu lokal', () {
    final m = Member.fromMap({
      'id': 2,
      'name': 'Urip',
      'position': 'Gelandang',
      'active': true,
      'joined_at': '2026-10-23T11:34:38.419Z',
    });
    expect(m.joinedAt.toUtc(), DateTime.utc(2026, 10, 23, 11, 34, 38, 419));
  });

  test('akun: id, tautan anggota, dan status password ikut terbaca', () {
    final u = AppUser.fromMap({
      'id': 7,
      'username': 'urip',
      'role': 'member',
      'active': true,
      'member_id': 444,
      'created_at': '2026-10-23T11:34:38.470Z',
      'has_password': true,
    });
    expect(u.id, 7);
    expect(u.memberId, 444);
    expect(u.hasPassword, isTrue);
    expect(u.createdAt!.toUtc(), DateTime.utc(2026, 10, 23, 11, 34, 38, 470));
  });

  test('akun tanpa password ditandai, bukan dianggap punya', () {
    final u = AppUser.fromMap({
      'id': 8,
      'username': 'baru',
      'role': 'member',
      'active': true,
      'member_id': null,
      'created_at': null,
      'has_password': false,
    });
    expect(u.hasPassword, isFalse);
    expect(u.memberId, isNull);
    expect(u.createdAt, isNull);
  });
}
