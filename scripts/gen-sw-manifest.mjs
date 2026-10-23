// Siapkan berkas shell untuk service worker, lalu cap versi cache-nya.
//
// Kenapa perlu manifest: pada pemuatan pertama, service worker baru aktif
// SETELAH halaman selesai memuat asetnya. Jadi aset yang dibutuhkan Flutter
// untuk start (canvaskit, potongan main.dart.js, font) tidak pernah lewat fetch
// handler dan tidak masuk cache. Akibatnya halaman bisa dibuka offline tapi
// aplikasinya tidak jalan.
//
// Kenapa perlu cap versi: nama cache harus berubah di setiap rilis. Kalau
// namanya tetap, service worker baru tidak pernah dipasang (isi `sw.js` sama
// persis), halaman lama terus disajikan, dan pengguna harus menekan
// Ctrl+Shift+R untuk melihat versi terbaru. Dengan cap ini, `sw.js` berubah
// setiap build → browser memasang SW baru → cache lama dihapus → halaman
// memuat ulang sendiri (lihat `web/index.html`).
//
//   node scripts/gen-sw-manifest.mjs [direktori-build]
import { readFile, readdir, writeFile } from 'node:fs/promises';
import { join, relative, sep } from 'node:path';

const root = process.argv[2] ?? 'build/web';

// Berkas yang tidak perlu di-precache: SW sendiri, manifestnya, dan berkas
// versi (harus selalu diambil dari jaringan supaya pembaruan terdeteksi).
const skip = new Set(['sw.js', 'sw-manifest.json', 'version.json']);

async function walk(dir) {
  const out = [];
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) {
      out.push(...(await walk(full)));
    } else if (entry.isFile()) {
      out.push(full);
    }
  }
  return out;
}

const files = (await walk(root))
  .map((f) => relative(root, f).split(sep).join('/'))
  .filter((f) => !skip.has(f))
  .sort();

await writeFile(join(root, 'sw-manifest.json'), JSON.stringify(files, null, 0));
console.log(`sw-manifest.json: ${files.length} berkas`);

/* ------------------------- cap versi service worker ------------------------ */

/**
 * Penanda rilis untuk nama cache.
 *
 * Nomor versi aplikasi saja tidak cukup: banyak rilis tidak menaikkannya (isi
 * `version.json` sama), sehingga `sw.js` tetap identik dan browser tidak pernah
 * memasang service worker baru. Akibatnya pengguna terus melihat versi lama
 * sampai menekan Ctrl+Shift+R — persis yang ingin dihindari.
 *
 * Karena itu cap memuat identitas build: commit Vercel, commit git lokal, atau
 * waktu build sebagai jalan terakhir. Setiap rilis menghasilkan `sw.js` yang
 * berbeda.
 */
async function buildStamp() {
  let base = '';
  try {
    const raw = await readFile(join(root, 'version.json'), 'utf8');
    const { version, build_number: build } = JSON.parse(raw);
    if (version) base = `${version}-${build ?? 0}`;
  } catch {
    // `version.json` tidak ada: cap tetap dibuat dari identitas build di bawah.
  }

  const commit =
    process.env.VERCEL_GIT_COMMIT_SHA?.slice(0, 8) ||
    (await gitCommit()) ||
    `t${Date.now()}`;

  return `${base || 'build'}-${commit}`.replace(/[^a-zA-Z0-9.-]/g, '');
}

/** Commit git lokal, kalau skrip dijalankan di mesin pengembang. */
async function gitCommit() {
  try {
    const { execFile } = await import('node:child_process');
    const { promisify } = await import('node:util');
    const run = promisify(execFile);
    const { stdout } = await run('git', ['rev-parse', '--short=8', 'HEAD']);
    return stdout.trim() || null;
  } catch {
    return null;
  }
}

const stamp = await buildStamp();
const swPath = join(root, 'sw.js');
const sw = await readFile(swPath, 'utf8');
const stamped = sw.replace(/const CACHE = 'msc-shell-[^']*';/, `const CACHE = 'msc-shell-${stamp}';`);

if (stamped === sw && !sw.includes(`msc-shell-${stamp}`)) {
  throw new Error('Cap versi gagal: baris `const CACHE = ...` tidak ditemukan di sw.js');
}

await writeFile(swPath, stamped);
console.log(`sw.js: cache msc-shell-${stamp}`);
