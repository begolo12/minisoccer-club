# Review — Tanding + Tim (round 1)

Metode: reviewer manual §2 (存量界面润色评审) — hanya menyelaraskan ke spesifikasi produk. Tanpa skor, tanpa mengganti warna/font/navigasi/halaman.
Bukti: 5 PNG statis di `design/current/`, semuanya benar-benar dibuka dan diukur: `tanding.png` 390x844 (1x, dark), `tanding-terang.png` 390x844 (1x, light), `detail-laga.png` 780x1688 (390x844@2x), `tim.png` 780x1688 (@2x), `tim-detail.png` 780x1688 (@2x).
Konvensi koordinat: **px = piksel di file**. Untuk file @2x saya tulis padanan dp dalam tanda kurung. Semua warna diambil dengan sampling piksel, bukan perkiraan.
Tidak ada preview server, tidak ada interaksi, tidak ada build/test yang dijalankan.

Catatan awal yang menentukan sisa laporan: `tanding.png` dan `tanding-terang.png` bukan dark/light dari layar yang sama — judul dan tab aktifnya sama ("Tanding"), tetapi jumlah seksi, set metrik strip, penamaan tim, subtitle, dan ada/tidaknya tabel klasemen berbeda. Keduanya tidak bisa sama-sama build terkini.

---

## 1. Checklist

### Masalah (urut dampak)

- **[problem 1]** `tanding.png` vs `tanding-terang.png` / seluruh layar: satu rute, dua arsitektur informasi — dark punya 4 seksi (SEDANG BERLANGSUNG / JADWAL BERIKUTNYA / KLASEMEN TIM / RIWAYAT HASIL) dan strip 3 tile (MAIN, GOL, SELISIH); light punya 2 seksi (BERLANGSUNG & AKAN DATANG / SELESAI) dan strip 5 tile (MENANG, SERI, KALAH, GOL, BOBOL); subtitle "Laga internal antar tim klub" vs "Jadwal & hasil pertandingan"; penamaan "Tim C vs Tim D" vs "vs Cimahi United"; tag hasil MENANG/SERI/KALAH hanya muncul di light, rata kanan sejajar judul (x329–368, `tanding-terang.png` y465–473), sementara di dark posisi itu kosong (x312–389 pada y746–752 tidak ada piksel) dan tag status dark diletakkan rata kiri di bawah meta (BERLANGSUNG y287, AKAN DATANG y409); skor baris yang sama 16px cap (`tanding.png`) vs 20px (`tanding-terang.png`); merah 0 piksel di dark vs 400 piksel di light → kedua tema harus merender inventaris elemen yang identik (seksi, tile strip, tag hasil, skala skor) dengan hanya nilai palet yang berbeda; diverifikasi sebagai daftar elemen yang sama pada kedua file.
- **[problem 2]** `tanding.png` / area daftar y186–694: laga berjalan dan laga berikutnya dipecah jadi dua seksi berisi satu baris masing-masing, lalu tabel klasemen diselipkan di antara jadwal dan hasil — label seksi di y207, y329, y451, y686 (jarak 122px, 122px, 235px), jadi empat SectionTitle dalam 479px; akibatnya daftar hasil baru mulai di y686 (81% tinggi layar) sementara di `tanding-terang.png` mulai di y445 → laga berjalan + akan datang berbagi satu SectionTitle, dan baris hasil pertama sudah terlihat tanpa scroll.
- **[problem 3]** `detail-laga.png` / ringkasan sesi, "0 KALAH": satu-satunya merah di seluruh halaman menandai angka nol — run merah `#FF5A5A` di x261–344, y664–681 (586 piksel merah di file ini, semuanya di blok itu), sementara "0 SERI" di sebelahnya netral; di `tanding-terang.png` merah hanya dipakai pada KALAH yang bernilai 1 (y127 dan y609) → merah hanya muncul pada kerugian yang benar-benar terjadi (nilai > 0) atau pada item yang gagal/terlambat; "0 KALAH" memakai warna meta netral yang sama dengan "0 SERI".
- **[problem 4]** `tim-detail.png` / StatStrip tile GOL: tiga caption dalam satu komponen memakai tiga ukuran — "cukup" cap 22px (11dp), "1M 0S 1K" 18px (9dp), "memasukkan–kebobolan" 9px (4.5dp) — dan caption terkecil justru satu-satunya yang menjelaskan arti "6-7", sehingga angka utama tile itu tidak terbaca sebagai "gol–kebobolan" di layar 390 → ketiga caption memakai satu token ukuran/warna (cap height terukur sama), dan arti "6-7" bisa dipahami tanpa membaca caption 4.5dp.
- **[problem 5]** `detail-laga.png` + `tim-detail.png` / baris daftar: affordance hapus adalah elemen yang paling banyak diulang dan paling menonjol — 5 kotak ber-border 34dp berisi "×" di `detail-laga.png` (plus "Ubah skor" + trash + "+ Sesi" + "+ Tambah"), 8 kotak yang sama di `tim-detail.png` (plus pensil + trash + "+ Tambah"); tidak ada satu pun frame role "member" di set ini untuk membuktikan aturan "member must never see add/edit/delete" → tersedia frame role member dari kedua layar yang tidak memuat satu pun affordance tambah/ubah/hapus, dan di frame admin hapus bukan lagi elemen yang paling banyak diulang (data utama baris harus lebih menonjol daripada tombol hapusnya).

### Peningkatan

- **[improvement 1]** `detail-laga.png` / blok skor: satu fakta ditulis tiga kali — judul halaman "Tim A vs Tim C", di dalam kartu "Tim A 5-3 Tim C", lalu verdict "Tim A menang" (y304–327) — sedangkan skornya sendiri sudah hijau sebagai penanda hasil → fixture disebut sekali di atas skor, kartu hanya memuat skor + aksi, dan baris verdict dihapus untuk membayar ruangnya.
- **[improvement 2]** `tanding.png` + `tim.png` / KLASEMEN: tabel 4 baris yang identik (TIM B 2 +3 4 … TIM C 2 -5 0) muncul di dua tab berbeda → tabel hanya hidup di satu layar; menghapusnya dari `tanding.png` adalah yang membayar problem 2 (hasil naik ke atas fold), sedangkan `tim.png` tetap memakai StandingsTable.
- **[improvement 3]** `tim-detail.png` / StatStrip: dua dari tiga tile hanya mengulang data yang sudah ada — "PEMAIN 8" = jumlah baris di bawahnya, "MAIN 2 / 1M 0S 1K" = string yang sama persis dengan meta baris Tim A di `tim.png`; strip memakan y176–373 (98.5dp) sehingga label "LAGA BERIKUTNYA" baru muncul di y1519 dari 1688 (90%) → hanya tile GOL yang dipertahankan (satu-satunya fakta yang tidak ada di tempat lain), dan label "LAGA BERIKUTNYA" terlihat tanpa scroll.
- **[improvement 4]** `tanding.png` / header StandingsTable: jarak header M→SG 18px (x281–289 → 307–322) tetapi SG→POIN hanya 7px (x322 → 329–355), sehingga pada 390px "SG POIN" terbaca sebagai satu token → jarak antar header kolom rata (selisih ≤4px), tanpa mengubah isi kolom.
- **[improvement 5]** `tim.png` / baris DAFTAR TIM: badge hijau berisi "8" dan subtitle di baris yang sama menulis "8 pemain" — satu angka dirender dua kali, dan badge lebih dulu terbaca sebagai nomor punggung/peringkat daripada jumlah pemain → hanya satu dari keduanya yang membawa angka itu, sehingga tiap baris menyebut jumlah pemain satu kali.

Sisa kecil (digabung): di `detail-laga.png` ada tiga gaya aksi sekunder pada satu halaman (kotak outline "Ubah skor", kotak ikon outline 34dp untuk trash/×, teks hijau polos "+ Sesi"/"+ Tambah") dan tidak ada Pill di kelima layar; kolom POIN di `tanding.png` dan `tim.png` seluruhnya hijau termasuk nilai 0 (Tim C), sehingga aksen tidak lagi menandai apa pun.

Yang sudah bersih: skor selalu rata kiri di kolom yang sama (`tanding-terang.png` x21–55 untuk keempat baris; `tanding.png` x21–53) dan tag hasil selalu rata kanan di x368 dengan warna yang benar (MENANG hijau, SERI netral, KALAH merah) — ini pola yang harus dipertahankan, bukan diperbaiki. Tabel klasemen ringkas M/SG/POIN juga tetap terbaca di 390px: keempat kolom rata kanan dan header sejajar dengan nilainya. Tidak ditemukan duplikat tangan dari komponen wajib mana pun (StatStrip/StatTile, StandingsTable, MatchRow, RowItem, SectionTitle, Panel semuanya dipakai ulang).

Yang tidak bisa dinilai dari set ini: (a) state pemain kurang/kosong — tidak ada frame-nya; yang bisa diukur hanya bahwa di frame yang ada tidak ada satu pun piksel merah di `tim.png` dan `tim-detail.png` (0 piksel merah terukur di kedua file) dan label state yang tampil ("cukup") dirender netral #8FA096, jadi netralitas cabang "kurang" belum terbukti; (b) pemisahan fixture vs riwayat di `tim-detail.png` hanya separuh — label "LAGA BERIKUTNYA" ada di y1519 dan terpisah oleh SectionTitle, tetapi bagian riwayat tidak masuk frame sehingga pemisahannya tidak bisa dibandingkan; (c) role "member"; (d) layout desktop ≥900px; (e) blok kartu — di `detail-laga.png` tidak ada satu pun baris kartu (hanya Gol dan Assist: 4 Gol + 1 Assist terlihat, satu baris terpotong di tepi bawah), jadi perlakuan warna/ikon kartu tidak bisa dinilai, dan tiap baris catatan tidak menyebut tim pemilik kejadian sehingga atribusi gol ke Tim A atau Tim C tidak bisa diperiksa dari frame.

---

## 2. Penyimpangan spesifikasi

| # | Penyimpangan | Bukti (file / lokasi terukur) |
|---|---|---|
| 1 | Warna hairline baris bukan nilai spesifikasi (dark) | `tanding.png` y308, `tim.png` y1048/1170/1292/1414, `tim-detail.png` y622/744/866/988/1110/1232/1354/1476: **#18221D**, spesifikasi **#202C25** |
| 2 | Warna hairline baris bukan nilai spesifikasi (light) | `tanding-terang.png` y368/507/568/629/708: **#E0E6E0**, spesifikasi **#D8E0D9**. Border panel justru memakai nilai yang benar (`tanding-terang.png` y95–100 = #D8E0D9) |
| 3 | Dua treatment panel untuk level yang sama | `tim.png`: StatStrip = base #080B09 + outline #202C25 (interior transparan), StandingsTable = kartu terisi #0E1512. Hal yang sama di `tanding.png` (strip transparan, tabel terisi) dan `tim-detail.png` (strip transparan). Spesifikasi hanya punya satu warna card |
| 4 | Aksen hijau light di luar palet | `tanding-terang.png`: isi solid angka "2" pada tile MENANG = **#0A7D43**, spesifikasi **#0E7C48**. Hijau dark di `tanding.png` dan `detail-laga.png` benar (#35D07F) |
| 5 | Hijau ketiga tanpa nama | `tim.png` x40–115, y951–1026: angka dan border badge tim = **#1F6D44** (bukan #35D07F, bukan #0E1512) |
| 6 | Tint permukaan di luar palet | `tanding.png` pill nav aktif = **#0E261A**; `tanding-terang.png` = **#D1E4D8**. Navigasi terkunci, jadi ini catatan untuk daftar token, bukan permintaan desain ulang |
| 7 | Skala caption StatTile tidak satu token | `tim-detail.png`: "cukup" cap 22px, "1M 0S 1K" 18px, "memasukkan–kebobolan" 9px (semua @2x) |
| 8 | Merah dipakai untuk nilai netral | `detail-laga.png` "0 KALAH" #FF5A5A (x261–344, y664–681). Aturan: merah hanya untuk gagal/terlambat (lihat problem 3) |
| 9 | Skala skor tidak dibagi antar tema | `tanding.png` baris riwayat: cap 16px; `tanding-terang.png` baris selesai: cap 20px — elemen yang sama, ukuran berbeda 25% |
| 10 | Tiga gaya aksi sekunder, tidak ada Pill | `detail-laga.png`: outline rect (radius ~8dp, tinggi 34dp) "Ubah skor", outline ikon 34dp (trash + tiap "×"), teks hijau polos "+ Sesi"/"+ Tambah". Pill tidak muncul di kelima layar padahal ada di daftar komponen wajib |
| 11 | Komponen baru tanpa padanan gaya | `tim.png` badge persegi-rounded 38dp (x40–115, y951–1026) berisi jumlah pemain, dan `detail-laga.png` tombol outline — keduanya tidak punya padanan di daftar komponen wajib, jadi tidak ada acuan gaya untuknya |
| 12 | Radius: spesifikasi tidak punya skala | Tiga radius berbeda dipakai (pill nav penuh bulat, panel, tombol ikon). Ini celah spesifikasi, bukan pelanggaran — perlu keputusan pemilik produk |
| 13 | Tidak bisa diverifikasi dari raster | Keluarga font (Barlow Condensed vs substitusi) dan positive tracking tidak bisa dipastikan dari PNG. Yang bisa dibuktikan: angka memang tabular — keempat skor `tanding-terang.png` berukuran 34–35px untuk jumlah digit yang sama |
| 14 | Sesuai spesifikasi (bukan penyimpangan) | Base #080B09 / #F2F5F1 dan card #0E1512 dan hairline panel #202C25 / #D8E0D9 semuanya persis nilai spesifikasi; tanpa gradient dan tanpa drop shadow (scan `detail-laga.png` x390 y90–101 murni #080B09 di atas border, tanpa halo); SectionTitle konsisten kecil+uppercase+rule ke tepi kanan; daftar memakai hairline row, bukan kartu bertumpuk; merah light hanya pada kerugian nyata. Card light #FFFFFF tidak terpakai karena layar light di set ini tidak punya panel terisi |

Tidak bisa diverifikasi karena tidak ada frame-nya: layout desktop ≥900px (rail 216px, konten max 980px, dua kolom) — set ini tidak memuat 1440x900; role "member"; state pemain kurang/kosong.

---

## 3. Tiga masalah layout/structure terbesar

### T1 — `tanding.png`: seksi dipecah sampai tiap SectionTitle hanya membungkus satu baris, dan tabel klasemen memotong alur laga
- **Lokasi:** area daftar y186–694, di antara strip dan fold.
- **Bukti:** label seksi terukur di y207 (SEDANG BERLANGSUNG), y329 (JADWAL BERIKUTNYA), y451 (KLASEMEN TIM), y686 (RIWAYAT HASIL). Dua label pertama hanya berjarak 122px dan masing-masing menaungi tepat satu baris laga (y244–273 dan y366–416). Tabel klasemen (card y473–657) duduk di antara jadwal dan hasil. Akibat terukurnya: baris hasil pertama mulai y686 dari 844, sedangkan di `tanding-terang.png` daftar SELESAI mulai y407 dan skor pertama y460.
- **Dampak:** mata harus melewati tiga judul seksi dan satu tabel untuk sampai ke "hasil terakhir" — pertanyaan pertama saat membuka tab Tanding. Empat SectionTitle dalam 479px membuat layar terbaca sebagai empat widget terpisah, bukan satu alur laga.
- **Target:** (a) laga berjalan + akan datang berbagi satu SectionTitle (seperti `tanding-terang.png`), (b) tabel klasemen keluar dari layar ini karena sudah ada di `tim.png` — itu yang membayar ruangnya, (c) baris hasil pertama terlihat tanpa scroll.
- **Verifikasi:** hitung SectionTitle di `tanding.png` (harus 2: satu untuk laga, satu untuk hasil); ukur y baris hasil pertama (< 500, sekarang 686); pastikan tabel 4 baris tidak lagi muncul di file ini.

### T2 — `detail-laga.png`: massa terberat halaman adalah blok yang paling sedikit informasinya, dan fixture-nya ditulis tiga kali
- **Lokasi:** header + kartu skor, y0–490.
- **Bukti:** judul "Tim A vs Tim C" (y37–68), lalu panel ber-border #202C25 setebal 4px (2dp) dari y102 sampai y487 berisi empat baris bertumpuk: tanggal (y150–167), skor 5-3 (x332–447, y222–284 — 116x63px = 58x31.5dp, satu-satunya elemen besar di halaman), verdict "Tim A menang" (y304–327), dan dua tombol (border y374–441). Panel itu satu-satunya panel ber-border di halaman; semua di bawahnya (sesi, catatan pertandingan) datar di atas base dengan hairline row. Jadi massa visual terberat ditaruh pada blok yang isinya mengulang judul + mengulang skor.
- **Dampak:** hierarki halaman jadi terbalik — blok 487px di atas hanya menyampaikan satu fakta (5-3, Tim A menang), sementara blok yang benar-benar menjelaskan angka itu baru mulai di y590 (label SESI & PEMENANG), S1 di y739, S2 di y821, lalu daftar gol di y976 dan terpotong di tepi layar 1688 — jadi penjelasan skor tidak pernah selesai dalam satu layar.
- **Target:** skor tetap jadi elemen terbesar, tetapi fixture disebut sekali (judul ATAU nama tim di dalam kartu, bukan keduanya), verdict dihapus karena skor hijau sudah menyatakannya, dan tanggal pindah keluar dari kartu sehingga blok itu menyusut dan blok sesi naik ke dalam layar.
- **Verifikasi:** string "Tim A vs Tim C" muncul satu kali; tidak ada baris verdict "… menang"; label "SESI & PEMENANG" mulai di atas y480 (@2x, sekarang y590) dan baris catatan terakhir yang terlihat adalah baris utuh, bukan terpotong.

### T3 — `tim.png` + `tim-detail.png`: kolom nama bergeser tiga nilai berbeda antar layar tim
- **Lokasi:** kolom teks utama pada baris daftar di kedua layar.
- **Bukti (@2x → dp):** `tim.png` nama tim mulai x140 (70dp) dengan badge di x40–115 (20–57.5dp), konsisten di keempat baris (x140 di y950/1072/1194/1316); `tim-detail.png` nama pemain mulai x126 (63dp) dengan nomor punggung di x42–54 (21–27dp); baris LAGA BERIKUTNYA di `tim-detail.png` judulnya mulai x172 (86dp) dengan ikon jam di x84 (42dp). Label seksi di kedua layar mulai x42–43 (21dp). Jadi satu layar memakai tiga anchor teks: 21 / 63 / 86dp, dan "nama item daftar" yang sama bergeser 7dp antara dua layar tim (70dp vs 63dp).
- **Dampak:** saat berpindah Tim → detail tim, semua nama bergeser; dan di dalam satu layar, baris fixture tidak sejajar dengan daftar pemain tepat di atasnya (86dp vs 63dp), sehingga bagian bawah halaman terbaca sebagai dua sistem baris yang berbeda. Halaman kehilangan 2–3 garis vertikal bersama yang membuat daftar mudah dipindai.
- **Target:** satu kolom nama per jenis baris di kedua layar tim (63dp atau 70dp, pilih satu), dan baris fixture memakai gutter ikon yang sama dengan baris laga di `tanding.png` sehingga judulnya jatuh di kolom yang sama dengan elemen sekolomnya.
- **Verifikasi:** ukur left edge nama di `tim.png` (x140) dan `tim-detail.png` (x126) — harus satu nilai; lalu left edge judul fixture (x172) vs nama pemain (x126) di `tim-detail.png` — selisih hanya selebar gutter ikon (42dp), bukan 23dp.

---

## 4. Motion

Motion/interaction not verified — bukti hanya frame statis, tanpa preview server dan tanpa interaksi. Tidak ada klaim soal transisi, umpan balik tombol, urutan muat, maupun alur (termasuk apakah "Ubah skor", "+ Sesi", "+ Tambah", chevron tim, dan "×" benar-benar bekerja, dan apakah state pemain kurang/kosong punya tampilan sendiri).

---

## 5. Teks dan elemen yang bisa dihapus

| String / elemen | Screenshot | Alasan |
|---|---|---|
| "dasar semua tanding" (dari subtitle "7–8 pemain per tim • dasar semua tanding") | `tim.png` | Fragmen yang tidak menunjuk objek/aksi/data apa pun; aturan jumlah pemain sudah tertulis di caption tile SIAP MAIN "min. 7 pemain" |
| "Tim klub" | `tim-detail.png` | Subtitle generik di bawah "Tim A"; tidak membedakan apa pun (semua tim adalah tim klub) |
| "Tim A menang" | `detail-laga.png` | Mengulang skor 5-3 yang sudah berwarna hijau; fakta yang sama ditulis ketiga kalinya di halaman |
| "memasukkan–kebobolan" | `tim-detail.png` | Hapus hanya bila label tile GOL diganti "GOL/BOBOL" — nama label yang menyebut kedua sisi lebih murah daripada caption 4.5dp |
| "SEDANG BERLANGSUNG" (label seksi) | `tanding.png` | Hilang dengan sendirinya saat seksi digabung dengan JADWAL BERIKUTNYA (problem 2); yang dihapus labelnya, bukan barisnya |
| Blok KLASEMEN TIM (4 baris tabel) | `tanding.png` | Duplikat persis tabel KLASEMEN di `tim.png`; menghapusnya adalah biaya untuk menaikkan daftar hasil ke atas fold |
| 5 kotak "×" pada 5 baris catatan pertandingan | `detail-laga.png` | Aksi hapus permanen per baris; halaman sudah punya satu aksi hapus di kartu skor, jadi 5 target tambahan ini hanya menambah noise |
| 8 kotak "×" pada 8 baris pemain | `tim-detail.png` | Alasan yang sama; hapus-per-pemain bukan tugas utama layar ini dan menjadi elemen paling banyak diulang |

Bukan untuk dihapus tapi harus disatukan: tag status `tanding-terang.png` memakai "BERLANGSUNG"/"KANDANG" sementara `tanding.png` memakai "BERLANGSUNG"/"AKAN DATANG" — satu kosakata status untuk satu state.

---

## 6. Keep

1. **Baris laga dengan skor rata kiri + tag hasil rata kanan** (`tanding-terang.png`: skor x21–55, tag berakhir x368, MENANG hijau / SERI netral / KALAH merah) — ini inti arah "papan skor": angka dulu, hasil di ujung baris, satu baris per laga. Jangan diubah jadi kartu, jangan di-center, dan jangan diseragamkan warnanya saat merapikan tema.
2. **Rincian sesi di `detail-laga.png`** ("2 MENANG 0 SERI 0 KALAH" + "S1 2–1", "S2 3–2") — satu-satunya blok yang menjelaskan asal angka 5-3 alih-alih mengulangnya, dan angkanya konsisten (2+3=5, 1+2=3). Saat memangkas kartu skor dan verdict, blok ini yang harus tetap utuh dan naik lebih dekat ke skor.
