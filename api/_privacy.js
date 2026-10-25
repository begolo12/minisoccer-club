// Privasi data anggota.
//
// Aplikasi ini sengaja bisa dibuka TANPA login (mode publik): jadwal,
// kas, dan iuran klub boleh dilihat siapa pun. Tapi daftar anggota yang
// lengkap dengan nomor HP dan alamat tinggal adalah data pribadi, dan
// `members` punya kolom itu — sehingga "SELECT * FROM members" cukup untuk
// mengambil semuanya dalam satu permintaan.
//
// Yang dilindungi di sini:
//   * `address` (alamat rumah) — hanya admin dan bendahara.
//   * `phone` (nomor HP) — juga hanya admin, bendahara, dan anggota yang
//     sudah masuk. Tamu tidak: nomor HP tidak perlu diketahui orang luar.
//
// Dua lapis, karena satu lapis bisa dilewati:
//   1. `scrubRows` membuang kunci sensitif dari hasil query — menutup
//      `SELECT *`, `m.*`, `row_to_json(m)`, dan `json_agg(members)`, yang
//      tidak bisa dicek dari teks query-nya.
//   2. `mentionsHidden` menolak query yang MENYebut kolom sensitif secara
//      eksplisit — menutup `count(phone)`, `WHERE phone LIKE ...`, dan
//      `md5(phone)`, yang tidak menghasilkan kolom namedrai untuk disaring.

/// Kolom yang disembunyikan untuk role ini.
export function hiddenColumns(role) {
  if (role === 'admin' || role === 'treasurer') return [];
  if (role === 'member') return ['address'];
  return ['address', 'phone'];
}

/// Pesan penolakan yang menyebut kolom yang sebenarnya diblokir.
///
/// Satu pesan untuk semua kolom ("data pribadi tidak boleh diakses")
/// membuat pengguna tidak tahu mana yang sebenarnya ditolak, dan
/// query-nya sulit ditelusuri. Jadi kolom yang disebut di query yang
/// jadi penentu pesannya — bukan sekadar kolom pertama yang tersembunyi.
export function hiddenColumnMessage(sql, hidden) {
  const mentioned = hidden.find((col) => new RegExp(`\\b${col}\\b`, 'i').test(sql));
  if (mentioned === 'address') return 'Alamat anggota hanya untuk admin dan bendahara';
  if (mentioned === 'phone') return 'Nomor HP anggota hanya untuk anggota yang sudah masuk';
  if (hidden.includes('address')) return 'Alamat anggota hanya untuk admin dan bendahara';
  if (hidden.includes('phone')) return 'Nomor HP anggota hanya untuk anggota yang sudah masuk';
  return 'Data anggota ini tidak bisa diakses';
}

/// Apakah query menyebut salah satu kolom tersembunyi secara eksplisit.
///
/// Pencocokan memakai batas kata, jadi `m.phone` dan `"phone"` ikut kena
/// (keduanya ada kata `phone` di dalamnya), sementara `telepon` tidak —
/// kolom itu memang tidak ada.
export function mentionsHidden(sql, hidden) {
  if (!hidden || hidden.length === 0) return false;
  return hidden.some((col) => new RegExp(`\\b${col}\\b`, 'i').test(sql));
}

/// Buang kunci sensitif dari hasil query, termasuk di dalam objek bersarang.
///
/// Rows dari Postgres berisi `Map`/objek biasa; `json_agg` dan
/// `row_to_json` membungkus baris sebagai nilai JSON (string atau map),
/// jadi penyaringan harus masuk ke dalam struktur, bukan hanya ke atas.
export function scrubRows(rows, hidden) {
  if (!hidden || hidden.length === 0) return rows;
  return rows.map((row) => scrubValue(row, hidden));
}

function scrubValue(value, hidden) {
  if (value == null) return value;
  if (Array.isArray(value)) return value.map((v) => scrubValue(v, hidden));
  if (value instanceof Map) {
    const out = {};
    for (const [k, v] of value.entries()) {
      if (hidden.includes(String(k).toLowerCase())) continue;
      out[k] = scrubValue(v, hidden);
    }
    return out;
  }
  if (typeof value === 'object') {
    // Objek biasa (hasil jsonDecode) —>sanitasi berarti memeriksa
    // keberadaannya sebagai properti.
    const out = {};
    for (const [k, v] of Object.entries(value)) {
      if (hidden.includes(String(k).toLowerCase())) continue;
      out[k] = scrubValue(v, hidden);
    }
    return out;
  }
  if (typeof value === 'string') {
    // Hasil json_agg bertipe string JSON. Buang kuncinya di dalam string,
    // lalu kembalikan sebagai string supaya bentuk respons tidak berubah.
    const trimmed = value.trim();
    if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return value;
    try {
      const parsed = JSON.parse(trimmed);
      return JSON.stringify(scrubValue(parsed, hidden));
    } catch {
      return value;
    }
  }
  return value;
}
