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

## Tampilan

| Beranda (desktop) | Tanding |
|---|---|
| ![Beranda](design/current/beranda-desktop.png) | ![Tanding](design/current/tanding.png) |

| Tim & klasemen | Kas klub |
|---|---|
| ![Tim](design/current/tim.png) | ![Kas](design/current/kas.png) |

| Turnamen | Detail laga |
|---|---|
| ![Turnamen](design/current/turnamen.png) | ![Detail laga](design/current/detail-laga.png) |

| Beranda (HP) | Tema terang |
|---|---|
| ![Beranda HP](design/current/beranda-hp.png) | ![Terang](design/current/beranda-terang.png) |

Screenshot lain (30 layar, termasuk lebar 320px dan mode terang) ada di
[`design/current/`](design/current/).

## Fitur

| Fitur | Isi |
|---|---|
| **Beranda** | Sapaan akun, papan skor laga berjalan (kalau ada) atau hero turnamen berikutnya, turnamen terakhir dengan progres laga — hasil per pertandingan dibuka dengan diketuk, ringkasan anggota/main/iuran, kas bulan ini, aksi cepat, pengumuman; di layar lebar ditambah klasemen, top skor, dan sewa lapangan |
| **Tanding** | Laga **internal antar tim klub**: jadwal, sesi/babak dengan pemenang, catat gol/assist/kartu, tombol **Selesai** langsung di baris, klasemen tim (menang 3 / seri 1), riwayat hasil, hasil bisa dibuka lagi |
| **Tim** | Tim klub 7–8 pemain: buat tim, atur pemain, klasemen abadi, riwayat laga per tim |
| **Anggota** | CRUD pemain (posisi, nomor punggung, HP), cari, filter aktif/nonaktif. Ketuk baris untuk membuka rekap per anggota: total sudah dibayar, daftar tunggakan (bisa langsung dicatat), riwayat iuran, dan patungan lapangan. Ikon **Ubah** membuka form edit |
| **Turnamen internal** | Pilih tim klub, bagi ke grup (1–8), jadwal round-robin otomatis per grup, klasemen per grup (menang 3 / seri 1 / kalah 0, GM-GK-SG-poin); status draft/berjalan/selesai mengikuti hasil laga. **Iuran per anggota** diisi per turnamen dan bisa diubah kapan saja |
| **Iuran** | Iuran **per turnamen** (bukan per bulan): pilih turnamen, lihat siapa yang belum bayar (bisa diketuk untuk langsung mencatat), nominal kurang, riwayat. Peserta = anggota dari tim yang ikut turnamen itu, jadi orang yang tidak bermain di turnamen tersebut tidak ikut ditagih |
| **Kas klub** | Buku kas: iuran + pemasukan/pengeluaran (sewa, wasit, konsumsi, perlengkapan, sponsor), saldo per bulan atau semua waktu (dengan pemisah bulan) |
| **Booking lapangan** | Jadwal sewa dipisah "Akan datang" & "Riwayat", durasi, biaya, tandai selesai/batal; biaya sewa bisa langsung dicatat sebagai pengeluaran kas (satu booking = satu catatan kas). Ketuk baris untuk **kehadiran & patungan**: tandai siapa yang main, biaya sewa dibagi rata otomatis (sisa pembulatan dibagikan satu rupiah supaya jumlahnya tetap pas), dan tiap setoran masuk Kas sebagai pemasukan "Patungan lapangan". Membatalkan booking ikut membuang setoran patungannya |
| **Pengumuman** | Info klub untuk anggota |
| **Statistik** | Main/menang/seri/kalah, gol per laga, selisih gol, pencetak gol + assist (5 teratas, sisanya bisa dibuka), klasemen tim |
| **Pengguna** | Akun + role admin / bendahara / anggota |
| **Pengaturan** | Tema terang/gelap (langsung), info server, tes koneksi, keluar |

Poin klasemen hanya dihitung dari laga berstatus selesai; skor laga yang
punya sesi selalu sama dengan jumlah sesinya.

QoL: pull-to-refresh (termasuk daftar pendek), empty state yang mengarahkan,
konfirmasi hapus, error state + retry, skeleton loading, layout menyesuaikan
lebar layar, tema bisa diganti tanpa membuka ulang app, tab dimuat saat dibuka
dan disegarkan setelah ada perubahan data, tombol tulis disembunyikan untuk
role anggota.

Catatan: APK sekarang selalu lewat `/api` (token sesi). Connection string DB
hanya ada di env server, tidak lagi disimpan di HP.

## Mode offline-first

Aplikasi bisa **diisi datanya tanpa internet**, lalu sinkron otomatis saat
tersambung. Data offline diutamakan: antrean lokal dikirim setelah keadaan
cloud, sehingga tulisan lokal menimpa data cloud.

| Keadaan | Perilaku |
|---|---|
| Online | Tulis langsung ke server seperti biasa; hasil baca disimpan ke cache |
| Offline — baca | Pembacaan yang pernah berhasil dikembalikan dari cache |
| Offline — tulis | Tulis masuk antrean, cache ditambal sehingga datanya **langsung terlihat** |
| Kembali online | Antrean dikirim berurutan; cache dibuang supaya pembacaan berikutnya mengambil keadaan server |
| Server menolak | Tulis ditandai gagal (tidak memblokir sisanya), bisa dibuang dari Pengaturan |
| Sesi habis | Antrean **tidak** dibuang — dikirim lagi setelah masuk |

Kapan sinkron dicoba: saat app dibuka, saat app kembali ke depan, saat tab
berpindah, dan dari tombol **Sinkron** di banner atau di Pengaturan → Data
offline.

Banner di atas isi menampilkan jumlah perubahan yang belum terkirim, karena
itulah data yang belum ada di cloud. Pengaturan → **Data offline** menunjukkan
status, tombol sinkron, dan tombol buang antrean.

### Web juga bisa dibuka tanpa jaringan

Flutter 3.47 tidak lagi membuat service worker (opsi `--pwa-strategy` sudah
dihapus), jadi tanpa penanganan khusus, membuka atau memuat ulang halaman saat
jaringan mati hanya menampilkan halaman error browser — padahal antrean
tersimpan di localStorage. `web/sw.js` menutup celah itu:

| Permintaan | Perlakuan |
|---|---|
| Navigasi & aset (canvaskit, `main.dart.js`, font) | cache-first, diperbarui di latar |
| `version.json` | selalu dari jaringan (untuk deteksi pembaruan) |
| `/api/*` | **tidak** disentuh — data klub dikelola aplikasi, bukan cache HTTP |

Daftar berkas yang di-precache dibuat saat build oleh
`scripts/gen-sw-manifest.mjs` (136 berkas), karena pada pemuatan pertama service
worker baru aktif setelah aset selesai dimuat — tanpa precache, aplikasi tidak
bisa start offline.

> **Batasannya jujur:** penambalan cache hanya mengenali bentuk SQL yang
> dipakai app ini. Tulis yang memakai ekspresi SQL (`CASE`, `COALESCE(subquery)`,
> agregat) tidak ditambal — data tampil apa adanya sampai sinkron berhasil.
> Lebih baik menampilkan data lama daripada angka karangan. `INSERT` banyak
> baris (jadwal turnamen) juga tidak ditambal; jadwalnya muncul setelah sinkron.
> Daftar tulis yang sengaja tidak ditambal beserta alasannya ada di
> `test/offline_writes_audit_test.dart`, dan tes itu membaca SQL asli dari
> `.audit/queries.json` — tulis baru yang belum ditangani akan menggagalkannya.

Implementasi: `lib/core/row_patch.dart` (urai SQL + tambal baris),
`lib/core/offline.dart` (antrean + pemetaan id sementara),
`lib/core/cache_*.dart` dan `outbox_store_*.dart` (berkas di Android,
localStorage di web), `web/sw.js` + `scripts/gen-sw-manifest.mjs` (shell offline
di web).

### Cara memverifikasi mode offline

| Perintah | Yang dibuktikan |
|---|---|
| `flutter test` | 222 tes: parser SQL, penambalan cache, urutan sinkron, pemetaan id, default kolom vs skema, semua tulis terklasifikasi, **jalur berkas Android** (`cache_io`/`outbox_store_io`), klasifikasi kegagalan jaringan, input nominal, keamanan sinkron, iuran per turnamen, **dialog yang tetap terbuka saat offline** |
| `npm run check:offline` | Di **Chrome sungguhan** terhadap produksi: login → tambah anggota → matikan jaringan → tambah lagi (langsung terlihat) → tutup app → buka lagi → terkirim otomatis ke database |
| `VIEWPORT=mobile npm run check:offline` | Alur yang sama di layout HP 390×844 (layout yang dipakai APK) |
| `npm run check:sw` | Server statis **dimatikan** lalu halaman dimuat ulang: app Flutter harus tetap jalan dari cache |
| `npm run check:features` | 24 pemeriksaan lintas halaman: setiap tab & halaman terbuka tanpa error, satu tulis nyata tersimpan, tidak ada layout meluber |
| `VIEWPORT=mobile npm run check:features` | Pemeriksaan yang sama di layout HP |
| `npm run check:attendance` | Di **Chrome sungguhan**: booking 300.000 → tandai 3 orang hadir → bagian terbagi tepat 300.000 → tandai setor → muncul di buku kas sebagai pemasukan `patungan` → **putus jaringan** → tulis lagi (antrean) → online → terkirim |
| `npm run check:member-dues` | Di **Chrome sungguhan**: anggota dengan 2 turnamen (1 lunas) → halaman riwayat menampilkan total, tunggakan, dan nominal keduanya |
| `npm run check:dues` | Di **Chrome sungguhan**: tagihan hanya memuat anggota yang ikut turnamen → catat iuran online → **putus jaringan** → catat lagi (masuk antrean, langsung tampak lunas) → online → terkirim ke database |
| `npm run check:match-offline` | Di **Chrome sungguhan**: laga berjalan → **putus jaringan** → tombol Selesai membuka dialog → simpan → antrean → online → laga berstatus `finished` di database |

`test/android_offline_io_test.dart` menjalankan kode Android yang sesungguhnya
(berkas JSON, bukan localStorage) dengan `getApplicationSupportDirectory`
dipalsukan ke direktori sementara — termasuk skenario "app ditutup lalu dibuka
lagi", yang tidak bisa diuji lewat cache memori.

> **Satu batasan yang perlu diketahui:** baris tidak ditambal ke query
> **ringkasan** (`count`, `sum`, `GROUP BY`). Angka ringkasan tidak ikut berubah
> saat baris ditambah, jadi menambal hanya akan menyisipkan baris sampah — mis.
> anggota baru muncul sebagai "pencetak gol" palsu. Untuk query seperti itu
> angkanya baru benar setelah sinkron.

### Yang terjadi saat sinkron gagal

| Kejadian | Perilaku |
|---|---|
| Jaringan mati di tengah sinkron | Berhenti, antrean utuh, dicoba lagi nanti |
| Sesi habis (token 12 jam) | Berhenti, antrean utuh, app minta masuk lagi — bukan diam |
| Server menolak satu tulis | Tulis itu ditandai gagal, sisanya tetap dikirim |
| Baris sudah dihapus di cloud (`UPDATE`/`DELETE` mengenai 0 baris) | Ditandai gagal dengan pesan jelas, **bukan** dilaporkan "terkirim" |
| Induk gagal dikirim (id sementara tanpa id asli) | Anaknya ditandai gagal di klien, tidak pernah dikirim dengan id negatif |
| Sebagian gagal | Cache **tidak** dibuang, supaya data yang baru diisi tidak lenyap dari layar |

Antrean yang gagal bisa dilihat dan dibuang di Pengaturan → Data offline.

## Setup database Neon (Vercel)

1. [Vercel Dashboard](https://vercel.com/dashboard) → **Storage** → database Neon → **Open in Neon**
   (atau langsung [console.neon.tech](https://console.neon.tech)).
2. Copy **Connection string**:
   ```
   postgresql://user:password@ep-xxx.ap-southeast-1.aws.neon.tech/neondb?sslmode=require
   ```
3. Isi `DATABASE_URL` di `.env` lokal dan di env Vercel, lalu jalankan
   `npm run db:init` (schema) dan `npm run db:harden` (role `app_web`).
   `db:harden` mencetak `DATABASE_URL_WEB` — **wajib** dipasang di env Vercel;
   tanpa itu server memakai koneksi owner dan izin tabel (lapis pengaman
   pertama) hilang.
   Daftar tabel/view yang di-grant ada di `scripts/_grants.mjs`; query baru
   yang memakai tabel belum ter-grant akan gagal di `npm test`.
4. Buka app → layar masuk → akun pertama dibuat lewat form **Admin pertama**,
   lalu tambah akun lain dari menu **Pengguna**.

`db:init` aman diulang dan **wajib dijalankan setiap kali `db/schema.sql`
berubah**. `CREATE TABLE IF NOT EXISTS` tidak menyentuh tabel yang sudah ada,
jadi tanpa menjalankannya DB lama tetap memakai kolom warisan (mis.
`matches.opponent NOT NULL`) dan tulis dari app baru gagal — gejalanya
"Gagal memuat data / Query gagal dijalankan" di seluruh halaman.

### Kalau app menampilkan "Gagal memuat data"

Gejala ini berarti query app ditolak server. Urutan diagnosis:

```bash
npm run check:schema     # kolom/tabel/view mana yang hilang di produksi
npm run check:e2e        # jalankan semua query app untuk tiap role (butuh admin)
```

`check:schema` tidak butuh kredensial (lewat endpoint publik) dan menyebut
nama kolom yang kurang. Perbaikannya selalu `npm run db:init` +
`npm run db:harden` dengan `DATABASE_URL` owner, lalu deploy ulang web.
`check:e2e` membuktikan batas hak akses: tamu & anggota hanya baca, admin &
bendahara boleh tulis.

Connection string hanya ada di env server, tidak pernah di HP maupun browser.

## Development

```bash
flutter pub get
npm install
cp .env.example .env              # isi DATABASE_URL, DATABASE_URL_WEB, AUTH_SECRET
npm run dev:api                   # API lokal di :3000 (tanpa `vercel dev`)
flutter run -d chrome --dart-define=API_BASE=http://localhost:3000
flutter run                       # Android, lewat API yang sama
flutter build apk --release --dart-define=API_BASE=https://minisoccer-club.vercel.app
flutter build web --release
```

`npm run dev:api` menjalankan `api/sql.js` dan `api/auth.js` apa adanya dengan
kontrak Vercel (`req.body` sudah di-parse, `res.status().json()`), jadi perilaku
lokal sama dengan produksi — termasuk batas role dan filter query.

## Deploy versi web (opsional)

Web tidak bisa buka TCP ke Postgres, jadi lewat Vercel Function `api/sql.js` (Neon HTTP driver).

```bash
npm install
cp .env.example .env                 # isi DATABASE_URL + AUTH_SECRET
set -a && . ./.env && set +a
npm run db:init                      # schema; ulangi setiap db/schema.sql berubah
npm run db:harden                    # role app_web + izin tabel
DATABASE_URL=... npm run db:fix -- --dry   # lihat data lama yang perlu dirapikan
npm run db:fix                       # booking lama → kas, iuran ganda → satu,
                                     # laga v1 tanpa tim → dihapus

npx vercel link                      # sekali saja
npx vercel env add DATABASE_URL production
npx vercel env add DATABASE_URL_WEB production   # dicetak oleh db:harden
npx vercel env add AUTH_SECRET production        # string acak panjang

flutter build web --release --no-web-resources-cdn
npx vercel --prod
```

`--no-web-resources-cdn` wajib: CSP produksi tidak mengizinkan CanvasKit dari
CDN publik, jadi asetnya harus ikut dibundel.

Setelah itu, deploy berikutnya cukup lewat GitHub Actions **Deploy Web** (Run workflow).
Isi secret repo: `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID`.

> **Login.** Semua akses DB lewat `/api/sql` yang butuh token sesi dari `/api/auth`.
> Password di-hash bcrypt oleh Postgres (`pgcrypto`), bukan disimpan di app.
> Tanpa `AUTH_SECRET`, endpoint menolak semua request — itu memang disengaja.

## Struktur

```
lib/
  core/   api.dart (URL API) · db.dart (akses DB, offline-first) · db_web.dart (HTTP driver)
          cache.dart + cache_io/stub (cache baca) · row_patch.dart (tambal cache setelah tulis)
          offline.dart (antrean tulis) · outbox_store_* (penyimpanan antrean) · net.dart
  data/   models.dart (model + query) · auth.dart (login, sesi, kelola user)
  ui/     theme (token warna/font + ThemeController), widgets (RowItem, Panel,
          StatStrip, StandingsTable, MatchRow, PeriodChips, PageScaffold,
          AppScrollBehavior), fmt, forms, finance (buku kas), halaman per fitur
api/sql.js                  Satu-satunya pintu SQL (role terbatas)
api/_guard.js               Filter statement + pengikat parameter `@nama`
api/_guard.test.mjs         Uji filter & parameter (node --test)
api/_app-queries.test.mjs   Semua query app harus lolos filter untuk role yang berhak
api/auth.js                 Login, register admin pertama, kelola user
api/_auth.js                Terbit/verifikasi token HMAC
db/schema.sql               Schema Neon (idempoten + migrasi dari v1)
design/                     catatan desain + mock server & preview (dev saja)
lib/preview_main.dart       entrypoint preview tanpa DB (dev saja)
scripts/init-db.mjs         Jalankan schema (npm run db:init)
scripts/harden-db.mjs       Buat role app_web + izin tabel (npm run db:harden)
scripts/rotate-db-password.mjs  Ganti password role DB (npm run db:rotate)
scripts/fix-data.mjs        Rapikan data lama (npm run db:fix; idempoten)
scripts/clean-test-data.mjs Hapus sisa data uji (`_uji_`, `_at_`, `_ft_`, …) termasuk booking + patungan (npm run db:clean)
scripts/dev-api.mjs         API lokal tanpa `vercel dev` (npm run dev:api)
scripts/check-schema.mjs    Deteksi schema produksi ketinggalan (npm run check:schema)
scripts/e2e-check.mjs       Semua query app untuk tiap role (npm run check:e2e)
scripts/flow-check.mjs      Alur admin ujung ke ujung (npm run check:flow)
scripts/money-check.mjs     Aturan uang: booking↔kas, iuran unik, poin (npm run check:money)
scripts/audit-queries.mjs   Jalankan SQL ASLI tiap method model (npm run check:audit)
scripts/_sql-probe.mjs      Ubah query tulis jadi probe SELECT (tanpa menulis)
scripts/_app-queries.mjs    Daftar query app — satu sumber untuk tes & e2e
scripts/_grants.mjs         Daftar tabel/view yang boleh diakses app_web
scripts/_neon.mjs           Runner Neon (IPv4 dipaksa) + pemecah statement SQL
scripts/security-check.mjs  Uji endpoint live (npm run check:live)
test/queries_audit_test.dart  Merekam SQL asli dari setiap method model
.github/workflows/build.yml Build APK otomatis
```

## Tes

```bash
npm test                 # filter SQL, pengikat parameter, semua query app
flutter analyze          # wajib bersih
flutter test             # unit: format, uang, round-robin, klasemen, buku kas, soft()
npm run check:schema     # schema produksi vs db/schema.sql (tanpa kredensial)
npm run check:e2e        # semua query app untuk tamu/anggota/bendahara/admin
npm run check:flow       # alur admin: anggota→tim→laga→sesi→klasemen→kas
npm run check:money      # booking↔kas, iuran unik, poin klasemen
npm run check:live       # keamanan endpoint produksi
```

### Audit query (menangkap drift schema)

Daftar query yang disalin manual bisa berbeda dari yang benar-benar dikirim app
— itu persis yang dulu terjadi: `npm test` hijau, produksi gagal. Karena itu
`check:audit` memakai SQL **asli**:

```bash
flutter test test/queries_audit_test.dart   # rekam SQL tiap method model
npm run check:audit                         # jalankan ke server sungguhan
```

Tahap pertama mencegat transport HTTP app, jadi yang terekam adalah string final
setelah interpolasi. Tahap kedua memastikan setiap query lolos filter, semua
parameter `@nama` terkirim, dan tabel/kolomnya ada di DB — tanpa mengeksekusi
tulis apa pun.

`check:e2e`, `check:flow`, `check:money`, dan `check:live` membuat data
sementara, menguji perilaku, lalu menghapusnya lagi. Jalankan setelah deploy,
bukan di CI biasa (menyentuh data produksi).

Kalau salah satu pemeriksaan terhenti di tengah (jaringan putus), sisa baris
ujinya bisa dibersihkan dengan `npm run db:clean` — semua data uji memakai
awalan `_uji_`, `_flow_`, `_money_`, atau `_e2e_`, jadi aman dijalankan
kapan saja dan tidak menyentuh data klub asli.

## CI/CD

- Push ke `main` → APK jadi artifact di tab **Actions**.
- Push tag `v*` → APK otomatis masuk **Releases**:
  ```bash
  git tag v1.8.0 && git push origin v1.8.0
  ```

### Pembaruan aplikasi

| Platform | Perilaku |
|---|---|
| **Web** | Otomatis. Tidak ada yang perlu dipasang: service worker memperbarui berkas di latar, dan versi baru terpakai saat halaman dimuat ulang. |
| **Android** | Otomatis **sampai** tahap pemasangan. Saat app dibuka, versi terbaru diperiksa di latar; kalau ada, muncul tawaran dengan satu tombol **Perbarui sekarang** yang mengunduh APK (dengan progres) lalu membuka installer Android. Ketukan terakhir **"Pasang"** tetap milik pengguna — Android tidak mengizinkan aplikasi biasa memasang APK secara senyap. |

Tawaran hanya muncul **sekali per versi**: menekan "Nanti" tidak memunculkannya
lagi untuk versi itu, tetapi versi berikutnya tetap ditawarkan. Titik hijau di
baris **Pengaturan** (tab Lainnya) tetap ada sebagai jalan masuk manual, dan di
sana tersedia tombol "Cek pembaruan".

Unduhan diverifikasi dengan `sha256` dari GitHub; berkas yang rusak dihapus dan
tidak dipasang. Pemeriksaan dibatasi sekali per 12 jam supaya tidak kena batas
API GitHub (60 permintaan/jam per IP tanpa token).

### Kunci penandatangan APK — jangan sampai hilang

APK rilis ditandatangani kunci tetap yang disimpan di GitHub Secrets
(`KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_PASSWORD`, `KEY_ALIAS`).
Workflow memasangnya ke `android/app/release-keystore.p12` + `android/key.properties`
sebelum build, lalu memverifikasi sertifikatnya di log build.

**Kenapa ini penting:** Android hanya mau memperbarui aplikasi kalau kunci
penandatangannya sama persis. Sebelumnya build memakai kunci *debug* yang dibuat
ulang di setiap runner, jadi setiap APK dari GitHub bersertifikat berbeda —
update selalu ditolak ("Aplikasi tidak terpasang") dan satu-satunya jalan keluar
adalah uninstall, yang **ikut menghapus antrean offline yang belum tersinkron**.

**Kalau kunci hilang:** aplikasi tidak akan pernah bisa di-update lagi. Simpan
salinan `release-keystore.p12` + `key.properties` di minimal dua tempat
terpisah. Keduanya sudah masuk `.gitignore` dan tidak boleh di-commit.

Build lokal tanpa `android/key.properties` tetap jalan, tapi jatuh ke kunci
debug dengan peringatan di log — cukup untuk `flutter run --release`, **tidak**
untuk rilis.

## Keamanan

| Lapis | Isi |
|---|---|
| Login | Password di-hash bcrypt oleh Postgres (`pgcrypto`), 6–200 karakter, username maks 40 |
| Sesi | Token HMAC-SHA256, berlaku 12 jam, ditandatangani `AUTH_SECRET`; token ditolak → app otomatis kembali ke layar masuk |
| Kunci akun | 5× salah password → terkunci 10 menit; maks 30 percobaan / 5 menit per IP |
| Jalur data | Semua query lewat `/api/sql`. **Tamu tanpa token boleh membaca** (mode publik read-only); menulis wajib `Authorization: Bearer <token>` |
| Role DB | `app_web`: tanpa DDL, tanpa akses `password_hash` (dibuat `npm run db:harden`) |
| Filter query | Satu statement, hanya SELECT/INSERT/UPDATE/DELETE/WITH; komentar & string dinormalisasi dulu, target tulis harus terbaca, `users` hanya lewat `/api/auth`; `public`/`member` read-only dan tidak bisa membaca daftar pengguna |
| Parameter | `@nama` → positional hanya di luar string/komentar; parameter yang tidak dikirim ditolak (bukan NULL diam-diam) |
| Kelola user | Tambah/reset/hapus hanya lewat `/api/auth` (admin), bukan lewat SQL |
| Header | CSP, HSTS, `X-Frame-Options: DENY`, `nosniff`, `Referrer-Policy: no-referrer` |

APK tidak lagi menyimpan connection string Neon — kredensial DB hanya ada di env
server. `APP_KEY` lama sudah tidak dipakai.

Belum ada: reset password via email, 2FA, dan rate limit lintas instance
(penghitung per instance). Tambahkan kalau app dipakai di luar klub sendiri.

## Kebersihan repo

Yang **tidak** pernah masuk git (lihat `.gitignore`):

| Kategori | Contoh | Alasan |
|---|---|---|
| Hasil build | `build/`, `.dart_tool/`, `node_modules/` | dibuat ulang tiap build |
| Artefak rilis | `*.apk`, `*.aab` | 60 MB/file; didistribusikan lewat GitHub Releases |
| Kredensial | `.env`, `.env.local`, `*.jks`, `*.keystore`, `*.pem` | rahasia; `.env.example` tetap di-commit sebagai template |
| Artefak kerja | `.audit/`, `.shots/`, `*.tmp` | hasil generate lokal, bisa dibuat ulang |
| Konfigurasi mesin | `.vercel/`, `.idea/`, `.vscode/`, `local.properties` | spesifik tiap developer |

Aturan yang dipakai: **hanya sumber yang dibutuhkan untuk membangun app** yang
di-commit. Kalau ragu, tambahkan ke `.gitignore` dulu — menghapus file dari
riwayat git jauh lebih mahal daripada menambahkannya nanti.

Sebelum commit, cek cepat:

```bash
git status --short              # apa yang akan masuk
git ls-files --others --exclude-standard   # file baru yang belum diabaikan
```

Kalau kredensial sudah terlanjur ter-commit, menghapus filenya **tidak cukup** —
nilainya ada di riwayat. Rotasi dulu (`npm run db:rotate -- <role>`), baru
bersihkan riwayat dan pasang nilai baru di env Vercel.
