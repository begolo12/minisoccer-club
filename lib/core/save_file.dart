/// Penyimpan berkas di web: unduh lewat `<a download>` + Blob.
///
/// APK tidak punya lokasi unduhan yang bisa dibuka tanpa izin penyimpanan
/// dan tanpa sheet berbagi, jadi di sana data dibagikan lewat clipboard —
/// `canSaveFile` memberi tahu pemanggil jalur mana yang tersedia.
library;

export 'save_file_stub.dart' if (dart.library.js_interop) 'save_file_web.dart';
