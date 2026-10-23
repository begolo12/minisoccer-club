/// Aturan formulir pendaftaran anggota, dipakai bersama oleh UI dan tes.
///
/// Aturannya SAMA dengan `api/register.js`. Server tetap memeriksa ulang
/// semuanya — salinan di klien hanya supaya kesalahan ketahuan sebelum
/// dikirim, bukan setelah menunggu jaringan.
library;

/// Pilihan posisi bermain. Harus sama dengan `POSITIONS` di server.
const kPositions = <String>['Kiper', 'Bek', 'Gelandang', 'Penyerang', 'Bebas'];

/// Rapikan nama: spasi berlebih dibuang.
String cleanName(String raw) => raw.trim().replaceAll(RegExp(r'\s+'), ' ');

/// Nomor HP → bentuk baku `08xxxxxxxxxx`, atau null kalau tidak masuk akal.
///
/// Menerima `0812-3456-7890`, `+62 812 3456 7890`, dan `62812...`; semuanya
/// menjadi satu nilai karena nomor inilah yang dipakai sebagai password awal
/// dan sebagai penanda "sudah terdaftar".
String? normalizePhone(String raw) {
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;
  if (digits.startsWith('62')) digits = '0${digits.substring(2)}';
  if (digits.startsWith('8')) digits = '0$digits';
  if (!digits.startsWith('0')) return null;
  if (digits.length < 9 || digits.length > 15) return null;
  return digits;
}

/// Nama depan → dasar username: huruf kecil, hanya huruf/angka, maks 20.
///
/// Sama dengan `usernameBase` di server. Kalau nama depan terlalu pendek
/// (mis. "M. Rizky"), dipakai nama lengkap yang disanitasi supaya username
/// tetap bisa diketik.
String usernameBase(String name) {
  final clean = cleanName(name);
  final words = clean.split(' ').where((w) => w.isNotEmpty).toList();
  final first = words.isEmpty
      ? ''
      : words.first.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  if (first.length >= 3) return first.substring(0, first.length > 20 ? 20 : first.length);
  final whole = clean.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  final base = whole.isEmpty ? 'anggota' : whole;
  return base.substring(0, base.length > 20 ? 20 : base.length);
}

/// Kesalahan nama, atau null kalau sah.
String? nameError(String raw) {
  final name = cleanName(raw);
  if (name.length < 3) return 'Nama wajib diisi, minimal 3 huruf';
  if (name.length > 60) return 'Nama terlalu panjang (maks 60 huruf)';
  if (!RegExp(r'[a-zA-Z]').hasMatch(name)) return 'Nama harus berisi huruf';
  if (!RegExp(r"^[a-zA-Z .'-]+$").hasMatch(name)) {
    return 'Nama hanya boleh berisi huruf, spasi, titik, dan tanda hubung';
  }
  return null;
}

/// Kesalahan nomor HP, atau null kalau sah.
String? phoneError(String raw) =>
    normalizePhone(raw) == null ? 'Nomor HP wajib diisi, contoh 081234567890' : null;

/// Kesalahan alamat, atau null kalau sah.
String? addressError(String raw) {
  final address = cleanName(raw);
  if (address.length < 5) return 'Alamat wajib diisi, minimal 5 huruf';
  if (address.length > 200) return 'Alamat terlalu panjang (maks 200 huruf)';
  return null;
}

/// Kesalahan posisi, atau null kalau sah.
String? positionError(String? value) =>
    kPositions.contains(value) ? null : 'Pilih posisi bermain';

/// Apakah alamat halaman ini adalah tautan pendaftaran?
///
/// Web bisa dipasang di akar domain maupun di bawah jalur portal
/// (`/minisoccer/daftar`), dan Flutter web memakai strategi hash secara
/// default (`/#/daftar`), jadi jalur maupun fragmen diperiksa.
bool isRegisterLocation(Uri uri) {
  String tail(String s) {
    final parts = s
        .replaceAll(RegExp(r'/+$'), '')
        .split('/')
        .where((p) => p.isNotEmpty)
        .toList();
    return parts.isEmpty ? '' : parts.last;
  }

  return tail(uri.path) == 'daftar' || tail(uri.fragment) == 'daftar';
}
