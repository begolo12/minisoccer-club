/// Versi non-web: tidak ada dokumen, jadi tidak ada prefiks jalur.
///
/// APK selalu di-build dengan `API_BASE` absolut, sehingga prefiks tidak
/// diperlukan. Berkas ini dipakai saat `dart.library.js_interop` tidak tersedia
/// (Android/iOS/desktop), supaya `package:web` tidak ikut terkompilasi.
library;

String documentPathPrefix() => '';
