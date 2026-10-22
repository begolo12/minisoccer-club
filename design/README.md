# Design notes

Arah visual app: **Papan skor** — papan LED stadion, bukan dashboard SaaS.

## Keputusan

| Hal | Nilai |
|---|---|
| Font angka/skor | Barlow Condensed, tabular, tracking positif |
| Font teks | Inter |
| Dasar gelap | `#080B09` · kartu `#0E1512` · garis `#202C25` |
| Dasar terang | `#F2F5F1` · kartu `#FFFFFF` · garis `#D8E0D9` |
| Aksen | hijau lapangan `#35D07F` (gelap) / `#0E7C48` (terang) |
| Uang | amber `#F5B841` / `#8A5A00` |
| Tunggakan & kalah | merah `#FF5A5A` / `#B3261E` |
| Permukaan | datar + garis rambut. Tanpa gradien dekoratif, tanpa bayangan |
| Daftar | baris ber-garis (`RowItem`), bukan kartu bertumpuk |
| Label bagian | huruf besar kecil + garis sampai tepi kanan (`SectionTitle`) |
| Desktop ≥900px | rail kiri 216px + isi maks 980px, dua kolom di beranda |
| HP | bottom nav, satu kolom |

Token ada di `lib/ui/theme.dart` (`AppThemes`). Warna yang bergantung mode
dipakai lewat `AppThemes.money(context)` dan `AppThemes.bad(context)` supaya
kontras tetap lolos di tema terang.

## Tooling preview (tidak ikut deploy)

Tanpa database, UI bisa dilihat lewat backend tiruan:

```bash
flutter build web --release -t lib/preview_main.dart -o build/preview
node design/mock/server.mjs            # http://localhost:8099
```

Parameter URL:

- `?tab=0..4` — tab awal (beranda, tanding, tim, iuran, lainnya)
- `?page=members|bookings|finance|announcements|stats|users|settings|tournaments|team|match|tournament`
- `?theme=light|dark`
- `?login=1` — tampilkan layar masuk, bukan langsung sebagai admin
- `?role=member|treasurer` — lihat tampilan tanpa hak tulis (tombol tulis
  harus hilang)

`design/mock/check.mjs <url> <lebar> <tinggi> <keluaran.png>` mengambil
screenshot lewat Chrome DevTools Protocol dan mencetak error console.

`lib/preview_main.dart` hanya entrypoint untuk tooling di atas; build
produksi tetap `lib/main.dart`. `design/` tidak diunggah ke Vercel
(diatur `.vercelignore`).

Mock server menyajikan data yang bentuknya sama dengan query asli (nama tim
di `matches`, `v_team_standings`, `tournament_teams.group_no`, 31 anggota
dalam 4 tim) supaya preview tidak menampilkan "0 tim" atau "—". Tulis yang
didukung: transaksi, iuran, booking, pengumuman, skor turnamen, dan pemain
per tim — cukup untuk mencoba alur simpan/hapus tanpa DB.

## Komponen bersama (`lib/ui/widgets.dart`)

Satu implementasi per pola, supaya halaman tidak menyimpang:

| Komponen | Dipakai di |
|---|---|
| `StatStrip` + `StatTile` | Beranda, Tanding, Tim, Iuran, Kas, Statistik, Turnamen, Booking |
| `StandingsTable` | Beranda (rail), Tanding, Tim, Turnamen, Statistik |
| `MatchRow` | Beranda, Tanding, Tim (riwayat) |
| `PeriodChips` + `recentPeriods()` | Iuran, Kas |
| `TagChip` | Turnamen (pemain per tim) |
| `RowItem`, `SectionTitle`, `Panel`, `Pill` | semua halaman |

`StandingsTable` memilih kolom berdasarkan lebar **wadah** (`LayoutBuilder`),
bukan lebar layar — di rail desktop tabel tetap ringkas (M/SG/Poin) walau
jendelanya lebar.

## Bukti

`design/current/` — tangkapan layar 390x844 (1440x900 untuk beranda, login,
turnamen, kas; 320x800 untuk cek layar sempit) dari semua halaman:
`beranda-hp`, `beranda-320`, `beranda-desktop`,
`beranda-terang`, `anggota`, `anggota-terang`, `anggota-member`, `tanding`, `iuran`, `iuran-terang`, `lainnya`,
`login-hp`, `login-desktop`, `detail-laga`, `detail-turnamen`,
`detail-turnamen-desktop`, `turnamen-desktop`, `statistik`, `pengguna`,
`booking`, `kas`, `kas-terang`, `kas-desktop`, `pengumuman`, `pengaturan`,
`tim-detail`.

## Catatan ronde review

Dua ronde review visual independen (7/10 lalu 7/10). Yang sudah diperbaiki:

- label statistik terpotong di HP; angka pakai font sempit + `FittedBox`
- baris terakhir tertutup bottom nav (padding bawah 28)
- garis hiasan nyasar di kartu laga; judul laga kini `vs` kecil + nama lawan
- aksi cepat tiga kolom tetap, tidak ada tombol menggantung
- tag hasil seragam `MENANG/SERI/KALAH` di beranda dan tanding
- skor selalu di kiri baris (satu urutan baca)
- iuran: total pakai amber, chip belum bayar pakai tanda centang
- pengguna: role bahasa Indonesia, tanpa baris ganda
- klasemen: tabel ringkas di HP (M/SG/Poin), penuh di layar lebar
- pengumuman, booking, jadwal turnamen: baris bergaris, bukan kartu bertumpuk
- kontras tema terang: hijau `#0A7D43`, amber `#7A5C00`

Ronde ketiga (perbaikan menyeluruh):

- klasemen yang tadinya disalin di tiga halaman jadi satu `StandingsTable`
- panel angka yang tadinya disalin di lima halaman jadi satu `StatStrip`
- deret chip periode dan baris laga juga disatukan
- beranda: laga berjalan/skor di papan, "Jadwal berikutnya" terpisah dari
  "Hasil terakhir" (dulu laga terjadwal ikut muncul sebagai hasil)
- beranda rail: mini klasemen dan booking berikutnya, bukan hanya top skor
- Tim: status kurang pemain netral (bukan merah); merah khusus gagal/tunggakan
- Iuran: nominal kurang dihitung dari iuran standar, chip belum bayar bisa
  diketuk untuk langsung mencatat
- Kas: keterangan transaksi tidak lagi mengulang judul
- Booking: dipisah "Akan datang" dan "Riwayat", tanggal pendek di kolom kiri
- Statistik: satu strip ringkasan, pencetak gol dengan batang proporsional,
  plus klasemen
- Lainnya: dikelompokkan (Kelola klub / Kompetisi / Informasi / Akun) dengan
  kartu akun di atas
- Beranda menyapa nama akun yang masuk, bukan "Klub" statis
- Tanding: strip angka jadi tiga tile (Main/Gol/Selisih), tidak lagi lima
  kolom sempit berdesakan
- Turnamen: ringkasan jumlah turnamen + status ber-pil di tiap baris, dan
  lama laga per pertandingan di subjudul
- Booking: kartu "Berikutnya" pakai tanggal pendek supaya tidak melipat
- Preview: rute `?page=members` ditambahkan; mock memperbaiki query catatan
  laga yang tertukar dengan query pencetak gol (dulu tampil "Gagal memuat")

Diketahui belum: tombol kembali tidak muncul saat halaman dibuka langsung
lewat `?page=` (memang tidak ditumpuk); di app normal halaman itu selalu
ditumpuk jadi tombolnya ada.

`design/ref/` — pembanding (FotMob, SofaScore) yang dipakai saat memilih arah.

## Ronde beranda berbasis turnamen

Beranda dulu menampilkan dua daftar laga ("jadwal berikutnya" dan "hasil
terakhir") sehingga tampilan luar terasa seperti daftar pertandingan, bukan
ringkasan klub. Sekarang:

- **Laga berjalan** tetap satu-satunya papan skor di beranda, dan hanya kalau
  ada laga `ongoing`. Kalau tidak, tempatnya diisi hero **turnamen berikutnya**
  (nama, lapangan, hitung mundur, tombol "Lihat turnamen").
- **Turnamen berikutnya** tampil sebagai baris ringkas kalau papan skor laga
  sedang dipakai; turnamen yang sedang berjalan tidak diulang di sini.
- **Turnamen terakhir** = yang berjalan, atau yang paling baru selesai (draft
  tidak dihitung — belum ada hasil). Kartunya tertutup: status, tanggal,
  lapangan, dan progres "4/6 laga". Hasil per pertandingan baru muncul setelah
  diketuk, dengan tautan ke detail turnamen.
- Daftar laga individual tidak lagi ada di beranda; laga dibaca di Tanding
  atau di dalam turnamen.

Kartu turnamen memakai `gen` (penghitung reload) supaya daftar hasil tidak
basi setelah skor diubah di halaman lain.

Kartu tertutup diberi label kecil "Hasil" di samping chevron (disembunyikan di
bawah 360px supaya nama turnamen tetap utuh), karena chevron saja tidak
terbaca sebagai "ketuk untuk melihat hasil".

## Ronde status turnamen

Status turnamen sebelumnya hanya naik satu arah (`draft` → `running` saat skor
pertama diisi) dan tidak pernah menjadi `selesai`. Sekarang
`Tournament.syncStatus` dijalankan setiap skor disimpan atau dihapus, dan
menurunkan status dari isi jadwal:

| Kondisi laga | Status |
|---|---|
| semua masih kosong | `draft` |
| sebagian terisi | `running` |
| semua terisi | `done` |

Tanpa ini turnamen yang sudah habis tetap tertulis "BERJALAN" selamanya dan
tidak pernah muncul sebagai "Turnamen terakhir" yang selesai. Label "Selesai"
di detail juga dihitung dari hasil laga, bukan dari objek turnamen yang dibuka
halaman itu, supaya berubah begitu laga terakhir diisi.

Daftar turnamen diurutkan menurut yang sedang dibutuhkan: berjalan dulu, lalu
yang akan datang (terdekat), lalu yang selesai (terbaru). Urutan tanggal
menaruh draft paling depan karena jadwalnya paling akhir.

## Ronde pembersihan 320px & status selesai

- **Turnamen selesai tetap hijau.** Warna status di beranda dan daftar turnamen
  dulu hanya hijau untuk `running`; yang `done` ikut abu-abu, jadi kartu
  "Turnamen terakhir" yang penuh hasil terlihat nonaktif dan bar progresnya
  kehilangan warna di 100%. Sekarang abu-abu khusus `draft`.
- **Riwayat laga tim bukan tempat laga terjadwal.** Detail tim memisahkan
  "Laga berikutnya" (urut terdekat) dari "Riwayat laga" (selesai). Sebelumnya
  baris "AKAN DATANG" muncul di bawah judul "Riwayat laga".
- **Role tidak diulang.** Kartu akun di Lainnya dan Pengaturan menulis role dua
  kali (subjudul + label kanan) dan melipat dua baris di 320px. Subjudul kini
  menjelaskan hak aksesnya saja ("Bisa mengubah data" / "Hanya membaca").
- **Preview punya rute `?page=team`** supaya detail tim bisa di-screenshot
  seperti halaman lain.

## Ronde kas klub

Halaman `Kas klub` menyatukan iuran (`payments`) dan transaksi manual
(`transactions`, sudah ada di schema tapi belum dipakai). Keputusan:

- Dua sumber tetap terpisah di DB; penggabungan dan saldo dihitung di klien
  (`mergeCashLedger`, `CashSummary`) supaya bisa dites tanpa DB.
- Satu ringkasan tiga angka (masuk / keluar / saldo) dengan garis rambut,
  sama seperti strip di beranda — bukan kartu bertumpuk.
- Chip periode: `Semua` di depan, lalu enam bulan terakhir. Bulan kosong
  memakai empty state yang sama dengan halaman lain.
- Baris iuran dan transaksi berbagi satu pola `RowItem`; hanya transaksi
  manual yang punya tombol hapus, karena iuran dikelola di halaman Iuran.
  Slot tombol tetap disediakan walau baris tidak punya aksi, supaya kolom
  nominal rata di semua baris.
- Di periode "Semua", tiap ganti bulan diberi label bulan kecil agar buku kas
  lintas bulan tidak terbaca sebagai satu deret.
- Beranda dapat blok "Kas bulan ini" yang menaut ke halaman ini; admin dan
  bendahara melihat tombol tambah, member hanya membaca (`Auth.canWrite`).

## Ronde kualitas (UI, frontend, backend)

Perbaikan yang mengubah perilaku, bukan hanya tampilan:

- **Tulis mengikuti role di semua layar.** Tombol tambah/hapus/sunting
  disembunyikan untuk `member`; server tetap menolak sebagai lapis kedua.
  Sebelumnya tombolnya tetap muncul dan baru gagal di server.
- **Laga berjalan tidak hilang.** `Match.upcoming()` kini menyertakan status
  `ongoing`, dan daftar Tanding memisahkan "Berlangsung & akan datang" dari
  "Selesai". Tombol beranda membuka detail laga, bukan dialog skor, supaya
  sesi dan catatan gol tetap bisa diisi.
- **Nominal iuran tidak lagi ditulis mati.** Form iuran terisi dari nominal
  yang paling sering dibayar (`Payment.standardAmount`), dan label tunggakan
  di beranda memakai angka yang sama; tanpa riwayat, label jadi "Belum bayar".
- **Hitungan lunas benar.** Angka "Lunas" memakai anggota aktif yang belum
  bayar, bukan jumlah baris pembayaran (yang bisa melebihi jumlah anggota
  kalau ada catatan ganda).
- **Sesi habis kembali ke login.** Token yang ditolak (`401`) memicu logout
  lokal lewat `Db.onSessionExpired`, bukan error di tiap halaman.
- **Jaringan buruk tidak menggantung.** Semua permintaan punya batas 20 detik
  dan pesan Indonesia; layar bootstrap punya tombol coba lagi + keluar akun.
- **Tema langsung berubah.** `ThemeController` mengganti `themeMode` tanpa
  membuka ulang app; manifest dan latar `index.html` memakai warna dasar gelap
  yang sama supaya tidak ada kilatan putih saat web dimuat.
- **Tab dimuat saat dibuka.** `HomeShell` hanya membangun tab yang pernah
  dibuka, lalu memuat ulang tab itu kalau ada tulisan sejak terakhir dilihat.
- **Aksi cepat tidak meluber di 320px.** Kisi tiga kolom memakai `Expanded`,
  jadi lebar tombol selalu pas; label panjang dipotong dengan elipsis.
- **Daftar pendek tetap bisa ditarik.** `AppScrollBehavior` memaksa
  `AlwaysScrollableScrollPhysics`, jadi pull-to-refresh bekerja di halaman
  yang baru berisi satu baris.
- **Input lebih aman.** Username/password punya batas panjang di server,
  body `/api/auth` dibatasi 8 KB, dan `Retry-After` dikirim saat dibatasi.
- **Filter SQL diuji.** `api/_guard.js` menormalkan komentar dan string dulu,
  menolak tulis tanpa target yang terbaca, menolak `public.users`, dan
  mengikat parameter hanya di luar string. `api/_guard.test.mjs` menguji
  filter & pengikat, `api/_app-queries.test.mjs` memastikan semua query yang
  dipakai app tetap lolos untuk role yang berhak (17 tes).

## Ronde tombol "Selesai pertandingan"

Masalahnya bukan kurang tombol, tapi alurnya tidak terbaca: menyelesaikan laga
harus lewat detail laga, dan skor diisi lewat keyboard angka. Sekarang satu
alur yang sama dipakai di tiga tempat.

- **Satu dialog skor untuk laga internal dan turnamen.** `showFinishMatch`
  (internal) dan `showScoreForm` (turnamen) memakai `ScoreStepper` dari
  `widgets.dart`: nama tim, tombol −, angka besar, tombol +, bertumpuk dua
  baris. Tombol − nonaktif saat skor 0 tetapi tetap bergaris, supaya tidak
  terbaca sebagai tombol rusak.
- **Akibat skor terlihat sebelum disimpan.** Dialog menampilkan
  `scoreOutcome(...)` — "Tim D menang 2–0 · 3 poin" — plus aturan poin
  (menang 3, seri 1, kalah 0). Jadi poin klasemen bukan hal yang baru
  ditemukan setelah menekan simpan.
- **Tombol langsung di baris.** `MatchRow.onFinish` memasang tombol
  "Selesai" di samping label status pada baris laga yang belum selesai
  (Tanding), dan baris jadwal turnamen mendapat tombol centang 30px.
  Setelah tersimpan muncul toast "Hasil tersimpan · poin klasemen diperbarui";
  toast dikirim sebelum reload karena reload membuang context baris.
- **Kartu papan skor beranda.** Tombol "Isi hasil" yang hanya membuka detail
  diganti dua tombol: "Selesai" (dialog skor) dan "Detail".
- **Skor berjalan tampil di baris.** Laga `ongoing` sekarang menampilkan skor
  sementaranya di kolom kiri `MatchRow` dan di header detail, bukan ikon jam
  dan "VS" — skor yang akan dikunci harus terbaca sebelum dikunci.
- **Hasil selesai menyebut poinnya.** Label baris jadi
  `TIM C MENANG · 3 POIN`, menyambung klasemen di halaman yang sama.
- **Mock backend ikut bisa menyelesaikan laga.** `design/mock/server.mjs`
  menangani `insert/update/delete matches`, `match_sessions`, dan sinkronisasi
  total sesi, jadi alur Selesai bisa diuji penuh tanpa DB.

## Ronde audit logika (E2E)

`design/mock/e2e.mjs` menjalankan SQL yang sama dengan app ke mock backend
(`node design/mock/e2e.mjs`, 27 pemeriksaan). Yang ditemukan dan diperbaiki:

| Bug | Akibat sebelumnya | Perbaikan |
|---|---|---|
| `Match.finish` menimpa total sesi | Laga 3–1 dari dua sesi bisa dikunci jadi 0–0 lewat dialog | Skor akhir = jumlah sesi kalau sesi ada; dialog menampilkan skor sesi sebagai read-only |
| `winnerPoints` = 0 untuk kemenangan away | Baris hasil menulis "TIM B MENANG · 0 POIN" | Diganti `pointsForWinner` (3/1) |
| `Standing.compute` menghitung laga non-`done` | Skor data lama menaikkan poin padahal UI menulis "vs" | Hanya laga `done`, sama seperti `v_standings` |
| `_syncTotals` mengosongkan skor ke 0–0 | Hapus sesi terakhir menghapus hasil laga selesai | Laga selesai mempertahankan hasil; laga lain direset dan kembali `scheduled` |
| `Match.upcoming` menyaring `ongoing` lama | Laga berjalan >3 jam hilang dari beranda | `ongoing` selalu ikut, hanya `scheduled` yang dibatasi 3 jam |
| Detail laga memakai objek lama | Skor di header tidak berubah setelah sesi ditambah | `Match.byId` dimuat ulang tiap reload; header memakai `_match` |
| Halaman tim membaca `goalsFor` mentah | Skor dan M/S/K terbalik untuk laga away | `MatchRow.forTeamId`, `goalsForTeam/goalsAgainstTeam` |
| Tim dihapus → nama "Tim A"/"Tim B" | Nama tim palsu di riwayat | Fallback "Tim dihapus" |
| Turnamen: estimasi laga pakai rata-rata grup | 5 tim / 2 grup tertulis 2 laga (aslinya 4) | Ukuran grup snake dihitung per grup; jeda dihitung (laga−1) |
| Turnamen: grup boleh berisi 1 tim | Jadwal dibuat tanpa laga | `groupCap` (min 2 tim/grup) dan tombol Buat menolak 0 laga |
| Statistik klub menampilkan "M/S/K" | Semua laga klub-vs-klub, jadi selalu ada pemenang | Diganti "Main / Gol (per laga) / Seri %" |
| Total gol = `goals_for` saja | Setengah gol hilang (gol tim away tidak dihitung) | Total = `goals_for + goals_against` |
| Iuran bisa dicatat dua kali | Kas dan label "Lunas" terhitung ganda | `Payment.existsFor` dicek sebelum simpan + form hanya anggota aktif |
| Tidak ada jalan membatalkan hasil | Salah tekan 0–0 permanen | Aksi "Buka lagi" di dialog hasil (`Match.reopen`) |
| Hapus anggota: pesan salah | Ditulis "catatan pertandingan ikut terhapus" (sebenarnya tidak) | Pesan menyebut iuran ikut terhapus, catatan gol jadi tanpa nama |

Pemeriksaan tetap: `flutter test` (17 tes) untuk `Standing.compute`,
`pointsForWinner`, sudut pandang tim, `groupCap`, round-robin per grup;
`npm test` (18 tes) untuk guard SQL — termasuk query baru `matchById`,
`paymentExists`, `reopenMatch`, `syncTotals` versi baru.

## Ronde audit backend & izin DB

Audit kali ini fokus ke jalur nyata (Vercel + Neon), bukan UI:

- **`app_web` tidak punya izin `tournament_teams` dan `v_team_standings`.**
  `scripts/harden-db.mjs` hanya meng-grant daftar tabel lama, sedangkan app
  sudah memakai keduanya → `permission denied` di Neon untuk halaman Tim,
  Turnamen, dan klasemen. Daftar grant kini satu sumber di
  `scripts/_grants.mjs`, dan `api/_app-queries.test.mjs` menolak build kalau
  ada tabel/view yang dipakai app tapi belum di-grant (diuji dengan
  menghapus `tournament_teams` dari daftar: tes langsung merah).
- **Fallback koneksi owner tidak bersuara.** `api/sql.js` memakai
  `DATABASE_URL_WEB || DATABASE_URL`; kalau variabel pertama lupa dipasang,
  app tetap jalan dengan hak owner. Sekarang ada `console.warn` di log.
- **Body `/api/sql` tidak dibatasi.** Sekarang 128 KB, dicek setelah token
  (permintaan tanpa token tidak diproses lebih jauh).
- **Hapus tim tidak menghitung ulang status turnamen.** `ON DELETE CASCADE`
  membuang jadwal turnamen, tapi turnamen bisa tetap tertulis "Selesai".
  `Team.delete` sekarang menyimpan daftar turnamen terdampak, menghapus, lalu
  `Tournament.syncStatus`; turnamen tanpa laga kembali `draft`.
- **Biaya booking tidak pernah masuk kas.** "Total sewa" di halaman Booking
  dan saldo Kas menghitung dua angka berbeda untuk uang yang sama.
  `transactions.booking_id` (unique, `ON DELETE CASCADE`) menautkan keduanya;
  form booking punya centang "Catat biaya ini ke kas" (default aktif), baris
  booking menulis "sudah di kas"/"belum di kas".
- **Tiga view mati dihapus.** `v_monthly_finance`, `v_player_stats`, dan
  `v_standings` tidak pernah dibaca app (rekap dihitung di Dart); dibiarkan
  berarti dua sumber kebenaran. Schema kini `DROP VIEW IF EXISTS` untuk
  ketiganya, grant tinggal `v_team_standings`.
- **Dead code model dibuang:** `Match.notes` (tidak pernah dibaca/ditulis UI)
  dan `Tournament.setStatus` (status selalu lewat `syncStatus`).

## Ronde perbaikan lanjutan (data lama, papan catat, Lainnya)

- **`npm run db:fix`.** Dua masalah data tidak bisa dibereskan oleh kode saja:
  booking lama yang biayanya belum pernah masuk kas, dan iuran ganda per
  anggota/periode. Skrip ini idempoten (`--dry` untuk pratinjau): membuat
  catatan kas untuk booking berbiaya yang belum tertaut, menyisakan satu
  iuran terbaru per periode, lalu memasang `idx_payments_member_period`.
- **Index unik iuran bersyarat.** `schema.sql` hanya membuat index unik kalau
  data lama sudah bersih (`DO $$ ... RAISE NOTICE ... $$`), supaya `db:init`
  tidak gagal di database yang masih punya duplikat. `splitStatements` di
  `scripts/_neon.mjs` sekarang sadar string, komentar, dan dollar-quote —
  pemecah `;` naif akan memotong blok `DO`.
- **Papan catat laga.** Dialog "Catatan baru" (pilih pemain dari dropdown,
  pilih jenis, isi menit, simpan, ulangi) diganti papan ketuk: satu baris per
  pemain dari kedua tim, empat tombol 34px (gol/assist/kuning/merah), kolom
  menit opsional, dan penghitung "n catatan tersimpan". Dialog tetap terbuka
  supaya rentetan kejadian satu laga selesai dalam satu kali buka.
- **Skor vs catatan dibedakan eksplisit.** Dua gol di daftar catatan tidak
  menggeser papan skor (skor = jumlah sesi). Tanpa keterangan, angka itu
  terbaca seperti bug; sekarang ada satu baris "Catatan pemain
  (gol/assist/kartu). Skor laga tetap dari sesi." di halaman dan di dialog.
- **Halaman Lainnya berisi angka, bukan deskripsi.** Tiap baris kini membawa
  keadaan nyata: "31 aktif", "Berikutnya 22 Okt 20.00", "Saldo Rp 640 rb
  bulan ini", "1 berjalan • 2 tersimpan", "6 laga selesai", "2 terbit •
  terakhir 18 Okt". Datanya satu `Future.wait` (7 query) dan punya
  pull-to-refresh; kalau gagal, subjudul jatuh ke teks statis.
- **Mock ikut bisa mencatat kejadian.** `insert/delete match_events` dan
  pencarian booking tanpa kas ditambahkan supaya papan catat dan `db:fix`
  bisa diuji tanpa DB.

## Ronde edit & koreksi (CRUD yang belum lengkap)

Sampai ronde sebelumnya banyak entitas hanya bisa dibuat dan dihapus. Yang
ditambahkan:

| Entitas | Sebelum | Sekarang |
|---|---|---|
| Jadwal laga | hanya hapus + buat ulang (sesi & catatan ikut hilang) | `Match.update` + ikon pensil di kepala detail; tim hanya bisa diganti selama laga belum selesai |
| Status laga | `ongoing` hanya muncul setelah ada sesi | tombol **Mulai** (`Match.start`) — laga 0–0 bisa tampil di papan skor beranda |
| Tim turnamen | dipilih sekali saat dibuat | ikon **Kelola tim** (`Tournament.updateTeams`) — jadwal dibuat ulang, ditolak kalau sudah ada laga berskor |
| Pengumuman | hapus + tulis ulang | `Announcement.update` + ikon pensil; tanggal terbit tetap |
| Transaksi kas | hapus + catat ulang | `Transaction.update`; baris buku kas bisa diketuk untuk koreksi nominal/kategori/tanggal |
| Skor sesi | keyboard angka | `ScoreStepper` yang sama dengan dialog hasil laga |

Perbaikan lain yang muncul saat verifikasi:

- **Pesan error tanpa prefix kelas.** `errText()` di `lib/ui/fmt.dart` membuang
  `Exception:` / `ApiException:`; toast yang dulu berbunyi
  "Exception: Sudah ada laga dengan skor" sekarang "Sudah ada laga dengan
  skor". Diuji di `widget_test.dart`.
- **Baris aksi laga tidak muat di 320px.** Tombol ikon tambahan dipindah ke
  kepala halaman (`PageScaffold.actions`) dan baris aksi memakai `Wrap`.
- **`e2e.mjs` bisa dijalankan berulang.** Nama entitas diberi cap waktu dan
  setiap bagian membuat datanya sendiri, jadi skrip tidak lagi gagal pada
  run kedua karena sisa data run pertama.
