# Round 1 review — Iuran + Kas

Reviewer: independen (tidak membangun UI ini). Metode: `oil-ui` reviewer manual §2 — menyelaraskan ke spesifikasi produk yang ada, tanpa skor, tanpa mengganti brand/font/navigasi.
Bukti: PNG statis di `design/current/`. Tanpa interaksi, tanpa preview server, tanpa membaca `lib/`.
Frame yang dibaca: `iuran.png` (780x1688 = 390x844@2x, dark), `iuran-terang.png` (2x, light), `kas.png` (390x844, dark), `kas-terang.png` (2x, light), `kas-desktop.png` (1440x900, dark).

Semua angka diukur dari piksel lalu dibagi 2 untuk frame @2x; satuannya px logis. Diukur: margin konten phone 20px (x=20..369); pitch baris ledger 61px (satu baris teks) / 79px (dua baris) di phone, dan 61px untuk semua baris di desktop termasuk yang dua baris; tinggi chip periode 38.5px; chip tunggakan Iuran 31.5px; panel ringkasan Iuran 98.5px vs Kas 81px; nominal rata kanan di x=328/329 (phone) dan x=1149 (desktop) dengan gutter tombol hapus 336..369 / 1156..1189; hairline baris `#18221D` / `#E0E6E0`, hairline panel & rule `#202C25` / `#D8E0D9`; `#FFFFFF` muncul 0 piksel di kedua frame light dan `#0E1512` tidak muncul di ketiga frame dark.

---

## 1. Quick checklist

### Problems (dampak terbesar dulu)

- **[problem 1]** `kas.png`, `kas-terang.png` / seluruh frame: bottom nav tidak dirender sama sekali — teks baris terakhir berhenti di y=822 dan hairline penutup di y=838 dari 844, lalu frame habis; tidak ada nav. Bandingkan `iuran.png` dan `iuran-terang.png` (viewport identik, state scroll sama-sama di tengah daftar) yang menampilkan nav 5 item. Model navigasi phone yang dikunci hilang di satu layar penuh, dan daftar berjalan sampai tepi bawah tanpa penutup. -> Acceptance: `kas.png` dan `kas-terang.png` menampilkan nav 5 item yang sama dengan `iuran.png` (posisi, ikon, label, pill aktif), dan hairline terakhir berhenti ≥16px di atas hairline atas nav.
- **[problem 2]** `kas.png`, `kas-terang.png`, `kas-desktop.png` / judul baris ("Iuran", "Sewa lapangan", "Wasit"): judul baris adalah teks **terkecil** di barisnya dan jauh di bawah norma daftar di produk ini. Cap "I" pada "Iuran" = 8px, digit "18" pada meta di bawahnya = 9px, cap "R" pada nominal di kanan = 12px. Bandingkan `iuran.png`: cap "R" pada "Rizky Pratama" = 11px, nominal = 10px, meta = 9px — hierarkinya benar. Nama anggota di `anggota.png` juga 11px cap. Di `kas-desktop.png` judul baris tetap 8px cap pada 1440px, sedangkan nama di kolom kanan `beranda-desktop.png` 13px cap. -> Acceptance: judul baris Kas ≥ cap nama baris `iuran.png` pada breakpoint yang sama (11px di 390px) dan lebih besar dari meta maupun nominalnya; ukuran judul baris desktop tidak lebih kecil dari ukuran baris desktop lain di produk.
- **[problem 3]** `iuran.png`, `iuran-terang.png` / baris chip periode: tidak ada chip "Semua" — chip pertama langsung "Oktober 2026" dalam keadaan aktif, lalu "September 2026", "Agustus 2026". `kas.png`, `kas-terang.png`, dan `kas-desktop.png` semuanya memulai dengan "Semua". -> Acceptance: chip pertama `iuran.png` bertulis "Semua" dan tidak aktif saat sebuah bulan dipilih; urutan dan jumlah chip identik dengan `kas.png` pada viewport yang sama.
- **[problem 4]** `iuran.png`, `iuran-terang.png` / blok "BELUM BAYAR", kelima chip: setiap anggota yang **belum** bayar membawa glyph centang merah ("Farhan Maulana ✓", "Gilang Ramadhan ✓", "Hafiz Alfarizi ✓", "Iqbal Fauzi ✓", "Jefri Kurnia ✓"), padahal glyph centang yang sama dipakai baris "RIWAYAT PEMBAYARAN" untuk status **sudah** bayar. Dibaca tanpa judul seksi, kelima chip berarti "lunas". -> Acceptance: chip anggota yang belum bayar tidak membawa glyph centang; maknanya tetap terbaca dari judul seksi + warna/border, bukan dari glyph yang dipakai untuk state kebalikannya.
- **[problem 5]** `iuran.png` vs `kas.png`, `kas-desktop.png` / kolom nominal: uang yang sama diperlakukan dengan tiga cara. "Rp 75.000" milik Rizky Pratama berwarna amber `#F5B841` di `iuran.png` tetapi "＋Rp 75.000" untuk pembayaran yang sama berwarna hijau `#35D07F` di `kas.png`; "−Rp 350.000" dan "−Rp 200.000" netral `#E8F0EA`; dan merah — yang oleh spesifikasi dicadangkan untuk "loss" — muncul 0 piksel di ketiga frame Kas. Amber juga hanya dipakai pada SALDO, bukan pada MASUK/KELUAR. -> Acceptance: satu tata bahasa warna uang yang konsisten di kedua layar — nominal kelas sama berwarna sama; hijau hanya untuk state/affordance (chip aktif, glyph lunas), bukan untuk nominal; jika arus keluar dianggap "loss" ia memakai merah `#FF5A5A` / `#B3261E`, jika tidak, kalimat spesifikasi itu yang perlu diputuskan pemiliknya.
- **[problem 6]** `iuran.png`, `iuran-terang.png` / baris terakhir: "Joko Susilo" terpotong — baris tanggal "18 Okt 2026" terbelah horizontal oleh bottom nav, bagian atas glyph tanggal hilang di bawah nav. -> Acceptance: tidak ada glyph yang tertutup nav pada 390x844 di kedua tema; padding bawah daftar ≥ tinggi nav.
- **[problem 7]** `iuran.png` vs `kas.png` / StatStrip: komponen bersama yang sama tampil dua ukuran pada breakpoint yang sama. `iuran.png`: nilai uang TERKUMPUL/KURANG cap ≈13px, nilai rasio "26/31" cap ≈25px (≈1.9x lebih besar), panel 98.5px. `kas.png`: ketiga nilai cap ≈10.5px seragam, panel 81px. Dua tile Iuran juga menyebut angka yang sama dua kali ("5 belum" di bawah LUNAS, "5 anggota" di bawah KURANG), sementara tiga sub-label Kas berjenis berbeda ("iuran Rp 1,95 jt" = rincian, "3 catatan" = jumlah, "tersedia" = kata status). -> Acceptance: satu ukuran nilai per breakpoint di kedua layar; tiap tile = label + nilai + maksimal satu sub-label; tidak ada dua tile yang menyebut angka yang sama.
- **[problem 8]** `iuran.png`, `iuran-terang.png` / blok "BELUM BAYAR": chip tidak duduk di grid halaman. Teks chip mulai di x=32, sedangkan seluruh nama baris di bawahnya mulai di x=48 dan label seksi di x=45..46.5; dua baris chip punya dua tepi kanan berbeda (baris 1 berakhir x=306.5, baris 2 x=363.5) dan lebar tidak seragam (chip 1 "Farhan Maulana" 22..154, chip 2 "Gilang Ramadhan" 165..306.5). -> Acceptance: teks chip berbagi satu anchor dengan teks baris ledger di bawahnya, dan blok hanya punya satu tepi kanan.
- **[problem 9]** `kas.png` / baris chip periode: chip keempat terpotong di tengah kata ("Agu") pada tepi frame; `iuran.png` memotong border chip "Agustus 2026" tetapi teksnya utuh — dua tingkat pemotongan berbeda untuk komponen yang sama. -> Acceptance: tidak ada glyph yang terbelah di tepi; jika baris memang dapat di-scroll, pemotongan tampil sebagai mask/fade yang disengaja.

### Improvements

- **[improvement 1]** `kas.png`, `kas-terang.png`, `kas-desktop.png` / sub-label tile MASUK: "iuran Rp 1,95 jt" memakai presisi berbeda dari nominal di sebelahnya ("Rp 3.700.000"). Dua presisi dalam satu panel merusak pembacaan kolom angka. -> Target: satu format untuk semua nominal; "jt" hilang dari kosakata angka.
- **[improvement 2]** kelima frame / header: periode dinyatakan dua kali dalam 40px — subtitle "Oktober 2026" di bawah judul halaman dan chip aktif "Oktober 2026". -> Target: satu pernyataan periode (chip), header kembali satu baris.
- **[improvement 3]** kelima frame / semua divider: ada dua nilai hairline — divider RowItem `#18221D` (dark) / `#E0E6E0` (light) versus border Panel dan rule SectionTitle `#202C25` / `#D8E0D9`. -> Target: satu token hairline, atau peredupan yang diterapkan konsisten ke rule dan divider sekaligus.
- **[improvement 4]** `iuran.png` vs `kas.png` / anchor SectionTitle: di `iuran.png` label "BELUM BAYAR" (x=45) dan "RIWAYAT PEMBAYARAN" (x=45) sejajar dengan teks baris (x=48); di `kas.png` label "BUKU KAS" (x=20) sejajar dengan ikon baris (x=21), bukan dengan teks baris (x=58). -> Target: satu logika anchor untuk SectionTitle terhadap RowItem, dipakai di kedua layar.
- **[improvement 5]** `iuran.png`, `iuran-terang.png` / blok tunggakan: kelima chip memakai border merah baru `#6B2B29` (dark) / `#D9A29D` (light) — dua nilai di luar palet, yang sudah punya `#FF5A5A`/`#B3261E` untuk merah dan `#202C25`/`#D8E0D9` untuk hairline. -> Target: state tunggakan memakai salah satu dari dua token yang sudah ada, bukan turunan baru.

**Bersih / bukan masalah:** kolom nominal lurus di semua baris, baik yang punya tombol hapus maupun tidak — tepi kanan 328/329 di `kas.png` dan `iuran.png`, 1149 di `kas-desktop.png`, gutter hapus 336..369 / 1156..1189 selalu dicadangkan sehingga tidak ada pergeseran; baris terbaca sebagai ledger hairline, bukan kartu bertumpuk, di `kas.png`, `kas-terang.png`, `kas-desktop.png` (tanpa fill, tanpa shadow, hairline penuh 20..369); chip aktif terbedakan tanpa warna karena bentuknya terisi dengan label terbalik (gelap di atas `#35D07F` pada dark, putih di atas hijau tua pada light) versus outline pada chip non-aktif; pitch baris 61px konsisten di `iuran.png` dan `kas.png`; merah hanya muncul untuk tunggakan di `iuran.png` (nilai KURANG + lima chip) dan tidak muncul sama sekali di ketiga frame Kas; tidak ada gradient maupun drop shadow di kelima frame; SectionTitle konsisten (uppercase kecil + rule ke tepi kanan konten, mis. "BUKU KAS" di `kas-desktop.png` berhenti di x=1189). `kas-terang.png` adalah frame paling bersih dari kelima.

**Tidak bisa diverifikasi dari set ini (tidak dihitung sebagai cacat):** state "Semua" aktif — tidak ada satu pun frame yang menampilkannya, jadi pemisah bulan dan perilakunya tidak bisa dinilai; state bulan kosong — kelima frame menampilkan Oktober yang terisi; tabular figures / positive tracking / Barlow Condensed asli vs substitusi — tidak bisa dipastikan dari raster, dan setiap nominal dalam satu kolom berangka sama sehingga tabularitas tidak teruji; role "member" — tidak ada indikator role di kelima frame, tombol "+" dan tombol hapus terlihat tanpa penanda siapa yang melihat; alur dan konfirmasi hapus.

---

## 2. Penyimpangan spesifikasi

Warna diambil langsung dari PNG; nilai yang persis sama dengan spesifikasi tidak didaftarkan.

| # | Penyimpangan | Bukti |
|---|---|---|
| D1 | Light money `#7A5C00`, spesifikasi `#8A5A00`. Nilai `#8A5A00` tidak ada di file mana pun. | `iuran-terang.png` (TERKUMPUL + seluruh nominal riwayat), `kas-terang.png` (SALDO) |
| D2 | Light accent `#0A7D43`, spesifikasi `#0E7C48`; dipakai sekaligus untuk fill chip aktif, glyph centang, dan nominal masuk. | `iuran-terang.png`, `kas-terang.png` |
| D3 | Token card tidak pernah dipakai: interior Panel/StatStrip = base halaman di kedua tema (`#080B09` dark, `#F2F5F1` light), bukan `#0E1512` / `#FFFFFF`. `#FFFFFF` 0 piksel di kedua frame light; `#0E1512` tidak ada di ketiga frame dark. | `iuran.png`, `kas.png`, `kas-desktop.png`, `iuran-terang.png`, `kas-terang.png` |
| D4 | Dua nilai hairline: divider RowItem `#18221D` (dark) / `#E0E6E0` (light) versus border Panel dan rule SectionTitle `#202C25` / `#D8E0D9`. Keduanya hadir di frame yang sama dengan jumlah piksel berbeda (11896 vs 8400 di `iuran.png`; 11897 vs 8416 di `iuran-terang.png`). | `iuran.png` (border panel y=126 vs divider baris y=439.5), `kas.png`, `kas-desktop.png`; `iuran-terang.png` (rule header y=71 `#D8E0D9` vs divider `#E0E6E0`), `kas-terang.png` |
| D5 | Bottom nav tidak dirender pada frame phone Kas (spesifikasi: phone = bottom nav). | `kas.png` (baris terakhir sampai y=822, hairline y=838, sisa 6px ke tepi), `kas-terang.png`; pembanding benar: `iuran.png`, `iuran-terang.png` |
| D6 | Rail 216px tidak dirender dan kolom konten ter-center di lebar viewport penuh (250..1189 = 940px), bukan di area 216..1440. | `kas-desktop.png` (0 piksel non-base di x<216) vs `beranda-desktop.png` (hairline rail x=215, konten mulai x=362) |
| D7 | Tata bahasa warna uang bertabrakan: nominal Iuran amber (money), nominal masuk Kas hijau (accent), nominal keluar Kas netral; merah untuk "loss" tidak dipakai di Kas. Spesifikasi: "Money: amber", "Overdue and loss: red". | `iuran.png`, `iuran-terang.png` vs `kas.png`, `kas-terang.png`, `kas-desktop.png` |
| D8 | PeriodChips dua konfigurasi pada viewport yang sama: tanpa "Semua" di Iuran, dengan "Semua" di Kas. Spesifikasi: "Semua first, then months". | `iuran.png`, `iuran-terang.png` vs `kas.png`, `kas-terang.png`, `kas-desktop.png` |
| D9 | StatStrip tidak direuse dengan ukuran yang sama pada breakpoint yang sama: nilai tengah cap ≈25px di satu layar, ketiga nilai cap ≈10.5px di layar lain (390px). | `iuran.png` vs `kas.png` |
| D10 | Ukuran judul baris RowItem berbeda jauh antar layar: cap 8px di Kas, 11px di Iuran dan di `anggota.png`, 13px pada baris desktop `beranda-desktop.png`. Di Kas judul (8px) juga lebih kecil dari meta (9px) dan nominal (12px) di baris yang sama. | `kas.png`, `kas-terang.png`, `kas-desktop.png` vs `iuran.png` |
| D11 | Border chip tunggakan `#6B2B29` (dark) / `#D9A29D` (light) — dua nilai di luar palet; spesifikasi hanya punya merah `#FF5A5A`/`#B3261E` dan hairline `#202C25`/`#D8E0D9`. | `iuran.png`, `iuran-terang.png` |
| D12 | Lebar konten 940px (≤980) — sesuai batas spesifikasi; dicatat hanya agar tidak diubah saat memperbaiki D6. | `kas-desktop.png` (250..1189), `beranda-desktop.png` (362..1293) |

Di dalam spesifikasi dan benar: base `#080B09` / `#F2F5F1`; hairline `#202C25` / `#D8E0D9` pada border Panel dan SectionTitle; accent `#35D07F`; money `#F5B841`; red `#FF5A5A` / `#B3261E`; permukaan datar tanpa gradient dan drop shadow; daftar = hairline RowItem tanpa kartu bertumpuk; margin konten phone 20px; chip periode 38.5px; pitch baris 61px dengan 79px untuk baris dua-baris di phone; kolom nominal rata kanan yang stabil. Radius tidak dinilai karena spesifikasi tidak mendefinisikannya dan tidak ada token radius di produk — chip, panel, dan tombol hapus memakai tiga nilai berbeda tanpa acuan.

---

## 3. Tiga masalah layout/structure terbesar

### T1 — `kas-desktop.png`: kolom 940px yang isinya hanya menempati 20% kiri baris

- **Lokasi:** seluruh area ledger di 1440x900.
- **Bukti:** deskripsi terpanjang "18 Okt 2026 • Sewa lapangan latihan rutin" berakhir di x=443, nominal mulai di x=1070 — 627px kosong di dalam baris selebar 940px (250..1189). Judul baris 8px cap, meta 9px cap: ukuran type phone dipakai apa adanya di 1440px, sementara `beranda-desktop.png` memakai 13px cap untuk baris setara. Rail 216px tidak dirender (0 piksel non-base di x<216), jadi tepi kiri ledger di x=250 tidak bertemu garis struktur apa pun — 112px lebih kiri dari anchor konten Beranda di x=362. Pitch baris 61px dipakai untuk semua baris, termasuk baris dua-baris "Sewa lapangan" yang di phone mendapat 79px; sepuluh baris utuh mengisi tinggi frame, lalu baris berikutnya terpotong tepi bawah.
- **Dampak:** halaman terbaca sebagai tabel yang mengambang di kegelapan, bukan kolom 980px yang dipilih dengan sengaja. Mata menempuh ~900px per baris untuk memasangkan deskripsi dengan nominalnya, dan 216px pertama frame tidak dipakai sama sekali. Jawaban atas pertanyaan "apakah kolom 980px berisi baris satu-baris terasa kosong atau disengaja": terasa kosong, dan penyebabnya terukur — bukan karena 980px terlalu lebar (batas itu dikunci), melainkan karena isi baris tidak disebar ke lebar yang tersedia dan type tidak naik bersama breakpoint.
- **Target hasil:** rail hadir seperti `beranda-desktop.png`; tepi kiri ledger jatuh di garis vertikal yang sama dengan konten Beranda; bagian tengah baris diisi field yang **sudah ada** — tanggal dan nama anggota dipisah menjadi dua kolom rata sehingga tiap baris punya tiga anchor (judul, tanggal, nama) di samping nominal — dan ukuran type baris desktop naik ke level baris desktop lain di produk. Tidak ada field baru, tidak ada kartu, pitch 61px boleh tetap.
- **Verifikasi:** tumpuk `kas-desktop.png` di atas `beranda-desktop.png` — tepi kiri konten berimpit (≈362) dan hairline rail terlihat di x=215; jarak dari ujung deskripsi terpanjang ke awal nominal ≤ ⅓ lebar baris; cap judul baris desktop ≥ cap baris `beranda-desktop.png`; jumlah anchor-x yang berulang di semua baris ≥ 3.

### T2 — `kas.png`, `kas-terang.png`, `kas-desktop.png`: hierarki baris terbalik — judul adalah teks terkecil

- **Lokasi:** semua baris ledger, mis. baris pertama y=270..300.
- **Bukti:** cap "I" pada "Iuran" = 8px; cap digit "18" pada meta di bawahnya = 9px; cap "R" pada nominal "+Rp 75.000" di kanan = 12px. Di `iuran.png` hubungannya benar: nama 11px, nominal 10px, meta 9px. Di `kas-desktop.png` judul baris tetap 8px cap sementara baris setara di `beranda-desktop.png` 13px cap. Akibatnya yang menonjol di Kas adalah tanggal, nama, dan angka — bukan jenis transaksi; "Iuran", "Sewa lapangan", "Wasit", satu-satunya kata yang membedakan pemasukan dari pengeluaran, adalah teks terkecil di layar.
- **Dampak:** buku kas kehilangan kolom yang paling penting. Untuk membedakan pemasukan dari pengeluaran, pembaca harus memakai ikon 20px dan warna nominal (yang sendiri tidak konsisten — problem 5), bukan judul baris. Di desktop efeknya berlipat karena type tetap 8px pada 1440px.
- **Target hasil:** judul baris menjadi teks terbesar di barisnya, minimal sejajar dengan baris `iuran.png` pada breakpoint yang sama, dan tidak lebih kecil dari baris desktop lain di produk; meta turun satu tingkat di bawahnya. Tidak menambah elemen — cukup membalik dua tingkat type yang sudah ada.
- **Verifikasi:** ukur cap judul, cap digit meta, dan cap nominal di baris yang sama pada `kas.png`, `kas-terang.png`, `kas-desktop.png` — judul harus yang terbesar; bandingkan dengan `iuran.png` pada skala yang sama.

### T3 — `iuran.png`: ringkasan tiga angka tidak menunjuk ke pekerjaan yang harus dilakukan

- **Lokasi:** panel ringkasan y=126..224.5, lalu blok "BELUM BAYAR" y=245..336.5.
- **Bukti:** TERKUMPUL = uang, cap ≈13px; LUNAS = rasio, cap ≈25px (paling besar di seluruh layar, ≈1.9x nilai uang di sebelahnya); KURANG = uang, cap ≈13px. Komponen yang sama di `kas.png` 81px dengan tiga nilai seragam cap ≈10.5px, jadi ukuran 25px itu pilihan lokal, bukan sifat komponen. Fakta "5 orang belum bayar" muncul tiga kali: "5 belum", "5 anggota", dan lima chip di bawahnya. Angka yang bisa ditindaklanjuti (Rp 375.000 / 5 anggota) berukuran sama dengan angka yang sudah selesai (Rp 1.950.000) dan duduk di slot ketiga.
- **Dampak:** mata mendarat di 26/31 — satu-satunya angka yang tidak menuntut aksi — lalu harus mencari ulang apa yang perlu dikerjakan. Ringkasan tidak pernah mengatakan "kejar 5 orang", dan dua sub-label yang berjenis berbeda membuat panel terbaca sebagai tiga widget terpisah, bukan satu strip.
- **Target hasil:** satu ukuran nilai untuk ketiga tile pada 390px (seperti `kas.png` sudah lakukan); jumlah orang disebut satu kali; penekanan diberikan lewat warna merah pada KURANG, bukan lewat ukuran yang berbeda-beda. Tidak menambah tile — ruang untuk menyamakan ukuran dibayar dengan menghapus satu dari dua sub-label yang menduplikasi angka.
- **Verifikasi:** cap height ketiga nilai di `iuran.png` sama; tinggi panel kembali 81px kecuali ada tile yang butuh baris kedua; angka "5" sebagai jumlah orang muncul satu kali di frame, di luar lima chip.

---

## 4. Motion

Motion/interaction not verified — bukti hanya frame statis, tanpa preview server dan tanpa interaksi. Tidak ada klaim soal transisi, umpan balik tap, konfirmasi hapus, atau perilaku scroll baris chip periode. Konsekuensinya problem 1 dan problem 9 tidak bisa dipastikan sebagai "nav memang tidak dirender" versus "nav disembunyikan saat scroll": yang bisa dikatakan hanya bahwa frame 390x844 untuk Kas tidak menampilkannya, sementara frame Iuran dengan state scroll serupa menampilkannya, dan bahwa chip keempat di `kas.png` terpotong di tengah kata.

---

## 5. Teks dan elemen yang bisa dihapus

| String / elemen | Screenshot | Alasan |
|---|---|---|
| "Oktober 2026" (subtitle di bawah judul halaman) | `iuran.png`, `iuran-terang.png`, `kas.png`, `kas-terang.png`, `kas-desktop.png` | Periode sudah dinyatakan chip aktif 40px di bawahnya; menghapusnya mengembalikan header ke satu baris dan menaikkan seluruh isi satu langkah |
| "5 belum" (sub-label tile LUNAS) | `iuran.png`, `iuran-terang.png` | Mengulang "5 anggota" di tile sebelahnya dan lima chip di bawahnya — satu fakta, tiga penulisan |
| "tersedia" (sub-label tile SALDO) | `kas.png`, `kas-terang.png`, `kas-desktop.png` | Kata status tanpa objek, tanpa aksi, tanpa data; saldo selalu "tersedia" |
| Glyph centang pada kelima chip "BELUM BAYAR" | `iuran.png`, `iuran-terang.png` | Bertentangan dengan label seksinya (problem 4); menghapusnya tidak menghilangkan informasi karena state sudah dibawa judul seksi |

Bukan untuk dihapus tetapi harus diformat ulang: "iuran Rp 1,95 jt" (`kas.png`, `kas-terang.png`, `kas-desktop.png`) — rincian komposisi ini informatif, tetapi satuannya harus mengikuti format nominal lain di panel yang sama. "3 catatan" dipertahankan: ia satu-satunya sub-label yang menambah informasi (jumlah entri) dan justru menjadi acuan bentuk bagi sub-label lain.

---

## 6. Keep

1. **Kolom nominal yang tidak bergeser oleh tombol hapus** (`kas.png`, `iuran.png`: tepi kanan 328/329; `kas-desktop.png`: 1149; gutter hapus 336..369 / 1156..1189 selalu dicadangkan) — inilah yang membuat baris terbaca sebagai buku kas dan bukan daftar kartu. Jangan biarkan nominal bergeser saat tombol hapus muncul atau hilang, dan jangan ubah baris menjadi kartu saat merapikan warna uang.
2. **Chip periode aktif yang terisi dengan label terbalik** (`iuran.png`, `kas.png` dark: label gelap di atas `#35D07F`; `iuran-terang.png`, `kas-terang.png` light: label putih di atas hijau tua) — state aktif terbaca dalam grayscale tanpa mengandalkan warna, jadi jangan diratakan menjadi underline atau teks berwarna saja saat memperbaiki D8.
