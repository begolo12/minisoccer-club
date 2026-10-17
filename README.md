# Minisoccer Club ⚽

Aplikasi manajemen klub mini soccer: **Flutter** + **shadcn UI** + **Neon Postgres** (database dari Vercel).
Mobile-first, dark & light mode, plus versi web.

## 📲 Download APK

**[Download APK terbaru](https://github.com/begolo12/minisoccer-club/releases/latest/download/app-release.apk)**

Versi web: **https://minisoccer-club.vercel.app**

1. Buka link di HP → download.
2. Buka file → izinkan "Install unknown apps" untuk browser/file manager → **Install**.
3. Buka app → tempel **connection string Neon** → **Hubungkan & siapkan**.
   Tabel dibuat otomatis, tidak perlu SQL manual.

## Fitur

| Fitur | Isi |
|---|---|
| **Beranda** | Jadwal terdekat, W/D/L, iuran bulan ini, aksi cepat, top skor, pengumuman |
| **Anggota** | CRUD pemain (posisi, nomor punggung, HP), cari, filter aktif/nonaktif |
| **Tanding** | Jadwal & hasil, sesi/babak dengan pemenang tiap sesi, catat gol / assist / kartu |
| **Iuran** | Bayar per bulan, siapa yang belum, riwayat, total terkumpul |
| **Booking lapangan** | Jadwal sewa, durasi, biaya, status |
| **Pengumuman** | Info klub untuk anggota |
| **Statistik** | Main/menang/draw/kalah, gol, poin, top skor & assist |
| **Pengguna** | Akun + role admin / bendahara / anggota |
| **Pengaturan** | Tema, ganti koneksi DB, tes koneksi |

QoL: pull-to-refresh, empty state yang mengarahkan, konfirmasi hapus, koneksi DB
disimpan terenkripsi di HP, tabel auto-dibuat saat pertama konek, error state + retry.

## Setup database Neon (Vercel)

1. [Vercel Dashboard](https://vercel.com/dashboard) → **Storage** → database Neon → **Open in Neon**
   (atau langsung [console.neon.tech](https://console.neon.tech)).
2. Copy **Connection string**:
   ```
   postgresql://user:password@ep-xxx.ap-southeast-1.aws.neon.tech/neondb?sslmode=require
   ```
3. Tempel di aplikasi saat onboarding. Selesai.

Connection string hanya tersimpan di HP (encrypted), tidak masuk repo.

## Development

```bash
flutter pub get
flutter run                       # Android (konek TCP langsung ke Neon)
flutter build apk --release       # APK
flutter build web --release       # versi web
```

## Deploy versi web (opsional)

Web tidak bisa buka TCP ke Postgres, jadi lewat Vercel Function `api/sql.js` (Neon HTTP driver).

```bash
npm install
cp .env.example .env                 # isi DATABASE_URL + APP_KEY
set -a && . ./.env && set +a
npm run db:init                      # buat tabel di Neon (sekali saja)

npx vercel link                      # sekali saja
npx vercel env add DATABASE_URL production
npx vercel env add APP_KEY production

flutter build web --release --dart-define=APP_KEY=<kunci-yang-sama>
npx vercel --prod
```

Setelah itu, deploy berikutnya cukup lewat GitHub Actions **Deploy Web** (Run workflow).
Isi secret repo: `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID`, `APP_KEY`.

> Tanpa `APP_KEY`, endpoint `/api/sql` menerima SQL dari siapa pun. Wajib diisi untuk produksi.

## Struktur

```
lib/
  core/   config.dart · db.dart (router) · db_io.dart (native) · db_web.dart (web)
  data/   models.dart — model + semua query
  ui/     theme, fmt, widgets, forms, halaman per fitur
api/sql.js                  Proxy SQL untuk versi web (Vercel Function)
db/schema.sql               Schema Neon (juga dijalankan otomatis oleh app)
.github/workflows/build.yml Build APK otomatis
```

## CI/CD

- Push ke `main` → APK jadi artifact di tab **Actions**.
- Push tag `v*` → APK otomatis masuk **Releases**:
  ```bash
  git tag v1.0.3 && git push origin v1.0.3
  ```

## Keamanan

APK konek langsung ke Neon (cocok untuk klub kecil). Versi web memakai proxy
server sehingga kredensial DB tidak pernah dikirim ke browser.
Kalau butuh multi-user dengan hak akses penuh, tambahkan auth di `api/sql.js`.
