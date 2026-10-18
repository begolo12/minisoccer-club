# Minisoccer Club ⚽

Aplikasi manajemen klub mini soccer: **Flutter** + **shadcn UI** + **Neon Postgres** (database dari Vercel).
Mobile-first, dark & light mode, plus versi web.

Tema "papan skor": angka Barlow Condensed, teks Inter, hijau lapangan di atas
hitam, daftar ber-garis alih-alih tumpukan kartu. Rail kiri di layar lebar,
bottom nav di HP. Detail token dan tooling preview: [`design/README.md`](design/README.md).

## 📲 Download APK

**[Download APK terbaru](https://github.com/begolo12/minisoccer-club/releases/latest/download/app-release.apk)**

Versi web: **https://minisoccer-club.vercel.app**

1. Buka link di HP → download.
2. Buka file → izinkan "Install unknown apps" untuk browser/file manager → **Install**.
3. Buka app → **Masuk** dengan akun dari admin. (Tanpa connection string; data lewat server.)

## Fitur

| Fitur | Isi |
|---|---|
| **Beranda** | Jadwal terdekat, W/D/L, iuran bulan ini, aksi cepat, top skor, pengumuman |
| **Anggota** | CRUD pemain (posisi, nomor punggung, HP), cari, filter aktif/nonaktif |
| **Tanding** | Jadwal & hasil, sesi/babak dengan pemenang tiap sesi, catat gol / assist / kartu |
| **Turnamen internal** | 4 tim round-robin (semua bertemu semua), jadwal otomatis per 20 menit dalam 2 jam, pembagian tim acak merata, klasemen grup (menang 3 / seri 1 / kalah 0, GM-GK-SG-poin) |
| **Iuran** | Bayar per bulan, siapa yang belum, riwayat, total terkumpul |
| **Kas klub** | Buku kas: iuran + pemasukan/pengeluaran (sewa, wasit, konsumsi, perlengkapan, sponsor), saldo per bulan atau semua waktu |
| **Booking lapangan** | Jadwal sewa, durasi, biaya, status |
| **Pengumuman** | Info klub untuk anggota |
| **Statistik** | Main/menang/draw/kalah, gol, poin, top skor & assist |
| **Pengguna** | Akun + role admin / bendahara / anggota |
| **Pengaturan** | Tema terang/gelap (langsung), info server, tes koneksi, keluar |

QoL: pull-to-refresh (termasuk daftar pendek), empty state yang mengarahkan,
konfirmasi hapus, error state + retry, skeleton loading, layout menyesuaikan
lebar layar, tema bisa diganti tanpa membuka ulang app, tab dimuat saat dibuka
dan disegarkan setelah ada perubahan data, tombol tulis disembunyikan untuk
role anggota.

Catatan: APK sekarang selalu lewat `/api` (token sesi). Connection string DB
hanya ada di env server, tidak lagi disimpan di HP.

## Setup database Neon (Vercel)

1. [Vercel Dashboard](https://vercel.com/dashboard) → **Storage** → database Neon → **Open in Neon**
   (atau langsung [console.neon.tech](https://console.neon.tech)).
2. Copy **Connection string**:
   ```
   postgresql://user:password@ep-xxx.ap-southeast-1.aws.neon.tech/neondb?sslmode=require
   ```
3. Isi `DATABASE_URL` di `.env` lokal dan di env Vercel, lalu jalankan
   `npm run db:init` (schema) dan `npm run db:harden` (role `app_web`).
4. Buka app → layar masuk → akun pertama dibuat lewat form **Admin pertama**,
   lalu tambah akun lain dari menu **Pengguna**.

Connection string hanya ada di env server, tidak pernah di HP maupun browser.

## Development

```bash
flutter pub get
npm install
cp .env.example .env              # isi DATABASE_URL, DATABASE_URL_WEB, AUTH_SECRET
flutter run -d chrome --dart-define=API_BASE=http://localhost:3000   # perlu `vercel dev`
flutter run                       # Android, lewat API yang sama
flutter build apk --release --dart-define=API_BASE=https://minisoccer-club.vercel.app
flutter build web --release
```

## Deploy versi web (opsional)

Web tidak bisa buka TCP ke Postgres, jadi lewat Vercel Function `api/sql.js` (Neon HTTP driver).

```bash
npm install
cp .env.example .env                 # isi DATABASE_URL + AUTH_SECRET
set -a && . ./.env && set +a
npm run db:init                      # buat tabel di Neon (sekali saja)

npx vercel link                      # sekali saja
npx vercel env add DATABASE_URL production
npx vercel env add AUTH_SECRET production   # string acak panjang

flutter build web --release
npx vercel --prod
```

Setelah itu, deploy berikutnya cukup lewat GitHub Actions **Deploy Web** (Run workflow).
Isi secret repo: `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID`.

> **Login.** Semua akses DB lewat `/api/sql` yang butuh token sesi dari `/api/auth`.
> Password di-hash bcrypt oleh Postgres (`pgcrypto`), bukan disimpan di app.
> Tanpa `AUTH_SECRET`, endpoint menolak semua request — itu memang disengaja.

## Struktur

```
lib/
  core/   api.dart (URL API) · db.dart (akses DB + secure storage) · db_web.dart (HTTP driver)
  data/   models.dart (model + query) · auth.dart (login, sesi, kelola user)
  ui/     theme (token warna/font + ThemeController), widgets (RowItem, Panel,
          PageScaffold, AppScrollBehavior), fmt, forms, finance (buku kas),
          halaman per fitur
api/sql.js                  Satu-satunya pintu SQL (role terbatas)
api/_guard.js               Filter statement + pengikat parameter `@nama`
api/_guard.test.mjs         Uji filter & parameter (node --test)
api/_app-queries.test.mjs   Semua query app harus lolos filter untuk role yang berhak
api/auth.js                 Login, register admin pertama, kelola user
api/_auth.js                Terbit/verifikasi token HMAC
db/schema.sql               Schema Neon
design/                     catatan desain + mock server & preview (dev saja)
lib/preview_main.dart       entrypoint preview tanpa DB (dev saja)
scripts/init-db.mjs         Jalankan schema (npm run db:init)
scripts/harden-db.mjs       Buat role app_web + uji batas akses (npm run db:harden)
scripts/security-check.mjs  Uji endpoint live (npm run check:live)
.github/workflows/build.yml Build APK otomatis
```

## Tes

```bash
npm test                 # filter SQL, pengikat parameter, semua query app
flutter analyze          # wajib bersih
flutter test             # unit: format, round-robin, klasemen, buku kas
npm run check:live       # endpoint produksi; butuh ADMIN_USER/ADMIN_PASS
```

`check:live` membuat akun member sementara, menguji batas baca/tulis, lalu
menghapusnya lagi. Jalankan setelah deploy, bukan di CI biasa (menyentuh data
produksi).

## CI/CD

- Push ke `main` → APK jadi artifact di tab **Actions**.
- Push tag `v*` → APK otomatis masuk **Releases**:
  ```bash
  git tag v1.0.3 && git push origin v1.0.3
  ```

## Keamanan

| Lapis | Isi |
|---|---|
| Login | Password di-hash bcrypt oleh Postgres (`pgcrypto`), 6–200 karakter, username maks 40 |
| Sesi | Token HMAC-SHA256, berlaku 12 jam, ditandatangani `AUTH_SECRET`; token ditolak → app otomatis kembali ke layar masuk |
| Kunci akun | 5× salah password → terkunci 10 menit; maks 30 percobaan / 5 menit per IP |
| Jalur data | Semua query lewat `/api/sql`, wajib `Authorization: Bearer <token>` |
| Role DB | `app_web`: tanpa DDL, tanpa akses `password_hash` (dibuat `npm run db:harden`) |
| Filter query | Satu statement, hanya SELECT/INSERT/UPDATE/DELETE/WITH; komentar & string dinormalisasi dulu, target tulis harus terbaca, `users` hanya lewat `/api/auth`; `member` read-only dan tidak bisa membaca daftar pengguna |
| Parameter | `@nama` → positional hanya di luar string/komentar; parameter yang tidak dikirim ditolak (bukan NULL diam-diam) |
| Kelola user | Tambah/reset/hapus hanya lewat `/api/auth` (admin), bukan lewat SQL |
| Header | CSP, HSTS, `X-Frame-Options: DENY`, `nosniff`, `Referrer-Policy: no-referrer` |

APK tidak lagi menyimpan connection string Neon — kredensial DB hanya ada di env
server. `APP_KEY` lama sudah tidak dipakai.

Belum ada: reset password via email, 2FA, dan rate limit lintas instance
(penghitung per instance). Tambahkan kalau app dipakai di luar klub sendiri.
