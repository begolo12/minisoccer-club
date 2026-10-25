/// Penyimpanan antrean tulis offline (Android/desktop: berkas JSON).
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

File? _file;

Future<File> _outboxFile() async {
  final cached = _file;
  if (cached != null) return cached;
  final base = await getApplicationSupportDirectory();
  final dir = Directory(base.path);
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final f = File('${dir.path}/outbox.json');
  _file = f;
  return f;
}

/// Baca isi antrean dari disk.
///
/// Kontrak: null HANYA berarti "belum pernah ada antrean". Kegagalan membaca
/// berkas yang ADA dilempar — kalau diubah jadi null, pemanggil menganggap
/// antreannya kosong dan penulisan berikutnya menimpa berkas yang belum
/// terbaca, menghapus seluruh tulisan offline yang belum terkirim.
Future<String?> readOutbox() async {
  final f = await _outboxFile();
  if (!f.existsSync()) return null;
  return f.readAsString();
}

/// Tulis antrean ke disk (tulis sementara + rename atomik).
///
/// Kegagalan DILEMPAR, bukan ditelan: `Outbox._persist` yang mencatatnya ke
/// `Outbox.loadError` supaya kehilangan penyimpanan tidak terjadi diam-diam
/// di balik banner "N perubahan menunggu".
Future<void> writeOutbox(String json) async {
  final f = await _outboxFile();
  // Nama sementara unik per penulisan, lalu rename atomik. Nama tetap
  // (`outbox.json.tmp`) akan saling menimpa kalau dua penulisan terjadi
  // berdekatan; rename tetap atomik di sistem berkas yang sama.
  final tmp = File('${f.path}.${DateTime.now().microsecondsSinceEpoch}.tmp');
  await tmp.writeAsString(json, flush: true);
  await tmp.rename(f.path);
}
