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

- `?tab=0..4` — tab awal (beranda, anggota, tanding, iuran, lainnya)
- `?page=bookings|announcements|stats|users|settings|tournaments|match|tournament|finance`
- `?theme=light|dark`
- `?login=1` — tampilkan layar masuk, bukan langsung sebagai admin
- `?role=member|treasurer` — lihat tampilan tanpa hak tulis (tombol tulis
  harus hilang)

`design/mock/check.mjs <url> <lebar> <tinggi> <keluaran.png>` mengambil
screenshot lewat Chrome DevTools Protocol dan mencetak error console.

`lib/preview_main.dart` hanya entrypoint untuk tooling di atas; build
produksi tetap `lib/main.dart`. `design/` tidak diunggah ke Vercel
(diatur `.vercelignore`).

## Bukti

`design/current/` — tangkapan layar 390x844 (1440x900 untuk beranda, login,
turnamen, kas; 320x800 untuk cek layar sempit) dari semua halaman:
`beranda-hp`, `beranda-320`, `beranda-desktop`,
`beranda-terang`, `anggota`, `anggota-terang`, `anggota-member`, `tanding`, `iuran`, `iuran-terang`, `lainnya`,
`login-hp`, `login-desktop`, `detail-laga`, `detail-turnamen`,
`detail-turnamen-desktop`, `turnamen-desktop`, `statistik`, `pengguna`,
`booking`, `kas`, `kas-terang`, `kas-desktop`, `pengumuman`, `pengaturan`.

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

Diketahui belum: tombol kembali tidak muncul saat halaman dibuka langsung
lewat `?page=` (memang tidak ditumpuk); di app normal halaman itu selalu
ditumpuk jadi tombolnya ada.

`design/ref/` — pembanding (FotMob, SofaScore) yang dipakai saat memilih arah.

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

