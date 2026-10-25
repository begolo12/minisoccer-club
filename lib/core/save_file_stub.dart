/// Versi non-web: tidak ada unduhan berkas.
///
/// APK bisa menulis ke disk (path_provider), tetapi berkas yang tidak bisa
/// ditemukan pengguna hanya menambah kebingungan. Data yang mau dibagikan
/// tetap lewat clipboard, jadi fitur ekspor tetap jalan di semua platform.
library;

bool get canSaveFile => false;

Future<void> saveTextFile(String name, String mime, String content) async {
  throw UnsupportedError('Unduhan berkas hanya tersedia di web');
}
