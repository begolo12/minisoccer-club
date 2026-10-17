# Minisoccer Club ⚽

Aplikasi manajemen klub mini soccer — **Flutter** + **shadcn UI** + **Neon Postgres** (database dari Vercel).
Mobile-first, dark & light mode, siap di-install sebagai APK.

## Fitur

| Fitur | Isi |
|---|---|
| **Beranda** | Jadwal terdekat, statistik W/D/L, total iuran bulan ini, aksi cepat, top skor, pengumuman |
| **Anggota** | CRUD pemain (posisi, nomor punggung, HP), pencarian, filter aktif/nonaktif |
| **Tanding** | Jadwal & hasil, detail pertandingan, **sesi/babak dengan pemenang otomatis**, catat gol / assist / kartu per pemain |
| **Iuran** | Catat pembayaran per bulan, siapa yang belum bayar, riwayat, total terkumpul |
| **Booking lapangan** | Jadwal sewa, durasi, biaya, status (dipesan/selesai/batal) |
| **Pengumuman** | Info klub untuk semua anggota |
| **Pengguna** | Daftar akun & role (admin / bendahara / anggota) |
| **Statistik** | Rekap main/menang/draw/kalah, gol, poin, top skor & assist |
| **Pengaturan** | Ganti tema, ganti koneksi database, tes koneksi |

QoL: pull-to-refresh di semua halaman, empty state yang mengarahkan, konfirmasi sebelum hapus,
koneksi database disimpan terenkripsi di HP, tabel dibuat otomatis saat pertama konek.

## Mulai (5 menit)

### 1. Siapkan database Neon

1. Buka [Vercel Dashboard](https://vercel.com/dashboard) → **Storage** → database Neon kamu → **Open in Neon**, atau langsung [console.neon.tech](https://console.neon.tech).
2. Copy **Connection string**, formatnya:
   ```
   postgresql://user:password@ep-xxx.ap-southeast-1.aws.neon.tech/neondb?sslmode=require
   ```

### 2. Install APK di HP

1. Buka tab **Releases** di repo ini: https://github.com/begolo12/minisoccer-club/releases
2. Download `app-release.apk` dari rilis terbaru.
3. Buka file di HP → izinkan "Install unknown apps" untuk aplikasi file manager/browser kamu → Install.

### 3. Hubungkan aplikasi ke Neon

Buka app → tempel connection string → **Hubungkan & siapkan**.
Tabel dibuat otomatis. Selesai — mulai tambah anggota.

> Connection string hanya disimpan di HP kamu (encrypted storage), tidak masuk repo.

## Development

```bash
flutter pub get
flutter run
```

Build APK sendiri:

```bash
flutter build apk --release
# atau isi URL default saat build:
flutter build apk --release --dart-define=NEON_URL="postgresql://..."
```

Tanpa `--dart-define`, app memakai placeholder di `lib/core/config.dart` dan meminta URL lewat layar onboarding.

### Struktur

```
lib/
  core/       config.dart (URL default), db.dart (koneksi + secure storage)
  data/       models.dart (model + semua query SQL)
  ui/         theme, fmt, widgets, forms, dan halaman per fitur
db/schema.sql Schema Neon (juga dijalankan otomatis oleh app)
.github/workflows/build.yml  Build APK otomatis
```

### CI/CD

- Push ke `main` → APK di-build, tersedia sebagai artifact di tab **Actions**.
- Push tag `v*` → APK otomatis diunggah ke **Releases**.
  ```bash
  git tag v1.0.1 && git push origin v1.0.1
  ```

## Web (Vercel)

Browser tidak bisa membuka TCP ke Postgres, jadi versi web memakai satu pintu:
`api/sql.js` (Neon HTTP driver). Kredensial DB tetap di server.

```bash
flutter build web --release --dart-define=APP_KEY=<kunci-rahasia>
vercel --prod
```

- `vercel.json` sudah menunjuk `build/web` sebagai output (build web dijalankan lokal/CI).
- Set env di Vercel → Settings → Environment Variables:
  - `DATABASE_URL` = connection string Neon
  - `APP_KEY` = sama dengan nilai `--dart-define=APP_KEY` di atas (kalau dikosongkan, endpoint terbuka — jangan untuk produksi)
- Endpoint default `API_URL=/api/sql` (same-origin), tidak perlu diubah kalau web dan function satu domain.

## Keamanan

Aplikasi Android konek langsung ke Neon (cocok untuk klub kecil, satu admin).
Versi web lewat `api/sql.js`; function itu menerima SQL mentah, jadi **wajib** set `APP_KEY`
kalau di-deploy publik. Kalau nanti butuh multi-user dengan hak akses per role,
ganti endpoint generik itu dengan endpoint per-fitur.
