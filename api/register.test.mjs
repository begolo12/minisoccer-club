import test from 'node:test';
import assert from 'node:assert/strict';

import {
  cleanName,
  cleanPhone,
  usernameBase,
  usernameCandidate,
  validateRegistration,
} from './register.js';

// Aturan formulir pendaftaran. Yang diuji di sini adalah bagian yang menentukan
// apakah data masuk ke database, jadi kasus tepinya harus dijaga: nomor HP
// dengan format berbeda, nama yang terlalu pendek, dan posisi di luar daftar.

test('nomor HP dari berbagai penulisan menjadi satu bentuk baku', () => {
  assert.equal(cleanPhone('0812-3456-7890'), '081234567890');
  assert.equal(cleanPhone('+62 812 3456 7890'), '081234567890');
  assert.equal(cleanPhone('6281234567890'), '081234567890');
  assert.equal(cleanPhone('8123456789'), '08123456789');
  assert.equal(cleanPhone('  0812 3456 7890  '), '081234567890');
});

test('nomor HP yang tidak masuk akal ditolak', () => {
  assert.equal(cleanPhone(''), null);
  assert.equal(cleanPhone('12345'), null); // tidak diawali 0 setelah normalisasi
  assert.equal(cleanPhone('0812'), null); // terlalu pendek
  assert.equal(cleanPhone('0812345678901234567'), null); // terlalu panjang
  assert.equal(cleanPhone('abcdefghij'), null);
});

test('nama dirapikan tanpa mengubah huruf', () => {
  assert.equal(cleanName('  Irvan   Nur   Cahyo '), 'Irvan Nur Cahyo');
});

test('nama depan menjadi dasar username', () => {
  assert.equal(usernameBase('Irvan Nur Cahyo'), 'irvan');
  assert.equal(usernameBase('IRVAN'), 'irvan');
  // Nama depan terlalu pendek: pakai nama lengkap supaya tetap bisa diketik.
  assert.equal(usernameBase('M. Rizky'), 'mrizky');
  assert.equal(usernameBase('  Ade  '), 'ade');
});

test('username berikutnya memakai angka, bukan nama lain', () => {
  assert.equal(usernameCandidate('irvan', 1), 'irvan');
  assert.equal(usernameCandidate('irvan', 2), 'irvan2');
  assert.equal(usernameCandidate('irvan', 10), 'irvan10');
});

test('formulir yang lengkap diterima dan dinormalkan', () => {
  const r = validateRegistration({
    name: '  Irvan   Nur ',
    phone: '+62 812-3456-7890',
    address: 'Jl. Melati 12, Bandung',
    position: 'Bek',
  });
  assert.equal(r.ok, true);
  assert.deepEqual(r.value, {
    name: 'Irvan Nur',
    phone: '081234567890',
    address: 'Jl. Melati 12, Bandung',
    position: 'Bek',
  });
});

test('setiap isian wajib diisi', () => {
  const base = { name: 'Irvan', phone: '081234567890', address: 'Jl. Melati 12', position: 'Bek' };
  for (const key of ['name', 'phone', 'address', 'position']) {
    const body = { ...base, [key]: '' };
    const r = validateRegistration(body);
    assert.equal(r.ok, false, `${key} kosong harus ditolak`);
    assert.ok(r.error.length > 0);
  }
});

test('posisi di luar daftar ditolak', () => {
  const r = validateRegistration({
    name: 'Irvan', phone: '081234567890', address: 'Jl. Melati 12', position: 'Striker',
  });
  assert.equal(r.ok, false);
});

test('nama dengan angka atau simbol aneh ditolak', () => {
  const base = { phone: '081234567890', address: 'Jl. Melati 12', position: 'Bek' };
  assert.equal(validateRegistration({ ...base, name: 'Irvan123' }).ok, false);
  assert.equal(validateRegistration({ ...base, name: 'Irvan @ rumah' }).ok, false);
  // Titik dan tanda hubung lazim di nama, jadi tetap diterima.
  assert.equal(validateRegistration({ ...base, name: "M. Irvan-Ash" }).ok, true);
});
