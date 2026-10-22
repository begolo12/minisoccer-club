// Ubah query tulis jadi query baca yang memvalidasi tabel + kolomnya, tanpa
// mengeksekusi tulis apa pun.
//
// Kenapa tidak dijalankan saja lalu di-rollback? `/api/sql` menerima satu
// statement dan tidak punya transaksi, jadi `BEGIN ... ROLLBACK` tidak bisa
// dikirim. Menjalankan UPDATE/DELETE dengan `WHERE false` pun tidak cukup:
// `SET played_at=@t` tetap dievaluasi tipenya, dan parameter contoh tidak
// selalu bertipe sama dengan kolom. Yang ingin dibuktikan adalah "tabel dan
// kolom yang disebut app ada di DB" — itu cukup lewat SELECT, sementara izin
// tulis dibuktikan terpisah oleh round-trip di e2e-check.
export function probeFor(sql) {
  const insert = /^\s*insert\s+into\s+([a-z_][a-z0-9_]*)\s*\(([^)]*)\)/i.exec(sql);
  if (insert) {
    const cols = insert[2].split(',').map((c) => c.trim()).filter(Boolean);
    return `SELECT ${cols.join(', ')} FROM ${insert[1]} LIMIT 0`;
  }

  const update = /^\s*update\s+([a-z_][a-z0-9_]*)\s+set\s+([\s\S]*?)(?:\bwhere\b|$)/i.exec(sql);
  if (update) {
    // Kolom = identifier di kiri `=` pada level teratas SET. Subquery di kanan
    // `=` dilewati supaya kolom di dalamnya tidak ikut dianggap kolom target.
    const cols = [];
    let depth = 0;
    let buf = '';
    for (const ch of update[2]) {
      if (ch === '(') depth++;
      if (ch === ')') depth--;
      if (ch === ',' && depth === 0) {
        cols.push(buf);
        buf = '';
        continue;
      }
      if (depth === 0) buf += ch;
    }
    cols.push(buf);
    const names = cols
      .map((c) => c.split('=')[0].trim())
      .filter((c) => /^[a-z_][a-z0-9_]*$/i.test(c));
    return `SELECT ${names.join(', ')} FROM ${update[1]} LIMIT 0`;
  }

  const del = /^\s*delete\s+from\s+([a-z_][a-z0-9_]*)/i.exec(sql);
  if (del) return `SELECT * FROM ${del[1]} LIMIT 0`;

  return sql;
}

/** True kalau query hanya membaca (tidak perlu diubah jadi probe). */
export function isRead(sql) {
  return /^\s*(select|with)\b/i.test(sql);
}

/** Nama parameter `@nama` yang dipakai query. */
export function paramNames(sql) {
  return [...new Set([...sql.matchAll(/@([a-zA-Z_][a-zA-Z0-9_]*)/g)].map((m) => m[1]))];
}
