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
- `?page=bookings|announcements|stats|users|settings|tournaments|match|tournament`
- `?theme=light|dark`
- `?login=1` — tampilkan layar masuk, bukan langsung sebagai admin

`design/mock/check.mjs <url> <lebar> <tinggi> <keluaran.png>` mengambil
screenshot lewat Chrome DevTools Protocol dan mencetak error console.

`lib/preview_main.dart` hanya entrypoint untuk tooling di atas; build
produksi tetap `lib/main.dart`. `design/` tidak diunggah ke Vercel
(diatur `.vercelignore`).

## Bukti

`design/current/` — tangkapan layar 390x844 (1440x900 untuk beranda, login,
turnamen) dari semua halaman: `beranda-hp`, `beranda-desktop`,
`beranda-terang`, `anggota`, `tanding`, `iuran`, `iuran-terang`, `lainnya`,
`login-hp`, `login-desktop`, `detail-laga`, `detail-turnamen`,
`detail-turnamen-desktop`, `turnamen-desktop`, `statistik`, `pengguna`,
`booking`, `pengumuman`, `pengaturan`.

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
