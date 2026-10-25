// Kredensial skrip pemeriksaan.
//
// Kenapa tidak ada default lagi: repo ini PUBLIK, dan password default
// (`admin123`) pernah tertulis di 15 skrip. Artinya siapa pun yang membaca
// GitHub punya akses admin ke klub yang真的 memakai app ini — termasuk
// produksi. Password default adalah hole di dinding, bukan fitur.
//
// Jadi sekarang: kredensial WAJIB diberikan lewat environment (`ADMIN_USER`
// / `ADMIN_PASS`), dan skrip BERHENTI dengan pesan jelas kalau tidak ada.
// Berguna untuk mesin pengembangan: taruh di `.env` (sudah masuk
// .gitignore) lalu skrip membacanya sendiri.
//
// Env dibaca dari process.env lebih dulu; `.env` hanya dipakai sebagai
// cadangan, dan nilainya TIDAK pernah dicetak ke log.
import { existsSync, readFileSync } from 'node:fs';

let _envLoaded = false;

/** Muat `.env` ke process.env (tanpa menimpa yang sudah ada). */
function loadDotEnv() {
  if (_envLoaded) return;
  _envLoaded = true;
  const file = new URL('../.env', import.meta.url);
  if (!existsSync(file)) return;
  for (const line of readFileSync(file, 'utf8').split('\n')) {
    const m = /^\s*([A-Z_][A-Z0-9_]*)\s*=\s*(.*)$/.exec(line);
    if (!m) continue;
    const value = m[2].trim().replace(/^["']|["']$/g, '');
    if (value && !(m[1] in process.env)) process.env[m[1]] = value;
  }
}

/**
 * Kredensial admin untuk skrip pemeriksaan.
 *
 * Melempar error kalau tidak ada — lebih baik skrip berhenti dengan pesan
 * jelas daripada diam-diam memakai password default yang sudah bocor.
 */
export function adminCredentials() {
  loadDotEnv();
  const user = process.env.ADMIN_USER;
  const pass = process.env.ADMIN_PASS;
  const missing = [];
  if (!user) missing.push('ADMIN_USER');
  if (!pass) missing.push('ADMIN_PASS');
  if (missing.length > 0) {
    throw new Error(
      `${missing.join(' dan ')} belum diisi.\n` +
        'Kredensial admin tidak lagi punya nilai default (repo ini publik).\n' +
        'Isi di environment mesin ini atau di file .env di root repo:\n' +
        '  ADMIN_USER=admin\n' +
        '  ADMIN_PASS=<password admin>\n',
    );
  }
  return { user, pass };
}
