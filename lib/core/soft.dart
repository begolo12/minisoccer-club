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
    return Soft._(error: errText(e), label: label);
  }
}

/// Kumpulan sumber yang gagal, siap ditampilkan sebagai satu baris.
String describeFailures(Iterable<Soft<Object?>> items) {
  final failed = items.where((s) => !s.ok).toList();
  if (failed.isEmpty) return '';
  return failed.map((s) => '${s.label} (${s.error})').join(' • ');
}
