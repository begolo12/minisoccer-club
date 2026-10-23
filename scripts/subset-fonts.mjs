// Kecilkan berkas font aplikasi tanpa mengubah tampilannya.
//
// Font Inter dan Barlow Condensed yang diunduh utuh membawa ribuan glif untuk
// bahasa yang tidak dipakai di sini (Latin Extended, Cyrillic, Greek, simbol
// matematika). Empat berkas Inter saja ~1,6 MB; di HP lama ukuran unduhan dan
// waktu pasang itu terasa.
//
// Skrip ini menyisakan hanya yang benar-benar dipakai aplikasi:
//   * Latin dasar + Latin-1 (nama, alamat, huruf beraksen sesekali)
//   * tanda baca umum: — – · … → × dan kawan-kawan
//   * simbol mata uang (Rp memakai huruf biasa, tetapi "€/$" bisa muncul di
//     catatan yang ditempel orang)
//
// Hasilnya ditulis menimpa berkas di `assets/fonts/`, jadi build berikutnya
// memakai versi kecil tanpa langkah tambahan. Jalankan ulang skrip ini kalau
// font aslinya diganti:
//
//   pip install fonttools brotli
//   node scripts/subset-fonts.mjs
//
// Kalau ada karakter yang hilang setelah dijalankan, tambahkan rentangnya di
// UNICODES lalu jalankan lagi; aplikasi akan menampilkan kotak kosong untuk
// glif yang tidak ada, dan itu terlihat langsung di layar.
import { execFileSync } from 'node:child_process';
import { readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

const DIR = 'assets/fonts';

// Latin dasar, Latin-1 Supplement, Latin Extended-A (nama dengan diakritik),
// tanda baca umum, mata uang, dan panah yang dipakai di UI.
const UNICODES = [
  'U+0020-007E', // ASCII
  'U+00A0-00FF', // Latin-1 (× di sini)
  'U+0100-017F', // Latin Extended-A
  'U+2000-206F', // tanda baca umum (— – … ·)
  'U+20A0-20CF', // mata uang
  'U+2190-2199', // panah (→)
].join(',');

const files = readdirSync(DIR).filter((f) => f.endsWith('.ttf'));
if (!files.length) {
  console.error(`Tidak ada .ttf di ${DIR}`);
  process.exit(1);
}

let before = 0;
let after = 0;
for (const f of files) {
  const path = join(DIR, f);
  const size = statSync(path).size;
  before += size;

  execFileSync(
    'python',
    [
      '-m', 'fontTools.subset', path,
      `--unicodes=${UNICODES}`,
      '--layout-features=kern,liga,calt,tnum,lnum',
      '--name-IDs=*',
      '--notdef-outline',
      '--recalc-bounds',
      '--flavor=', // TTF biasa; jangan dikompres
      `--output-file=${path}`,
    ],
    { stdio: 'inherit' },
  );

  const now = statSync(path).size;
  after += now;
  console.log(`${f}: ${(size / 1024).toFixed(0)} KB -> ${(now / 1024).toFixed(0)} KB`);
}

console.log(
  `\nTotal: ${(before / 1048576).toFixed(2)} MB -> ${(after / 1048576).toFixed(2)} MB ` +
    `(hemat ${((before - after) / 1024).toFixed(0)} KB)`,
);
