// Privasi data anggota.
//
// Bug yang ditutup tes ini: mode publik (tamu tanpa login) bisa membaca
// nomor HP dan alamat tinggal SEMUA anggota lewat satu permintaan
// `SELECT * FROM members`. Daftarnya memang terlihat (nama, posisi, nomor
// punggung — itu bagian dari data klub), tapi nomor HP dan alamat adalah
// data pribadi yang tidak perlu terlihat orang luar.
//
// Dua lapis, karena satu lapis bisa dilewati:
//   1. Guard: query yang MENYEBUT kolom sensitif ditolak.
//   2. Saringan hasil: `SELECT *` / `m.*` / `row_to_json(m)` tidak menyebut
//      kolomnya, jadi hasilnya dibuang kunci sensitifnya.
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { rejectSql } from './_guard.js';
import { hiddenColumns, mentionsHidden, scrubRows } from './_privacy.js';

const guest = { r: 'public' };
const member = { r: 'member' };
const treasurer = { r: 'treasurer' };
const admin = { r: 'admin' };

test('tamu tidak boleh menyebut kolom data pribadi', () => {
  assert.notEqual(rejectSql('SELECT name, phone FROM members', guest), null);
  assert.notEqual(rejectSql('SELECT * FROM members WHERE phone LIKE \'08%\'', guest), null);
  assert.notEqual(rejectSql('SELECT count(phone) AS n FROM members', guest), null);
  assert.notEqual(rejectSql('SELECT md5(phone) FROM members', guest), null);
  assert.notEqual(rejectSql('SELECT address FROM members', guest), null);
  // Alias tidak menolong: yang dicari adalah kata kuncinya.
  assert.notEqual(rejectSql('SELECT phone AS hp FROM members', guest), null);
  // WHERE juga.
  assert.notEqual(rejectSql('SELECT * FROM members WHERE address = \'x\'', guest), null);
});

test('SELECT * dan m.* lolos guard, tapi isinya disaring', () => {
  // `m.*` tidak menyebut nama kolomnya, jadi guard tidak bisa menolaknya.
  // Lapis kedua (saringan hasil) yang menutupnya — lihat tes scrubRows.
  assert.equal(rejectSql('SELECT m.* FROM members m', guest), null);
  const rows = [{ id: 1, name: 'Budi', phone: '0812', address: 'Jl. Mawar' }];
  const scrubbed = scrubRows(rows, hiddenColumns('public'));
  assert.equal(scrubbed[0].phone, undefined);
  assert.equal(scrubbed[0].address, undefined);
});

test('anggota boleh melihat nomor HP tapi bukan alamat', () => {
  assert.equal(rejectSql('SELECT name, phone FROM members', member), null);
  assert.notEqual(rejectSql('SELECT address FROM members', member), null);
  assert.notEqual(rejectSql('SELECT * FROM members WHERE address = \'x\'', member), null);
});

test('admin dan bendahara boleh melihat semuanya', () => {
  assert.equal(rejectSql('SELECT name, phone, address FROM members', admin), null);
  assert.equal(rejectSql('SELECT name, phone, address FROM members', treasurer), null);
});

test('kolom biasa tetap boleh untuk semua role', () => {
  for (const role of [guest, member, treasurer, admin]) {
    assert.equal(rejectSql('SELECT id, name, position, jersey FROM members', role), null);
    assert.equal(rejectSql('SELECT * FROM members', role), null,
      'SELECT * sendiri boleh — yang_closed adalah isinya (lihat scrubRows)');
  }
});

test('saringan hasil membuang kunci sensitif', () => {
  const rows = [
    { id: 1, name: 'Budi', phone: '0812', address: 'Jl. Mawar', position: 'Bek' },
  ];
  const scrubbed = scrubRows(rows, hiddenColumns('public'));
  assert.equal(scrubbed[0].phone, undefined);
  assert.equal(scrubbed[0].address, undefined);
  assert.equal(scrubbed[0].name, 'Budi');
  assert.equal(scrubbed[0].position, 'Bek');
});

test('saringan hasil membuang address untuk anggota, phone tetap ada', () => {
  const rows = [{ id: 1, name: 'Budi', phone: '0812', address: 'Jl. Mawar' }];
  const scrubbed = scrubRows(rows, hiddenColumns('member'));
  assert.equal(scrubbed[0].address, undefined);
  assert.equal(scrubbed[0].phone, '0812');
});

test('saringan hasil menyaring objek di dalam array (json_agg)', () => {
  const rows = [{ items: [{ name: 'Budi', phone: '0812', address: 'Jl. Mawar' }] }];
  const scrubbed = scrubRows(rows, hiddenColumns('public'));
  assert.equal(scrubbed[0].items[0].phone, undefined);
  assert.equal(scrubbed[0].items[0].address, undefined);
  assert.equal(scrubbed[0].items[0].name, 'Budi');
});

test('saringan result menyaring JSON di dalam string (row_to_json)', () => {
  const rows = [{ j: '{"id":1,"name":"Budi","phone":"0812","address":"Jl. Mawar"}' }];
  const scrubbed = scrubRows(rows, hiddenColumns('public'));
  const parsed = JSON.parse(scrubbed[0].j);
  assert.equal(parsed.phone, undefined);
  assert.equal(parsed.address, undefined);
  assert.equal(parsed.name, 'Budi');
});

test('admin dan bendahara: hasil tidak disaring', () => {
  const rows = [{ id: 1, name: 'Budi', phone: '0812', address: 'Jl. Mawar' }];
  assert.equal(scrubRows(rows, hiddenColumns('admin'))[0].phone, '0812');
  assert.equal(scrubRows(rows, hiddenColumns('treasurer'))[0].address, 'Jl. Mawar');
});

test('penyebutan kolom recognizes alias dan quoted identifier', () => {
  assert.equal(mentionsHidden('SELECT m.phone FROM members m', ['phone']), true);
  assert.equal(mentionsHidden('SELECT "phone" FROM members', ['phone']), true);
  assert.equal(mentionsHidden('SELECT PHONE FROM members', ['phone']), true);
  assert.equal(mentionsHidden('SELECT name FROM members', ['phone']), false);
  // `telepon` bukan `phone` — kolom itu memang tidak ada di tabel.
  assert.equal(mentionsHidden('SELECT telepon FROM members', ['phone']), false);
});
