// Buat daftar berkas shell untuk di-precache service worker.
//
// Kenapa perlu: pada pemuatan pertama, service worker baru aktif SETELAH
// halaman selesai memuat asetnya. Jadi aset yang dibutuhkan Flutter untuk
// start (canvaskit, potongan main.dart.js, font) tidak pernah lewat fetch
// handler dan tidak masuk cache. Akibatnya halaman bisa dibuka offline tapi
// aplikasinya tidak jalan.
//
// Solusinya: daftar lengkap berkas ditulis saat build, lalu SW menyimpannya
// sekaligus waktu install (saat itu masih online).
//
//   node scripts/gen-sw-manifest.mjs   (setelah flutter build web)
import { readdir, writeFile } from 'node:fs/promises';
import { join, relative, sep } from 'node:path';

const root = 'build/web';

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
