/// Pemuatan yang boleh gagal sebagian.
///
/// Halaman seperti Beranda menjalankan belasan query sekaligus. Dengan
/// `Future.wait` biasa, satu tabel yang izinnya belum diberikan (mis.
/// `v_team_standings` untuk role `app_web`) membuat **seluruh** halaman
/// menampilkan "Gagal memuat data" — padahal 12 query lain berhasil. Helper
/// ini mencatat sumber yang gagal, lalu halaman menampilkan sisanya plus satu
/// baris peringatan yang menyebut nama sumbernya.
library;

import 'errors.dart';

class Soft<T> {
  const Soft._({this.value, this.error, required this.label});

  /// Nilai hasil, atau [fallback] kalau gagal. Tidak pernah null untuk T
  /// non-nullable.
  final T? value;
  final String? error;
  final String label;

  bool get ok => error == null;
}

/// Jalankan [load]; kegagalan dikembalikan sebagai [Soft.error], bukan
/// dilempar. [fallback] dipakai saat gagal supaya kode pemanggil tidak perlu
/// menangani null di setiap tempat.
Future<Soft<T>> soft<T>(
  String label,
  Future<T> Function() load, {
  required T fallback,
}) async {
  try {
    return Soft._(value: await load(), label: label);
  } catch (e) {
    // `fallback` WAJIB dipakai: pemanggil menulis `value!` untuk sumber yang
    // berhasil, dan nilai null di sini membuat seluruh halaman meledak
    // dengan "Null check operator used on a null value" — persis yang
    // terjadi di produksi saat `v_team_standings` belum ada.
    return Soft._(value: fallback, error: errText(e), label: label);
  }
}

/// Kumpulan sumber yang gagal, siap ditampilkan sebagai satu baris.
String describeFailures(Iterable<Soft<Object?>> items) {
  final failed = items.where((s) => !s.ok).toList();
  if (failed.isEmpty) return '';
  return failed.map((s) => '${s.label} (${s.error})').join(' • ');
}

/// Satu baris per sumber yang gagal: "Label: pesan". Bentuk ini dipakai
/// `DegradedNotice`, yang menampilkan tiap sumber sebagai baris sendiri.
List<String> failuresOf(Iterable<Soft<Object?>> items) => [
      for (final s in items)
        if (!s.ok) '${s.label}: ${s.error}',
    ];

/// Tutup kumpulan [Soft] yang sudah dijalankan paralel.
///
/// Semua gagal = server atau jaringan mati, bukan satu tabel yang izinnya
/// belum ada. Untuk kasus itu halaman menampilkan layar error penuh dengan
/// tombol coba lagi — lebih jujur daripada halaman kosong yang terlihat
/// seperti "belum ada data". Sebagian gagal = data yang berhasil tetap
/// tampil, dan daftar kegagalannya dikembalikan untuk [DegradedNotice].
List<String> settle(Iterable<Soft<Object?>> items) {
  final list = items.toList();
  if (list.isNotEmpty && list.every((s) => !s.ok)) {
    throw Exception(list.first.error);
  }
  return failuresOf(list);
}
