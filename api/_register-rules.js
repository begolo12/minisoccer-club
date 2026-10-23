// Aturan formulir pendaftaran anggota.
//
// Dipisah dari `register.js` supaya bisa diuji tanpa memasang dependensi
// database: `register.js` mengimpor `@neondatabase/serverless` saat dimuat,
// sedangkan aturan di sini murni fungsi.
//
// Salinan aturan yang sama ada di `lib/core/registration.dart` untuk klien;
// server tetap memeriksa ulang semuanya.

export const POSITIONS = ['Kiper', 'Bek', 'Gelandang', 'Penyerang', 'Bebas'];

/**
 * Nomor HP → bentuk baku `08xxxxxxxxxx`, atau null kalau tidak masuk akal.
 *
 * Orang menulis nomor dengan cara berbeda: `0812-3456-7890`, `+62 812 3456
 * 7890`, `62812...`. Semua bentuk itu harus menjadi satu nilai, karena nomor
 * inilah yang dipakai sebagai password awal dan sebagai penanda "sudah
 * terdaftar".
 */
export function cleanPhone(raw) {
  let digits = String(raw ?? '').replace(/\D/g, '');
  if (!digits) return null;
  if (digits.startsWith('62')) digits = `0${digits.slice(2)}`;
  if (digits.startsWith('8')) digits = `0${digits}`;
  if (!digits.startsWith('0')) return null;
  if (digits.length < 9 || digits.length > 15) return null;
  return digits;
}

/** Rapikan nama: spasi berlebih dibuang, huruf disimpan apa adanya. */
export function cleanName(raw) {
  return String(raw ?? '').trim().replace(/\s+/g, ' ');
}

/**
 * Nama depan → dasar username: huruf kecil, hanya huruf/angka, maks 20.
 *
 * Contoh: "Irvan Nur Cahyo" → "irvan"; "M. Rizky" → "m"; "Ade" → "ade".
 * Kalau hasilnya terlalu pendek (mis. "M."), dipakai nama lengkap yang
 * disanitasi supaya usernamenya tetap bisa diketik dan diingat.
 */
export function usernameBase(name) {
  const clean = cleanName(name);
  const words = clean.split(' ').filter(Boolean);
  const first = (words[0] ?? '').toLowerCase().replace(/[^a-z0-9]/g, '');
  if (first.length >= 3) return first.slice(0, 20);
  const whole = clean.toLowerCase().replace(/[^a-z0-9]/g, '');
  return (whole || 'anggota').slice(0, 20);
}

/** Calon username ke-[n]: dasar, lalu dasar2, dasar3, … */
export function usernameCandidate(base, n) {
  if (n <= 1) return base;
  return `${base.slice(0, 20 - `${n}`.length)}${n}`;
}

/**
 * Validasi isian formulir. Semua wajib diisi.
 *
 * Return `{ ok: true, value }` atau `{ ok: false, error }` dengan pesan yang
 * bisa langsung ditampilkan di formulir.
 */
export function validateRegistration(body) {
  const name = cleanName(body?.name);
  if (name.length < 3) return { ok: false, error: 'Nama wajib diisi, minimal 3 huruf' };
  if (name.length > 60) return { ok: false, error: 'Nama terlalu panjang (maks 60 huruf)' };
  if (!/[a-zA-Z]/.test(name)) return { ok: false, error: 'Nama harus berisi huruf' };
  if (!/^[a-zA-Z .'-]+$/.test(name)) {
    return { ok: false, error: 'Nama hanya boleh berisi huruf, spasi, titik, dan tanda hubung' };
  }

  const phone = cleanPhone(body?.phone);
  if (!phone) {
    return { ok: false, error: 'Nomor HP wajib diisi, contoh 081234567890' };
  }

  const address = String(body?.address ?? '').trim().replace(/\s+/g, ' ');
  if (address.length < 5) return { ok: false, error: 'Alamat wajib diisi, minimal 5 huruf' };
  if (address.length > 200) return { ok: false, error: 'Alamat terlalu panjang (maks 200 huruf)' };

  const position = String(body?.position ?? '').trim();
  if (!POSITIONS.includes(position)) {
    return { ok: false, error: 'Pilih posisi bermain' };
  }

  return { ok: true, value: { name, phone, address, position } };
}

