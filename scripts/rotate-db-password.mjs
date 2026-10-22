// Rotasi password role database setelah kredensial bocor.
//
// Kenapa perlu: connection string owner pernah ikut ter-commit ke repo publik
// (file `.db-url.tmp`). Menghapus file dari commit TIDAK cukup — nilainya
// sudah ada di riwayat git, di cache, dan di clone mana pun. Satu-satunya
// perbaikan yang benar adalah mengganti password-nya, lalu memasang nilai baru
// di env Vercel.
//
//   DATABASE_URL=<owner lama> node scripts/rotate-db-password.mjs neondb_owner
//   DATABASE_URL_WEB=<app_web lama> node scripts/rotate-db-password.mjs app_web
//
// Skrip mencetak connection string BARU. Simpan ke env Vercel, jangan ke file.
import { randomBytes } from 'node:crypto';

import { makeRunner } from './_neon.mjs';

const role = process.argv[2];
if (!role) {
  console.error('Pakai: node scripts/rotate-db-password.mjs <nama-role>');
  process.exit(1);
}
const url = process.env.DATABASE_URL;
if (!url) {
  console.error('DATABASE_URL belum diset (pakai connection string LAMA).');
  process.exit(1);
}

// Password baru: base64url supaya aman di URL tanpa escaping.
const password = randomBytes(24).toString('base64url');

const run = await makeRunner(url);
// Identifier role tidak bisa diparameterkan; hanya izinkan nama role yang
// bentuknya wajar supaya argumen tidak bisa menyuntik SQL.
if (!/^[a-z_][a-z0-9_]*$/i.test(role)) {
  console.error('Nama role tidak valid.');
  process.exit(1);
}
await run(`ALTER ROLE "${role}" WITH PASSWORD '${password}'`);

const next = new URL(url);
next.password = password;
console.log(`Password role "${role}" sudah diganti.`);
console.log(`CONNECTION_STRING_BARU=${next.toString()}`);
