# Rencana Perbaikan Minisoccer Club

Dasar: audit kode `lib/core`, `lib/data`, `lib/ui`, `api/`, `db/schema.sql`
pada 2026-10-27. Setiap butir menyebut bukti (berkas:baris) dan cara
memverifikasinya. Status ditandai saat dikerjakan.

## Kondisi awal (terukur)

| Ukuran | Nilai |
|---|---|
| Versi | 1.15.8+45 |
| Tes Flutter | 267 lulus |
| Tes Node | 50 lulus |
| Permintaan HTTP per layar Beranda | 10 (9 paralel + 1 serial) |
| Permintaan HTTP per layar Lainnya | 8 |
| Target ketuk < 44px | 12 pola, puluhan pemakaian |
| `fontSize:` di luar token tema | 76 di 16 berkas |
| Berkas > 800 baris | 6 |
| Kontras gagal AA | `#5F6F65` di `#E7EDE6` = 4,47:1 |

---

## Fase 1 — Integritas data (paling mendesak)

Kerusakan yang tidak terlihat: buku kas klub bisa salah tanpa pesan error.

### 1.1 Tulis idempoten
**Bukti:** timeout 20 s (`lib/core/db_web.dart:15`) dianggap gagal jaringan
(`lib/core/net.dart:28-29`), lalu tulis masuk antrean (`lib/core/db.dart:96`)
padahal server mungkin sudah commit. INSERT tanpa kunci unik
(`announcements`, `bookings`, `transactions`, `matches`, `members`) terduplikasi
saat antrean dikirim.

**Perbaikan:**
- `db/schema.sql`: tabel `applied_writes (write_id TEXT PRIMARY KEY, result JSONB, created_at)`.
- `api/sql.js`: terima `writeId`; kalau sudah ada → balas hasil tersimpan
  (`replayed: true`), jangan jalankan ulang.
- `lib/core/db_web.dart`: kirim `writeId`.
- `lib/core/offline.dart`: item antrean membawa `writeId` tetap.
- Pembersihan berkala (retensi 7 hari) di `db:init` (DELETE saat startup tidak
  diperlukan; cukup indeks waktu + tugas manual `npm run db:purge`).

**Verifikasi:** tes node mengirim SQL yang sama dua kali dengan `writeId` sama →
`rowCount` kedua 0 dan hasil pertama diputar ulang; tes Flutter memalsukan
timeout setelah commit → satu baris, bukan dua.

### 1.2 Daya tahan antrean
**Bukti:** `lib/core/offline.dart:334-405` menyimpan berkas hanya setelah
seluruh loop selesai; app dibunuh di tengah → item terkirim diulang.

**Perbaikan:** hapus item dari antrean + tulis berkas **per item** yang sukses;
backoff eksponensial (5 s → 5 m) supaya `sync()` tidak menahan 20 s di setiap
pindah tab.

**Verifikasi:** tes yang mensimulasikan kegagalan pada item ke-2 lalu memuat
ulang berkas → item ke-1 tidak ada lagi.

### 1.3 Tulis yang ditolak server tidak masuk antrean
**Bukti:** `lib/data/models.dart:1175-1189` menangkap **semua** error pada leg
kas booking, termasuk 403/400, lalu memasukkannya ke antrean → item gagal
permanen dan pesan "dikirim otomatis" menyesatkan.

**Perbaikan:** hanya antrekan bila `Db.isNetworkFailure(e)` atau `Unauthorized`.

### 1.4 Hapus anggota tidak menghapus uang
**Bukti:** `db/schema.sql:132` `payments.member_id … ON DELETE CASCADE`;
`lib/data/models.dart:102` mengirim `DELETE FROM members`. Satu ketukan
menghapus riwayat iuran dan mengubah saldo kas.

**Perbaikan:** hapus hanya bila tidak ada jejak keuangan. Kalau ada, server
menolak dengan pesan jelas, dan UI menawarkan **Nonaktifkan** (kolom `active`
sudah ada). Cek di klien (satu query ringan) + penjaga di database
(`BEFORE DELETE` trigger yang melempar bila ada `payments`/`transactions`).

### 1.5 UPDATE/DELETE yang tidak mengenai baris
**Bukti:** `lib/core/db.dart:112-120` mengembalikan `rowCount`, semua model
mengabaikannya (`models.dart:97-104`). Menyunting baris yang sudah dihapus orang
lain tampak berhasil.

**Perbaikan:** `Db.executeExpect(n)` untuk UPDATE/DELETE; lempar
`StaleRowException` bila 0 baris → UI memuat ulang dan memberi pesan.

### 1.6 Filter bulan memakai index
**Bukti:** `lib/data/models.dart:905-907` `to_char(occurred_at,'YYYY-MM')=@p`
membuat `idx_tx_occurred` tidak terpakai dan batas bulannya beda dengan
`payments.paid_at` yang memakai rentang UTC (`models.dart:537-544`).

**Perbaikan:** ganti ke `occurred_at >= @from AND occurred_at < @to`.

---

## Fase 2 — Keamanan

### 2.1 Pencabutan token
**Bukti:** token HMAC stateless 12 jam (`api/_auth.js:6`); `setActive(false)`
(`api/auth.js:184-207`), ubah role, dan reset password tidak membatalkan token.

**Perbaikan:** kolom `users.token_version`, klaim `v` di token, cek di
`/api/sql` dengan cache proses 60 detik. Naikkan versi pada: ganti/reset
password, nonaktifkan akun, ubah role. Kolom belum ada (deploy lama) → cek
dilewati dengan peringatan di log, supaya urutan deploy tidak mematikan API.

### 2.2 Pagar `/api/sql`
**Bukti:** tidak ada batas laju, batas baris, atau statement timeout
(`api/sql.js:42-95`); tamu boleh SELECT apa pun yang tidak dilarang.

**Perbaikan:** batas laju per IP/token (Map per instance, sama seperti
`api/auth.js`), batas 5.000 baris per jawaban, dan
`ALTER ROLE app_web SET statement_timeout = '8s'` di `scripts/harden-db.mjs`.

### 2.3 Cache per akun, bukan per role
**Bukti:** `lib/core/db.dart:37` + `lib/core/cache.dart:70`. Dua admin di satu
perangkat berbagi cache.

**Perbaikan:** `cacheScope = '<role>:<userId>'`.

### 2.4 Sesi habis tidak menghapus data baca
**Bukti:** `lib/data/auth.dart:137,174` menghapus seluruh cache saat sesi
habis; perangkat tanpa sinyal kehilangan semua data terbaca.

**Perbaikan:** pertahankan cache (hanya antrean dan token yang diurus), mode
baca tetap jalan sampai login lagi. Kunci cache tetap per akun sehingga data
akun lain tidak terbaca.

---

## Fase 3 — Performa

### 3.1 Satu permintaan untuk satu layar
**Bukti:** 1 query = 1 POST (`lib/core/db_web.dart:29-54`). Beranda 10,
Lainnya 8.

**Perbaikan:** `POST /api/sql {queries:[{sql,params}]}` dijalankan paralel di
server, dikembalikan per item (satu item gagal tidak menggagalkan yang lain).
Klien: `Db.queryMany`, dipakai Beranda dan Lainnya. Fallback cache tetap per
item. Kalau batch gagal karena jaringan, perilaku sama seperti sekarang
(cache/antrean per item).

### 3.2 Index
Tambahan: `members(name)`, `payments(paid_at)`, `payments(tournament_id, paid_at DESC)`,
`bookings(starts_at DESC)`, `bookings(status, starts_at)`,
`matches(away_team_id)`, `tournaments(starts_at DESC)`,
`announcements(created_at DESC)`, `tournament_teams(team_id)`.
Buang yang redundan: `idx_payments_member`, `idx_attendance_booking`,
`idx_sessions_match`, `idx_tm_tournament`, `idx_tournament_teams`,
`idx_tx_period` (kolomnya mati).

### 3.3 Query berurutan yang bisa paralel
`bookings.dart:306-315`, `matches.dart:711-713`, `tournament.dart:763-793`,
`tournament.dart:246-253`, `forms.dart:560-573`.

---

## Fase 4 — UX & aksesibilitas

| # | Masalah | Bukti | Perbaikan |
|---|---|---|---|
| 4.1 | Target ketuk < 44px | `widgets.dart:108,1298`, `matches.dart:946,980`, `tournament.dart:583`, `shell.dart:342`, dll. | Naikkan ke 44 (ikon tetap kecil) |
| 4.2 | Kontras teks kecil 4,47:1 | `theme.dart:107` | `mutedForeground` light `#57665D` (≈4,9:1) |
| 4.3 | Kuning kartu 1,53:1 | `matches.dart:596,901` | Token `cardYellow` (`#8A6A00` light / `#FACC15` dark) |
| 4.4 | Tanpa `Semantics(header)` | 0 pemakaian | Judul halaman & bagian |
| 4.5 | Chip terpilih tak diumumkan | `widgets.dart:917` | `Semantics(selected:)`, `button:` |
| 4.6 | Skeleton & error tak diumumkan | `widgets.dart:151,258` | `liveRegion`, `disableAnimations` |
| 4.7 | Back Android membuang isian dialog | `forms.dart:34` dkk. | `PopScope` + konfirmasi |
| 4.8 | "Atur ulang" skor tanpa konfirmasi | `tournament.dart:1111` | Dialog konfirmasi |
| 4.9 | Label hilang setelah mengetik | `forms.dart:93` dkk. | Label persisten |
| 4.10 | Validasi lewat toast 2 detik | `forms.dart:48` dkk. | Pesan inline per field |
| 4.11 | Tanggal/tanggal-picker bahasa Inggris | `main.dart:60` tanpa `flutter_localizations` | Tambah delegasi `id` |
| 4.12 | Error mentah tampil ke pengguna | `widgets.dart:266`, `dashboard.dart:1020` | `errText()` + tombol coba lagi |
| 4.13 | Rel Beranda kosong saat gagal | `dashboard.dart:1354` | Skeleton/`DegradedNotice` |
| 4.14 | Panel akun menelan error jadi "Tidak tertaut" | `users.dart:433` | State gagal + coba lagi |
| 4.15 | Iuran anggota: satu gagal = halaman mati | `member_dues.dart:77` | `soft`/`settle` |
| 4.16 | Jargon Inggris | `vs`, `Username`, `password`, `role`, `offline`, `Top skor` | Bahasa Indonesia |

---

## Fase 5 — Verifikasi & dokumentasi

1. `npm test` — tes baru: batch, idempoten, token_version, batas baris.
2. `flutter analyze` — nol isu.
3. `flutter test` — seluruh suite + tes baru (queryMany, hapus anggota, antrean).
4. `flutter build web --release` — smoke build.
5. `npm run check:schema` — schema produksi cocok setelah `db:init`.
6. README + PLAN diperbarui; versi dinaikkan.

## Status pelaksanaan (2026-10-27)

| Fase | Bukti |
|---|---|
| 1.1 Tulis idempoten | `applied_writes` + `writeId` di klien/antrean; `api/sql.test.mjs` 12 tes (tulis sama hanya sekali) |
| 1.2 Antrean tahan mati | item dikeluarkan + disimpan per item; backoff 5 s → 5 m |
| 1.3 Tulis ditolak tidak diantrekan | `Booking.insert` hanya mengantrekan kegagalan jaringan/sesi; tes diperbarui |
| 1.4 Hapus anggota | trigger `members_protect_finance` (diuji: `DELETE` ditolak, transaksi rollback) + UI menawarkan Nonaktifkan |
| 1.5 Baris hilang | `Db.executeExpect` → `StaleRowException` |
| 1.6 Filter bulan | rentang `occurred_at`, index terpakai |
| 2.1 Pencabutan sesi | `users.token_version` + cek 60 detik; tes 401 untuk versi lama/nonaktif |
| 2.2 Pagar `/api/sql` | 24 query/permintaan, 5.000 baris, batas laju, `statement_timeout=8s` pada role |
| 2.3–2.4 Cache | scope per akun; cache tidak dibuang saat logout |
| 3.1 Batch | `{queries:[…]}` + penggabungan 6 ms di klien; tes: 3 query = 1 permintaan |
| 3.2 Index | 13 index baru, 6 index mati dibuang — terverifikasi di DB |
| 3.3 Paralelisasi | Beranda/Lainnya/Iuran/Sewa/Turnamen |
| 4.1–4.6 Aksesibilitas | target 44px, kontras 5,1:1, `Semantics` header/selected/liveRegion, guard dialog, konfirmasi reset skor |
| 4.11 Lokalisasi | `flutter_localizations` (id) untuk date/time picker |
| 4.12–4.15 Error state | `errText`, skeleton/degraded notice, panel akun, iuran anggota |
| 4.16 Bahasa | jargon (`vs`, `Username`, `password`, `offline`, `CSV`, `Top skor`, `Installer`) diganti |
| 4.9–4.10 Form | validasi inline + label persisten lewat widget bersama `FieldLabel`; semua dialog isian (anggota, laga, iuran, transaksi, sewa, pengumuman, akun, turnamen, kata sandi) |
| 4.1 Tombol teks | `visualDensity: VisualDensity.standard` — tema memasang density compact yang diam-diam memotong 8px dari `minimumSize` 44 (tombol "Masuk" di bilah mode publik terukur 36px) |
| 2.3b Cache web | localStorage dibatasi 400 entri / 3 juta karakter; entri tertua dibuang, dan saat kuota penuh tulisan dicoba sekali lagi setelah dipangkas |
| Integrasi main | jejak audit (`audit_log`) tetap tercatat di jalur batch/idempoten; `auth_throttle` membatasi login lintas instance; `showEditorDialog` jadi satu pemilik PopScope; `/api/health` publik |

**Verifikasi terakhir**

```
npm test                 65 lulus
flutter analyze          No issues found
flutter test             282 lulus
flutter build web        sukses (release, no-cdn)
db:init                  dua kali berturut-turut, 92 statement (idempoten)
check:schema             Schema produksi cocok
check:secrets            tidak ada kredensial (termasuk riwayat git)
CI Build APK             sukses untuk 6bdda00 (run 125) dan 2dac02b (run 126):
                         secret scan, 65 tes Node, analyze, 282 tes Flutter,
                         2 APK (universal + per-ABI), verifikasi sertifikat
visual sweep (3 ukuran)  52/52 (build pra-label) • hp 19/20 sesudahnya, satu-
                         satunya fail = tap target "Semua", lalu diperbaiki dan
                         diverifikasi 0 target kecil di Chrome + 2 widget test
potret dialog 320×640    label persisten tampil, dialog tidak meluber
```

Catatan integrasi: main bergerak selama pekerjaan ini (perbaikan login 500,
jejak audit, health, pengingat iuran, navigasi shell, penjaga Back/Batal form,
rilis 1.15.9). Dua merge commit menggabungkan keduanya — bukan memilih salah
satu: audit tetap tercatat di jalur batch/idempoten, PopScope tunggal milik
`showEditorDialog`, minimum kata sandi 8 karakter dari main dengan teks
Indonesia, dan `db:init` diperbaiki agar idempoten pada database yang kolom
`transactions.period`-nya sudah dihapus.

CATATAN lingkungan: `ADMIN_PASS` di `.env` tidak lagi cocok dengan akun admin
produksi (kemungkinan dirotasi di luar sesi ini). Semua pemeriksaan yang butuh
login admin (`check:visual`, `check:features`, `check:e2e`) harus dijalankan
ulang setelah `.env` diperbarui; tidak ada perubahan aplikasi yang bergantung
padanya.

## Yang sengaja tidak dikerjakan

| Hal | Alasan |
|---|---|
| Push notification | Butuh Firebase + izin OS; nilai rendah untuk 20 anggota — pengingat iuran sudah bisa disalin ke WhatsApp |
| Reset password lewat email | Klub tidak punya domain email; admin sudah bisa setel ulang dan menyalinnya sekali |
| 2FA | Melebihi kebutuhan klub; menambah friksi harian |
| Pindah dari `/api/sql` ke RPC per fitur | Guard + grant kolom sudah membatasi; migrasi besar tanpa manfaat langsung |
| State management baru (Riverpod/Bloc) | `setState` + `ValueNotifier` cukup; menambah dependensi justru menambah berat APK |