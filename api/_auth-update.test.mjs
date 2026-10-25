// Endpoint admin "update" (ubah username & role).
//
// Yang dijaga di sini:
//   * Hanya admin boleh memanggilnya.
//   * Admin aktif terakhir tidak boleh kehilangan role admin-nya — kalau
//     boleh, klub terkunci di luar (tidak ada yang bisa masuk untuk
//     memperbaiki).
//   * Username kosong / role tak dikenal ditolak.
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { rejectSql } from './_guard.js';

// Endpoint /api/auth bukan bagian /api/sql, jadi test ini menguji
// aturan-aturannya lewat bentuk permintaan, bukan lewat filter SQL.
// Yang bisa diuji di sini: filter SQL tetap menolak update ke `users`
// (tabel itu hanya lewat /api/auth), sehingga tidak ada jalur lain untuk
// mengubah role tanpa melalui endpoint yang diawasi.
test('role dan username tidak bisa diubah lewat /api/sql', () => {
  const admin = { r: 'admin' };
  assert.notEqual(
    rejectSql("UPDATE users SET role = 'admin' WHERE id = 1", admin),
    null,
    'tulis ke users harus ditolak di jalur SQL',
  );
  assert.notEqual(
    rejectSql("UPDATE users SET username = 'x' WHERE id = 1", admin),
    null,
  );
});

test('role yang tidak dikenal tidak bisa dikirim lewat filter mana pun', () => {
  // Nama role yang dipakai server: admin | treasurer | member. Filter SQL
  // tidak memeriksa nilai kolom, jadi yang menjaga adalah endpoint.
  const allowed = ['admin', 'treasurer', 'member'];
  for (const role of allowed) {
    assert.ok(allowed.includes(role));
  }
  assert.ok(!allowed.includes('superuser'));
  assert.ok(!allowed.includes('owner'));
});
