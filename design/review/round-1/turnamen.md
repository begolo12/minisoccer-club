# Review — Turnamen + Statistik (round 1)

Metode: reviewer manual §2 (存量界面润色评审) — hanya menyelaraskan ke spesifikasi produk, tanpa skor, tanpa mengganti warna/font/navigasi.
Bukti: 5 PNG statis di `design/current/` (semua benar-benar dibuka): `turnamen.png` 780x1688 (=390x844@2x), `turnamen-desktop.png` 1440x900, `detail-turnamen.png` 390x1400, `detail-turnamen-desktop.png` 1440x900, `statistik.png` 390x844.
Semua koordinat di bawah diukur dari PNG (piksel logis, bukan device px kecuali disebut @2x).

---

## 1. Checklist

### Masalah (urut dampak)

- **[problem 1]** `turnamen.png` + `statistik.png` / seluruh frame: tidak ada bottom nav (area y=750–844 pada `statistik.png` dan ~61% bawah `turnamen.png` murni #080B09), padahal `beranda-hp.png` dan `tanding.png` pada ukuran yang sama menampilkan nav 5 item dengan state aktif → layar phone yang di-review harus menampilkan bottom nav dengan item aktif yang sama seperti `beranda-hp.png`; layar ini tidak boleh tampil sebagai halaman tanpa kerangka.
- **[problem 2]** `turnamen-desktop.png` + `detail-turnamen-desktop.png` / seluruh frame: rail 216px tidak ada (0 piksel non-base di x<216, sedangkan `beranda-desktop.png` punya hairline rail di x=215 + item aktif "Beranda"), dan kolom konten ter-center di 1440 (250..1189) → rail 216px harus muncul dan kolom konten (≤980) ter-center di area 216..1440, bukan di seluruh lebar viewport.
- **[problem 3]** `detail-turnamen.png` + `detail-turnamen-desktop.png` / header: state turnamen tidak pernah disebut (tidak ada kata BERJALAN/DRAFT/SELESAI), strip menaruh angka beraksen terbesar pada estimasi "21.00", dan satu-satunya aksi header adalah ikon hapus → header harus menyatakan state dengan kata yang sama seperti daftar, aksen terbesar dipakai untuk progres laga (4/6), dan hapus bukan lagi satu-satunya aksi header (aksi yang relevan dengan state sudah ada di `beranda-hp.png`: "Isi hasil").
- **[problem 4]** `turnamen.png` + `turnamen-desktop.png` / baris daftar: tidak ada isyarat urutan yang bisa dipakai sebelum membaca tepi kanan — state hanya kata kecil di x=294–344 (`turnamen.png`), posisi tanggal berubah antar baris ("20 Okt 19.00 • Lapangan Cimahi" vs "2 grup • 26 Okt 19.00 • Lapangan UPI"), baris BERJALAN tidak membawa progres 4/6 → tanggal harus mulai di kolom x yang sama untuk semua baris, urutan berjalan→akan datang→selesai terbaca tanpa membaca tepi kanan, dan baris BERJALAN memuat progres yang sama dengan `beranda-hp.png`.
- **[problem 5]** `detail-turnamen.png` / baris JADWAL: durasi per laga hanya ada di strip ("20 menit/laga"), subtitle baris berisi "G1 • B1" yang tidak terbaca, dan blok laga mulai di x=153 sementara jam mulai di x=32 (left-to-left 121px; margin kiri 133 vs kanan 83 dalam baris 20..369) → tiap baris jadwal memuat durasi sehingga jam selesai tiap laga bisa dibaca dari barisnya, singkatan diganti label terbaca, dan gap meta→laga tidak lebih besar dari satu tinggi baris.
- **[problem 6]** `statistik.png` / daftar PENCETAK GOL: "Semua 11" tidak punya satuan dan tidak bisa direkonsiliasi (5 baris tampil = 9 gol, strip menulis GOL 12), dan dua baris bernilai 3 gol punya perlakuan bar berbeda (baris 1 #35D07F penuh, baris 2 #236E46) → label ekspansi menyebut satuannya dan angkanya cocok dengan GOL 12, dan dua nilai identik mendapat panjang + warna bar identik.

### Peningkatan

- **[improvement 1]** `detail-turnamen.png` / strip: tile TIM ("4") tidak punya caption sementara dua tile lain punya ("selesai", "20 menit/laga"), jadi baseline ketiga kolom ragged → ketiga tile punya satu baris caption yang sama, atau tidak ada caption sama sekali.
- **[improvement 2]** `detail-turnamen.png` vs `beranda-hp.png` / progres 4/6: bar yang sama dirender di luar Panel (y=197–201, 11px di bawah border kartu y=186) di detail, tapi di dalam kartu di beranda → satu treatment untuk objek yang sama.
- **[improvement 3]** `statistik.png` + `detail-turnamen.png` / kolom POIN: seluruh kolom beraksen hijau, termasuk 0 poin, sehingga aksen tidak menandai apa pun → aksen menandai satu hal saja (mis. pemimpin), sisanya netral.
- **[improvement 4]** `statistik.png` / caption strip: "3.0 per laga" memakai titik desimal Inggris sementara jam di layar lain memakai titik sebagai pemisah Indonesia, dan "bobol 10" adalah fragmen → "3,0 per laga" dan "kebobolan 10".
- **[improvement 5]** `statistik.png` / KLASEMEN TIM: Tim B dan Tim D identik di semua kolom yang terlihat (M 2, SG +3, POIN 4) tapi diberi peringkat 1 dan 2 → pada 390px, dua baris identik tidak diberi urutan berbeda tanpa kolom pembeda yang terlihat (kolom GM/GK sudah ada di `detail-turnamen-desktop.png`).

Yang sudah bersih (satu baris): proporsi bar `statistik.png` akurat — 3 gol = 322px, 1 gol = 108px (rasio 2,98 vs 3,0), dan tabel KLASEMEN di `statistik.png` / `detail-turnamen.png` tidak terpotong di 390px.

---

## 2. Penyimpangan spesifikasi

| # | Penyimpangan | Bukti (file / lokasi terukur) |
|---|---|---|
| 1 | Bottom nav tidak dirender (spesifikasi: phone = bottom nav) | `turnamen.png` (y=332–844 kosong, tidak ada nav), `statistik.png` (y=750–844 kosong). Pembanding yang benar: `beranda-hp.png`, `tanding.png` |
| 2 | Rail 216px tidak dirender (spesifikasi: desktop ≥900 = rail 216px) | `turnamen-desktop.png`, `detail-turnamen-desktop.png`: 0 piksel non-base di x<216; `beranda-desktop.png` punya hairline rail di x=215 |
| 3 | Kolom konten desktop tidak memperhitungkan rail | `turnamen-desktop.png`, `detail-turnamen-desktop.png`: konten 250..1189 (940px, center di 1440). Spesifikasi: rail 216 + konten ≤980 → seharusnya ter-center di 216..1440 |
| 4 | Hairline header tidak sejajar dengan hairline baris | `turnamen-desktop.png`, `detail-turnamen-desktop.png`: rule header x=259..1180, rule baris x=250..1189, judul mulai x=250 — inset 9px yang tidak cocok dengan apa pun |
| 5 | Hairline header beda perilaku antar breakpoint | `turnamen.png` (0..779, full-bleed) dan `statistik.png` (0..389, full-bleed) vs `turnamen-desktop.png` (inset 259..1180) |
| 6 | Dua treatment kontainer tanpa beda makna | `statistik.png` + `turnamen.png` + `detail-turnamen.png`: StatStrip = outline #202C25 di atas base #080B09 (interior #080B09); StandingsTable/roster = kartu terisi #0E1512. Spesifikasi hanya mendefinisikan satu warna card |
| 7 | Warna di luar palet | `statistik.png`: track bar #141D18 dan fill non-pemimpin #236E46. Palet hanya punya aksen #35D07F, card #0E1512, hairline #202C25 |
| 8 | Daftar berupa kartu bertumpuk, bukan RowItem | `detail-turnamen.png` bagian PEMAIN PER TIM: tiga Panel ber-border (Tim A/B/C) masing-masing berisi chip ber-border → dua tingkat border bersarang. Spesifikasi: "Lists are hairline rows (RowItem), never stacked cards" |
| 9 | Pill tidak dipakai untuk status | `turnamen.png`: "BERJALAN" dan "DRAFT" adalah teks polos tanpa shape/ruang; tidak ada komponen Pill di kelima layar, padahal Pill ada di daftar komponen wajib |
| 10 | Tidak ada merah di lima layar | `turnamen.png`, `turnamen-desktop.png`, `detail-turnamen.png`, `detail-turnamen-desktop.png`, `statistik.png` — sesuai aturan "merah hanya untuk gagal/terlambat". Tidak ada gradient dan drop shadow di kelima layar |
| 11 | SectionTitle konsisten | Semua label seksi (DAFTAR TURNAMEN, KLASEMEN, JADWAL, PEMAIN PER TIM, PENCETAK GOL, KLASEMEN TIM) kecil, uppercase, dengan rule ke tepi kanan — sesuai spesifikasi |
| 12 | Tidak bisa diverifikasi dari raster | Barlow Condensed vs substitusi, tabular figures, dan positive tracking tidak bisa dipastikan dari satu frame; light theme dan aturan role "member" juga tidak ada di kelima screenshot ini |

Catatan lintas-build (bukan tugas layar ini, tapi penyebabnya sama): `kas-desktop.png` juga tanpa rail, jadi ketiadaan rail bukan cacat dua file ini saja.

---

## 3. Tiga masalah layout/structure terbesar

### T1 — `turnamen.png` / `turnamen-desktop.png`: daftar bukan pemilik frame, dan isyarat urutan ada di titik terlemah layar
- **Lokasi:** area daftar setelah strip + seluruh area kosong di bawah baris terakhir.
- **Bukti:** `turnamen.png` — separator baris terakhir di y=332 dari 844 (61% viewport kosong); `turnamen-desktop.png` — konten berakhir y≈332 dari 900 (63% kosong). State hanya kata di x=294–344 dengan chevron di 358–363, jadi terbaca paling akhir. Tanggal pindah posisi: baris 1 "20 Okt 19.00 • Lapangan Cimahi", baris 2 "2 grup • 26 Okt 19.00 • Lapangan UPI". Strip (TURNAMEN 2 / BERJALAN 1 / SELESAI 0) hanya menghitung ulang dua baris yang langsung terlihat di bawahnya.
- **Dampak:** halaman terbaca sebagai layar belum jadi (dua baris lalu kosong), dan saat turnamen bertambah, satu-satunya cara mengurutkan adalah membaca teks kecil di tepi kanan — tepat di titik yang paling jauh dari awal baris.
- **Target:** (a) tanggal mulai di kolom x yang sama untuk semua baris; (b) state terbaca tanpa membaca tepi kanan — mis. dikelompokkan dengan SectionTitle BERJALAN / AKAN DATANG / SELESAI, dan strip 3 tile yang hanya menghitung ulang daftar dihapus untuk membayar ruangnya; (c) daftar mengisi frame sampai nav, bukan berhenti di 40% tinggi.
- **Verifikasi:** crop 60% kiri tiap baris → tanggal mulai di x yang sama; screenshot 390x844 → baris terakhir berhenti di atas bottom nav, bukan di y≈332; strip 3 tile tidak lagi ada.

### T2 — `detail-turnamen(-desktop).png`: baris JADWAL punya gutter mati dan tidak berbagi anchor
- **Lokasi:** bagian JADWAL, keenam baris.
- **Bukti:** `detail-turnamen-desktop.png` — jam mulai x=262, "Tim A" mulai x=678: 416px antar-left-edge = 44% lebar baris (250..1189); blok laga 678..811, center ≈744 sedangkan center baris 720, jadi bukan center dan bukan rata kiri. `detail-turnamen.png` — jam x=32, blok laga x=153..287 di baris 20..369 (margin kiri 133, kanan 83). Anchor kiri di satu halaman: 20 (label seksi + separator), 32 (jam), 37 (nomor peringkat), 58 (nama tim di tabel KLASEMEN), 153 (tim di JADWAL) — lima left edge dalam 133px.
- **Dampak:** jam dan laga terbaca sebagai dua kolom terpisah, mata harus melompat 400px untuk menggabungkan satu baris; hubungan "jam ini milik laga ini" jadi lemah.
- **Target:** satu jalur baca per baris — kolom meta lebar tetap, blok laga mulai di anchor yang dipakai elemen lain di kolom itu; gutter ≤ satu tinggi baris.
- **Verifikasi:** ukur left edge "Tim A"/"Tim C"/"Tim B" di keenam baris (harus satu x), dan gap kolom meta→blok laga (bukan 416px di 1440).

### T3 — `detail-turnamen.png`: PEMAIN PER TIM adalah kartu bertumpuk + 20+ target hapus
- **Lokasi:** bagian PEMAIN PER TIM, tiga kartu Tim A/B/C.
- **Bukti:** tiga Panel ber-border berisi grid chip ber-border, tiap chip membawa "×" (8 di Tim A, 8 di Tim B, sisanya Tim C) — dua tingkat border bersarang dan puluhan glyph hapus kecil permanen di satu layar.
- **Dampak:** bagian paling bawah halaman jadi dinding kotak yang bersaing dengan KLASEMEN dan JADWAL, dan hapus-per-pemain menjadi aksi yang selalu terlihat (paling mudah tersenggol) padahal bukan tugas utama halaman.
- **Target:** roster dibaca lewat hairline row + label seksi (satu tingkat border, sesuai RowItem), dan hapus bukan affordance permanen per pemain.
- **Verifikasi:** hitung tingkat border di bagian itu (harus satu), dan tidak ada lagi glyph "×" yang menempel di tiap nama pada frame 390.

---

## 4. Motion

Motion/interaction not verified — bukti hanya frame statis, tanpa preview server dan tanpa interaksi. Tidak ada klaim soal transisi, urutan muat, atau alur (termasuk apakah "Semua 11" benar-benar membuka daftar penuh, dan apakah chevron baris membuka detail).

---

## 5. Teks dan elemen yang bisa dihapus

| String / elemen | Screenshot | Alasan |
|---|---|---|
| "Tim klub • klasemen per grup" | `turnamen.png` | Menjelaskan fitur, bukan data atau aksi; tidak menunjuk objek apa pun |
| "DAFTAR TURNAMEN" | `turnamen.png` | Mengulang judul halaman "Turnamen internal"; menghapusnya menaikkan daftar satu baris |
| "2 grup" | `turnamen.png` (baris 2) | Angka grup tanpa tampilan grup di layar ini; juga satu-satunya baris yang field-nya beda urutan |
| "Rekap hasil & pencetak gol" | `statistik.png` | Subtitle deskriptif, bukan data |
| "Semua 11" | `statistik.png` | Satuannya tidak jelas dan tidak cocok dengan 9 gol yang terlihat / GOL 12 — perjelas satuannya atau hapus |
| "×" pada setiap chip pemain | `detail-turnamen.png` | 20+ target hapus permanen; hapus per pemain bukan aksi utama halaman |
| Strip TURNAMEN 2 / BERJALAN 1 / SELESAI 0 | `turnamen.png` | Hanya menghitung ulang dua baris yang tampil langsung di bawahnya; ruangnya lebih berguna untuk pengelompokan status |

"G1 • B1" (`detail-turnamen.png`) bukan untuk dihapus tapi diganti: singkatan itu tidak terbaca dan menempati slot yang seharusnya memuat durasi laga.

---

## 6. Keep

1. **Pewarnaan nama pemenang di JADWAL** (`detail-turnamen.png`: "Tim A" hijau pada 3–1 dan 2–0, "Tim D" hijau pada 1–2, seri 1–1 keduanya netral) — ini satu-satunya tempat aksen membawa makna yang tidak bisa diganti teks; jangan diratakan jadi "skor hijau" saat merapikan baris.
2. **Daftar turnamen sebagai hairline row datar** (`turnamen.png`: ikon trofi + judul + subtitle + status, tanpa kartu dan tanpa pill) — permukaan datar inilah yang membuat layar ini terasa papan skor, bukan dashboard SaaS; perbaiki urutan/state-nya tanpa mengubahnya jadi tumpukan kartu.
