// Matikan service worker bawaan Flutter.
//
// Flutter 3.47 masih menghasilkan `flutter_service_worker.js` berupa stub yang,
// saat aktif, **membatalkan registrasinya sendiri lalu memuat ulang semua tab**.
// Stub itu mendaftar pada scope yang sama dengan `sw.js` milik aplikasi, jadi
// keduanya saling menggantikan: halaman dimuat ulang dua kali setiap rilis, dan
// cache offline aplikasi ikut terhapus.
//
// Aplikasi memakai `web/sw.js` (lihat `scripts/gen-sw-manifest.mjs`). Supaya
// Flutter tidak mendaftarkan apa pun, `serviceWorkerSettings` dibuang dari
// pemanggilan `_flutter.loader.load(...)` — bukan hanya versinya, karena
// bootstrap tetap mendaftar dengan `?v=null` bila objeknya masih ada. Stub-nya
// juga dihapus dari hasil build.
//
//   node scripts/disable-flutter-sw.mjs [direktori-build]
import { readFile, rm, stat, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

const root = process.argv[2] ?? 'build/web';
const bootstrapPath = join(root, 'flutter_bootstrap.js');

const source = await readFile(bootstrapPath, 'utf8');

/**
 * Buang kunci `serviceWorkerSettings: {...}` dari objek konfigurasi
 * `_flutter.loader.load(...)`.
 *
 * Pencarian dimulai dari pemanggilan `load`, bukan dari awal berkas: di dalam
 * pustaka loader ada parameter bernama sama (`load({serviceWorkerSettings:e})`)
 * yang tidak boleh disentuh.
 */
function tanpaServiceWorkerSettings(text) {
  const call = text.lastIndexOf('_flutter.loader.load(');
  if (call < 0) return text;

  const key = text.indexOf('serviceWorkerSettings:', call);
  if (key < 0) return text;

  const braceStart = text.indexOf('{', key);
  if (braceStart < 0) return text;

  let depth = 0;
  let end = -1;
  for (let i = braceStart; i < text.length; i += 1) {
    if (text[i] === '{') depth += 1;
    else if (text[i] === '}') {
      depth -= 1;
      if (depth === 0) {
        end = i;
        break;
      }
    }
  }
  if (end < 0) return text;

  let from = key;
  let to = end + 1;

  // Koma di depan (kalau ada) ikut dibuang; kalau tidak ada, koma di belakang.
  const before = text.slice(0, from);
  const trimmed = before.replace(/,\s*$/, '');
  if (trimmed.length !== before.length) {
    from = trimmed.length;
  } else {
    const after = text.slice(to).match(/^\s*,/);
    if (after) to += after[0].length;
  }

  return text.slice(0, from) + text.slice(to);
}

const patched = tanpaServiceWorkerSettings(source);

if (patched === source) {
  // Sudah pernah ditambal (mis. deploy dari CLI mengunggah build/web yang
  // sudah lewat skrip ini, lalu Vercel menjalankannya lagi). Baru jadi masalah
  // kalau stub Flutter masih ada: itu tanda bentuk bootstrap berubah.
  const stub = await stat(join(root, 'flutter_service_worker.js')).catch(() => null);
  if (stub) {
    throw new Error(
      'Tidak menemukan `serviceWorkerSettings` di pemanggilan _flutter.loader.load — periksa versi Flutter.',
    );
  }
  console.log('service worker Flutter sudah dimatikan sebelumnya; sw.js aplikasi yang dipakai');
  process.exit(0);
}

await writeFile(bootstrapPath, patched);
await rm(join(root, 'flutter_service_worker.js'), { force: true });

console.log('service worker Flutter dimatikan; sw.js aplikasi yang dipakai');
