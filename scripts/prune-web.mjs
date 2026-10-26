// Buang artefak web yang tidak dipakai build ini.
//
// `flutter build web` menyalin SEMUA varian renderer, bukan hanya yang dipakai.
// Hasilnya `build/web` 47 MB, dan 30 MB di antaranya tidak pernah diminta satu
// browser pun:
//
//   * `*.symbols`        — peta simbol untuk stack trace yang bisa dibaca
//                          (6 MB). Berguna saat debug, mati di produksi.
//   * `skwasm*`, `wimp*` — renderer untuk build `--wasm`. Build ini dart2js
//                          (lihat `builds` di `flutter_bootstrap.js`), jadi
//                          tidak ada yang memuatnya (12 MB).
//
// Yang TIDAK dibuang: `canvaskit.js`, `canvaskit.wasm`, dan varian
// `chromium/` + `webparagraph/`. Loader memilih varian menurut kemampuan
// browser (`canvasKitVariant: auto`), jadi Chrome memakai `chromium/` dan
// membuangnya berarti layar kosong di browser yang paling banyak dipakai.
//
// ponytail: daftar ini mengikuti build dart2js + canvaskit. Kalau suatu saat
// pindah ke `flutter build web --wasm`, hapus `skwasm*` dari daftar di bawah
// (kalau tidak, build wasm-nya rusak).
import { readdirSync, rmSync, statSync } from 'node:fs';
import { join } from 'node:path';

const DIR = process.argv[2] ?? 'build/web/canvaskit';

const DROP = [
  /\.symbols$/,
  /^skwasm.*\.(js|wasm)$/,
  /^wimp.*\.(js|wasm)$/,
];

let freed = 0;
let removed = 0;
for (const name of readdirSync(DIR)) {
  if (!DROP.some((re) => re.test(name))) continue;
  const path = join(DIR, name);
  try {
    freed += statSync(path).size;
    rmSync(path, { recursive: true, force: true });
    removed++;
  } catch {
    // Berkas terkunci / sudah hilang: bukan alasan menggagalkan deploy.
  }
}

const mb = (n) => `${(n / 1024 / 1024).toFixed(1)} MB`;
console.log(`prune-web: ${removed} berkas dibuang (${mb(freed)}) dari ${DIR}`);
