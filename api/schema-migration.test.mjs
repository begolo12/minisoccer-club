// Penjaga migrasi schema.
//
// Latar belakang: saat iuran diubah dari BULANAN ke PER TURNAMEN, kolom
// `payments.period` dihapus — tetapi satu blok `DO $$ ... $$` yang membuat
// index unik pada kolom itu tertinggal. Akibatnya `npm run db:init` GAGAL
// dengan "column period does not exist", sehingga database baru tidak bisa
// disiapkan sama sekali. Tidak ada tes yang menangkapnya karena semua
// pemeriksaan lain berjalan di database yang sudah dimigrasi.
//
// Tes ini membaca `db/schema.sql` sebagai teks dan memastikan tidak ada
// pernyataan yang masih menyebut kolom yang sudah dihapus.
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import assert from 'node:assert/strict';

const schema = readFileSync(new URL('../db/schema.sql', import.meta.url), 'utf8');

/** Buang komentar supaya penjelasan sejarah tidak dianggap kode. */
function stripComments(sql) {
  return sql
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .split('\n')
    .map((line) => line.replace(/--.*$/, ''))
    .join('\n');
}

const code = stripComments(schema);

test('schema tidak memakai kolom payments.period yang sudah dihapus', () => {
  // `period` masih sah di beberapa tempat, jadi tes ini mencari PEMAKAIAN
  // sebagai kolom, bukan sekadar kata "period":
  //  - `CREATE ... INDEX ... ON payments (... period ...)`
  //  - `GROUP BY ... period`
  //  - `SELECT ... period ... FROM payments`
  //
  // Yang TIDAK dianggap pelanggaran:
  //  - `ALTER TABLE payments DROP COLUMN period` (migrasi yang membuangnya)
  //  - `DROP INDEX ... period` (nama index lama, bukan kolom)
  //  - pemeriksaan `information_schema ... column_name = 'period'` (justru
  //    cara aman memeriksa keberadaan kolom sebelum dipakai)
  const offenders = [];

  for (const m of code.matchAll(
    /CREATE\s+(?:UNIQUE\s+)?INDEX[^;]*?\bON\s+payments\s*\(([^)]*)\)/gi,
  )) {
    if (/\bperiod\b/i.test(m[1])) {
      offenders.push(`index pada payments memakai kolom period: ${m[0].replace(/\s+/g, ' ').slice(0, 120)}`);
    }
  }

  for (const m of code.matchAll(/GROUP\s+BY\s+([^;]*?)(?:HAVING|ORDER|$)/gi)) {
    if (/\bperiod\b/i.test(m[1]) && /payments/i.test(code.slice(Math.max(0, m.index - 600), m.index + 200))) {
      offenders.push(`GROUP BY memakai period: ${m[0].replace(/\s+/g, ' ').slice(0, 120)}`);
    }
  }

  for (const m of code.matchAll(/SELECT\s+([^;]*?)\bFROM\s+payments\b/gi)) {
    if (/^\s*\*|(?:^|,)\s*period\b/i.test(m[1])) {
      offenders.push(`SELECT dari payments mengambil period: ${m[0].replace(/\s+/g, ' ').slice(0, 120)}`);
    }
  }

  assert.deepEqual(
    offenders,
    [],
    `schema masih memakai kolom period pada tabel payments, sehingga db:init gagal:\n${offenders.join('\n')}`,
  );
});

test('setiap kolom yang dipakai index/constraint ada di CREATE TABLE-nya', () => {
  // Kumpulkan kolom tiap tabel dari blok CREATE TABLE.
  const tables = new Map();
  for (const m of code.matchAll(/CREATE TABLE IF NOT EXISTS (\w+) \(([\s\S]*?)\n\);/g)) {
    const [, name, body] = m;
    const cols = new Set();
    for (const line of body.split('\n')) {
      const c = /^\s{2}([a-z_][a-z0-9_]*)\s+/i.exec(line);
      if (c) cols.add(c[1].toLowerCase());
    }
    tables.set(name.toLowerCase(), cols);
  }
  assert.ok(tables.size > 5, 'blok CREATE TABLE tidak terbaca');

  // Kolom yang ditambahkan lewat migrasi dianggap ada.
  for (const m of code.matchAll(/ALTER TABLE (\w+) ADD COLUMN (?:IF NOT EXISTS )?([a-z_][a-z0-9_]*)/gi)) {
    tables.get(m[1].toLowerCase())?.add(m[2].toLowerCase());
  }

  // Index yang dibuat langsung (bukan lewat ALTER) harus memakai kolom yang ada.
  const problems = [];
  for (const m of code.matchAll(/CREATE (?:UNIQUE )?INDEX (?:IF NOT EXISTS )?\w+\s+ON (\w+)\s*\(([^)]*)\)/gi)) {
    const table = m[1].toLowerCase();
    const cols = tables.get(table);
    if (!cols) continue; // tabel dari luar berkas ini
    for (const raw of m[2].split(',')) {
      const col = raw.trim().split(/\s+/)[0].toLowerCase();
      if (!col || col.includes('(')) continue; // ekspresi, bukan kolom polos
      if (!cols.has(col)) problems.push(`index pada ${table} memakai kolom "${col}" yang tidak ada`);
    }
  }
  assert.deepEqual(problems, [], problems.join('\n'));
});

test('migrasi iuran per turnamen men-drop period sebelum membuat index baru', () => {
  const dropAt = code.search(/ALTER TABLE payments\s+DROP COLUMN\s+(IF EXISTS\s+)?period/i);
  const addAt = code.search(/ADD COLUMN IF NOT EXISTS tournament_id/i);
  assert.ok(addAt > -1, 'kolom tournament_id tidak pernah ditambahkan di schema');
  if (dropAt > -1) {
    assert.ok(
      dropAt > addAt,
      'kolom period harus dihapus SETELAH tournament_id ditambahkan, ' +
        'supaya data lama bisa dipindahkan dulu',
    );
  }
});
