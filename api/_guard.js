// Penjaga query untuk /api/sql.
//
// Klien boleh mengirim SQL apa pun, jadi validasi ini harus tahan terhadap
// trik penulisan (komentar, tanda kutip, nama tabel berskema). Aturan:
//   1. Satu statement, hanya SELECT/INSERT/UPDATE/DELETE/WITH.
//   2. Tulis hanya ke tabel yang diizinkan; `users` hanya lewat /api/auth.
//   3. Role `member` tidak boleh menulis sama sekali.
//   4. Kalau sebuah tulis tidak bisa dipastikan targetnya, tolak.
//   5. Data pribadi anggota (nomor HP, alamat) tidak boleh diambil role
//      baca-saja — lihat `_privacy.js`.

import { hiddenColumns, hiddenColumnMessage, mentionsHidden } from './_privacy.js';

const MAX_LEN = 20_000;

// Tabel yang tidak boleh ditulis lewat jalur SQL umum.
const WRITE_DENY = new Set(['users', 'pg_catalog', 'information_schema']);

const DANGEROUS =
  /\b(pg_[a-z_]+|information_schema|dblink|lo_import|lo_export|set_config|current_setting|grant|revoke|alter|create|drop|truncate|comment\s+on|copy|vacuum|analyze|listen|notify|security\s+definer|execute|prepare|deallocate|call|reset)\b/i;

const WRITE_HEAD =
  /\b(insert\s+into|update|delete\s+from|merge\s+into)\s+(?:only\s+)?((?:"(?:[^"]|"")*"|[a-z_][a-z0-9_$]*)(?:\s*\.\s*(?:"(?:[^"]|"")*"|[a-z_][a-z0-9_$]*))*)/gi;

/**
 * Buang komentar dan isi literal string supaya kata kunci di dalamnya tidak
 * dianggap perintah. Identifier berkutip dibiarkan agar targetnya terbaca.
 */
export function normalize(text) {
  let out = '';
  let i = 0;
  while (i < text.length) {
    const c = text[i];

    if (c === "'") {
      out += "''";
      i++;
      while (i < text.length) {
        if (text[i] === "'") {
          if (text[i + 1] === "'") {
            i += 2;
            continue;
          }
          i++;
          break;
        }
        i++;
      }
      continue;
    }

    if (c === '"') {
      out += c;
      i++;
      while (i < text.length) {
        out += text[i];
        if (text[i] === '"') {
          if (text[i + 1] === '"') {
            out += text[i + 1];
            i += 2;
            continue;
          }
          i++;
          break;
        }
        i++;
      }
      continue;
    }

    if (c === '$' && text[i + 1] === '$') {
      const end = text.indexOf('$$', i + 2);
      out += "''";
      i = end === -1 ? text.length : end + 2;
      continue;
    }

    if (c === '-' && text[i + 1] === '-') {
      while (i < text.length && text[i] !== '\n') i++;
      out += ' ';
      continue;
    }

    if (c === '/' && text[i + 1] === '*') {
      const end = text.indexOf('*/', i + 2);
      i = end === -1 ? text.length : end + 2;
      out += ' ';
      continue;
    }

    out += c;
    i++;
  }
  return out;
}

/** Nama tabel terakhir dari target tulis, tanpa kutip dan skema. */
function tableName(target) {
  const last = target.split('.').pop().trim();
  return last.replace(/^"|"$/g, '').replace(/""/g, '"').toLowerCase();
}

/** Daftar tabel yang ditulis, atau null kalau ada tulis tanpa target jelas. */
function writeTargets(code) {
  const targets = [];
  let found = false;
  for (const m of code.matchAll(WRITE_HEAD)) {
    found = true;
    targets.push(tableName(m[2]));
  }
  if (!found && /\b(insert|update|delete|merge)\b/i.test(code)) {
    return { targets, ambiguous: true };
  }
  return { targets, ambiguous: false };
}

// Kolom data pribadi anggota, dipisah menurut tingkat akses.
//
//   * `address` (alamat tinggal) — untuk SEMUA orang kecuali admin dan
//     bendahara. Alamat rumah tidak perlu dilihat siapa pun di luar klub.
//
//   * `phone` (nomor HP) — untuk admin, bendahara, dan anggota yang sudah
//     masuk. Anggota perlu nomor satu sama lain untuk menjadwalkan main.
//     Tamu (mode publik) tidak: aplikasi sengaja menampilkan data klub
//     tanpa login, tapi daftar anggota lengkap dengan nomor HP adalah data
//     pribadi yang tidak perlu terlihat oleh siapa pun di luar klub.
//
// Rincian aturannya hidup di `_privacy.js` — satu sumber kebenaran untuk
// guard (menolak query yang menyebut kolom ini) dan sql.js (menyaring hasil
// query yang memakai `SELECT *`).
export { hiddenColumns, mentionsHidden, hiddenColumnMessage } from './_privacy.js';

/** Return pesan error (string) kalau query ditolak, null kalau boleh. */
export function rejectSql(text, session) {
  if (typeof text !== 'string' || !text.trim()) return 'sql required';
  if (text.length > MAX_LEN) return 'Query terlalu panjang';

  const trimmed = text.trim().replace(/;\s*$/, '');
  const code = normalize(trimmed);

  if (code.includes(';')) return 'Satu statement per permintaan';

  if (!/^\s*(select|insert|update|delete|with)\b/i.test(code)) {
    return 'Hanya SELECT/INSERT/UPDATE/DELETE';
  }

  // Password tidak pernah lewat jalur ini — pakai /api/auth.
  if (/\b(password_hash|pin_hash)\b/i.test(code)) return 'Password hanya lewat /api/auth';

  if (DANGEROUS.test(code)) return 'Query tidak diizinkan';

  // SELECT ... INTO membuat tabel baru; tidak dipakai aplikasi.
  if (/\binto\b/i.test(code.replace(/\b(insert|merge)\s+into\b/gi, 'insert_target'))) {
    return 'Query tidak diizinkan';
  }

  // `ON CONFLICT DO UPDATE SET` bukan perintah UPDATE bertarget.
  const scan = code.replace(/\bdo\s+update\b/gi, 'do_update');
  const { targets, ambiguous } = writeTargets(scan);

  if (ambiguous) return 'Query tidak dikenali';

  // Data pribadi anggota (nomor HP, alamat tinggal) TIDAK boleh keluar ke
  // role baca-saja.
  //
  // Kenapa: mode publik (tamu tanpa login) sengaja menampilkan data klub
  // supaya orang bisa lihat jadwal dan kas tanpa akun. Tapi daftar anggota
  // yang ikut打出 lengkap dengan nomor HP dan alamat adalah data pribadi
  // yang tidak perlu terlihat oleh siapa pun di luar klub — dan lewat
  // /api/sql yang menerima SQL bebas, "SELECT * FROM members" cukup untuk
  // mengambil semuanya dalam satu permintaan.
  //
  // Yang boleh: admin dan bendahara (keduanya sudah memegang data kas dan
  // iuran, jadi nomor HP untuk="@+62" plainly needed). Role `member` dan
  // tamu tidak.
  if (targets.length === 0) {
    if (/\busers\b/i.test(scan) && session?.r !== 'admin') {
      return 'Hanya admin yang bisa melihat pengguna';
    }
    // Daftar pengguna juga tidak untuk tamu, termasuk lewat view/join.
    if (session?.r === 'public' && /\busers\b/i.test(scan)) {
      return 'Hanya admin yang bisa melihat pengguna';
    }
    // Data pribadi anggota (nomor HP untuk tamu, alamat untuk semua role
    // baca-saja) tidak boleh ditanyakan secara eksplisit. Query yang
    // memakai `SELECT *` tidak bisa dicek di sini — hasilnya disaring di
    // sql.js.
    const hidden = hiddenColumns(session?.r);
    if (mentionsHidden(scan, hidden)) {
      return hiddenColumnMessage(scan, hidden);
    }
    return null;
  }

  // `public` = tamu tanpa token; `member` = akun dengan hak baca saja.
  if (session?.r === 'public' || session?.r === 'member') {
    return 'Mode publik hanya bisa melihat data. Masuk untuk mengubah.';
  }
  if (targets.some((t) => WRITE_DENY.has(t))) return 'Tabel ini hanya lewat /api/auth';
  if (/\busers\b/i.test(scan)) return 'Tabel ini hanya lewat /api/auth';

  return null;
}

export class MissingParam extends Error {}

/**
 * `@nama` -> `$1` hanya di luar string/identifier/komentar, supaya karakter
 * `@` di dalam teks (mis. email) tidak ikut dianggap parameter.
 */
export function toPositional(text, params = {}) {
  const order = [];
  let out = '';
  let i = 0;

  while (i < text.length) {
    const c = text[i];

    if (c === "'" || c === '"') {
      const quote = c;
      out += c;
      i++;
      while (i < text.length) {
        out += text[i];
        if (text[i] === quote) {
          if (text[i + 1] === quote) {
            out += text[i + 1];
            i += 2;
            continue;
          }
          i++;
          break;
        }
        i++;
      }
      continue;
    }

    if (c === '-' && text[i + 1] === '-') {
      const nl = text.indexOf('\n', i);
      const end = nl === -1 ? text.length : nl;
      out += text.slice(i, end);
      i = end;
      continue;
    }

    if (c === '/' && text[i + 1] === '*') {
      const end = text.indexOf('*/', i + 2);
      const stop = end === -1 ? text.length : end + 2;
      out += text.slice(i, stop);
      i = stop;
      continue;
    }

    if (c === '@') {
      const m = /^@([a-zA-Z_][a-zA-Z0-9_]*)/.exec(text.slice(i));
      if (m) {
        const name = m[1];
        let index = order.indexOf(name);
        if (index === -1) {
          if (!Object.hasOwn(params, name)) {
            throw new MissingParam(`Parameter @${name} tidak dikirim`);
          }
          order.push(name);
          index = order.length - 1;
        }
        out += `$${index + 1}`;
        i += m[0].length;
        continue;
      }
    }

    out += c;
    i++;
  }

  return { text: out, values: order.map((n) => params[n] ?? null) };
}
