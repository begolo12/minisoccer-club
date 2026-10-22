/// Teks error yang bisa dibaca user.
///
/// `Exception(...)` dan `ApiException(...)` dari model sudah berbahasa
/// Indonesia dan ditujukan ke user; prefix kelasnya hanya noise —
/// "Exception: Sudah ada laga dengan skor" tidak lebih jelas daripada
/// "Sudah ada laga dengan skor".
library;

String errText(Object e) => e
    .toString()
    .replaceFirst(RegExp(r'^(Exception|ApiException):\s*'), '')
    .trim();
