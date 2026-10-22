import { test } from 'node:test';
import assert from 'node:assert/strict';

import { rejectSql, toPositional } from './_guard.js';
import { APP_WEB_TABLES, APP_WEB_VIEWS } from '../scripts/_grants.mjs';
import { reads, writes, paramsFor } from '../scripts/_app-queries.mjs';

// Query yang benar-benar dikirim aplikasi ada di scripts/_app-queries.mjs
// (dipakai juga oleh scripts/e2e-check.mjs). Tujuannya menangkap filter yang
// terlalu ketat: kalau daftar ini ditolak, fitur di app ikut mati walau tidak
// ada masalah keamanan.
const admin = { r: 'admin' };
const treasurer = { r: 'treasurer' };
const member = { r: 'member' };

test('semua query aplikasi lolos untuk admin', () => {
  for (const [name, sql] of Object.entries(reads)) {
    assert.equal(rejectSql(sql, admin), null, `baca ${name}`);
  }
  for (const [name, sql] of Object.entries(writes)) {
    assert.equal(rejectSql(sql, admin), null, `tulis ${name}`);
  }
});

test('bendahara boleh menulis data klub', () => {
  for (const [name, sql] of Object.entries(writes)) {
    assert.equal(rejectSql(sql, treasurer), null, `tulis ${name}`);
  }
});

test('anggota hanya boleh membaca', () => {
  for (const [name, sql] of Object.entries(reads)) {
    if (name === 'users') continue; // daftar pengguna khusus admin
    assert.equal(rejectSql(sql, member), null, `baca ${name}`);
  }
  for (const [name, sql] of Object.entries(writes)) {
    assert.notEqual(rejectSql(sql, member), null, `tulis ${name}`);
  }
});

test('semua query aplikasi bisa diikat parameternya', () => {
  for (const sql of [...Object.values(reads), ...Object.values(writes)]) {
    const params = paramsFor(sql);
    assert.doesNotThrow(() => toPositional(sql, params), sql.slice(0, 40));
  }
});

// Izin `app_web` (scripts/_grants.mjs) harus mencakup setiap tabel/view yang
// dipanggil app. Query yang lolos filter SQL tetap gagal di Neon kalau
// grant-nya lupa ditambah — ini yang dulu terjadi pada `tournament_teams`
// dan `v_team_standings`.
test('setiap tabel/view aplikasi punya izin app_web', () => {
  const granted = new Set([...APP_WEB_TABLES, ...APP_WEB_VIEWS, 'users']);
  const referenced = new Set();
  // `DO UPDATE SET ...` bukan nama tabel, jadi kata kunci SQL disaring.
  const keywords = new Set(['set', 'select', 'where', 'values', 'only']);
  for (const sql of [...Object.values(reads), ...Object.values(writes)]) {
    for (const m of sql.matchAll(/\b(?:from|join|into|update)\s+([a-z_][a-z0-9_]*)/gi)) {
      const name = m[1].toLowerCase();
      if (!keywords.has(name)) referenced.add(name);
    }
  }
  for (const table of referenced) {
    assert.ok(granted.has(table), `tabel ${table} dipakai app tapi tidak di-grant`);
  }
});

// Mode publik: tamu (tanpa token) boleh membaca data klub, tetapi tidak boleh
// menulis dan tidak boleh melihat daftar pengguna.
test('tamu hanya boleh membaca data klub', () => {
  const guest = { r: 'public' };
  for (const [name, sql] of Object.entries(reads)) {
    if (name === 'users') {
      assert.notEqual(rejectSql(sql, guest), null, 'baca users harus ditolak');
      continue;
    }
    assert.equal(rejectSql(sql, guest), null, `baca ${name}`);
  }
  for (const [name, sql] of Object.entries(writes)) {
    assert.notEqual(rejectSql(sql, guest), null, `tulis ${name} harus ditolak`);
  }
});

test('query yang menyentuh tabel users ditolak untuk tamu', () => {
  const guest = { r: 'public' };
  assert.notEqual(rejectSql('SELECT u.username FROM users u', guest), null);
  assert.notEqual(rejectSql('SELECT * FROM users WHERE id=@id', guest), null);
});
