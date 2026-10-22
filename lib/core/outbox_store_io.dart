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

Future<String?> readOutbox() async {
  try {
    final f = await _outboxFile();
    if (!f.existsSync()) return null;
    return await f.readAsString();
  } catch (_) {
    return null;
  }
}

Future<void> writeOutbox(String json) async {
  try {
    final f = await _outboxFile();
    // Nama sementara unik per penulisan, lalu rename atomik. Nama tetap
    // (`outbox.json.tmp`) akan saling menimpa kalau dua penulisan terjadi
    // berdekatan; rename tetap atomik di sistem berkas yang sama.
    final tmp = File('${f.path}.${DateTime.now().microsecondsSinceEpoch}.tmp');
    await tmp.writeAsString(json, flush: true);
    await tmp.rename(f.path);
  } catch (_) {
    // Gagal menyimpan antrean = kehilangan data offline. Tidak bisa
    // dilempar ke UI di sini; pemanggil mencatat lewat `Outbox.loadError`.
  }
}
