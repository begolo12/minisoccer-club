/// Cache offline untuk platform dengan `dart:io` (Android, desktop).
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'cache.dart';

class FileCacheStore implements CacheStore {
  Directory? _dir;

  /// Batas cache di disk.
  ///
  /// Sebelum ini setiap kombinasi query+params menghasilkan satu berkas dan
  /// tidak ada yang pernah menghapusnya: HP yang dipakai setahun akan
  /// mengumpulkan ribuan berkas JSON, dan pemindaian `listEntries` (dipakai
  /// penambalan offline) makin lambat di tiap tulis. Batasnya murah — data klub
  /// setahun jauh di bawah ini — dan yang dibuang selalu entri TERTUA, yang
  /// paling tidak berguna saat offline.
  ///
  /// ponytail: eviction berbasis "kapan disimpan", bukan "kapan terakhir
  /// dibaca". Kalau nanti ada query yang jarang berubah tapi sering dibaca,
  /// tambahkan sentuhan mtime di `readRows`.
  static const _maxFiles = 400;
  static const _maxBytes = 24 * 1024 * 1024;

  Future<Directory> _cacheDir() async {
    final cached = _dir;
    if (cached != null) return cached;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/query_cache');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _dir = dir;
    return dir;
  }

  /// Simpan satu entri. `sql` dan `params` ikut ditulis: penambal offline butuh
  /// tahu query asalnya untuk menentukan baris mana yang harus diubah.
  ///
  /// Ditulis ke berkas sementara lalu di-rename: kalau app dimatikan di tengah
  /// penulisan, berkas lama (atau tidak ada berkas) tetap utuh. Tanpa ini,
  /// JSON bisa terpotong dan entri itu dianggap tidak ada — padahal itu
  /// satu-satunya salinan untuk dibaca offline.
  @override
  Future<void> writeEntry(CacheEntry entry) async {
    try {
      final dir = await _cacheDir();
      final target = File('${dir.path}/${entry.key}.json');
      final tmp = File('${target.path}.tmp');
      await tmp.writeAsString(
        jsonEncode({
          'sql': entry.sql,
          'params': entry.params,
          'saved_at': entry.savedAt.toIso8601String(),
          'rows': entry.rows,
        }),
        flush: true,
      );
      await tmp.rename(target.path);
      await _evict(dir);
    } catch (_) {
      // Cache adalah optimasi: gagal menulis tidak boleh menggagalkan query.
    }
  }

  /// Buang entri tertua sampai jumlah dan ukuran kembali di bawah batas.
  ///
  /// Dipanggil setelah tulis, bukan di `listEntries`: hanya di sini jumlah
  /// berkas bertambah. Kegagalan diabaikan — cache yang kebesaran lebih baik
  /// daripada query yang gagal.
  Future<void> _evict(Directory dir) async {
    try {
      final files = <({File file, DateTime at, int size})>[];
      await for (final e in dir.list()) {
        if (e is! File || e.path.endsWith('.tmp')) continue;
        final st = await e.stat();
        files.add((file: e, at: st.modified, size: st.size));
      }
      var total = files.fold<int>(0, (s, f) => s + f.size);
      if (files.length <= _maxFiles && total <= _maxBytes) return;

      files.sort((a, b) => a.at.compareTo(b.at));
      var count = files.length;
      for (final f in files) {
        if (count <= _maxFiles && total <= _maxBytes) break;
        try {
          await f.file.delete();
          count--;
          total -= f.size;
        } catch (_) {
          // Berkas sedang dipakai: coba berikutnya.
        }
      }
    } catch (_) {
      // Direktori tidak terbaca: biarkan apa adanya.
    }
  }

  /// Semua entri cache. Entri lama (tanpa `sql`) dilewati karena tidak bisa
  /// ditambal — lebih baik hilang dari cache daripada menampilkan data basi.
  @override
  Future<List<CacheEntry>> listEntries() async {
    final out = <CacheEntry>[];
    try {
      final dir = await _cacheDir();
      await for (final e in dir.list()) {
        if (e is! File) continue;
        // Berkas sementara (`.tmp`) adalah penulisan yang belum selesai;
        // jangan dibaca sebagai entri sah.
        if (e.path.endsWith('.tmp')) continue;
        try {
          final raw = jsonDecode(await e.readAsString());
          if (raw is! Map) continue;
          final sql = raw['sql'];
          if (sql is! String || sql.isEmpty) continue;
          final rows = (raw['rows'] as List?) ?? const [];
          out.add(CacheEntry(
            key: e.uri.pathSegments.last.replaceAll(RegExp(r'\.json$'), ''),
            sql: sql,
            params: (raw['params'] as Map?)?.cast<String, Object?>() ?? const {},
            rows: rows.map((r) => Map<String, dynamic>.from(r as Map)).toList(),
            savedAt: DateTime.tryParse((raw['saved_at'] as String?) ?? '')?.toLocal() ??
                DateTime.now(),
          ));
        } catch (_) {
          // Satu berkas rusak tidak boleh menggagalkan penambalan entri lain.
        }
      }
    } catch (_) {
      // Direktori belum ada / tidak bisa dibaca.
    }
    return out;
  }

  @override
  Future<CachedRows?> readRows(String key) async {
    try {
      final dir = await _cacheDir();
      final file = File('${dir.path}/$key.json');
      if (!file.existsSync()) return null;
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return null;
      final rows = (raw['rows'] as List?) ?? const [];
      return CachedRows(
        rows.map((r) => Map<String, dynamic>.from(r as Map)).toList(),
        DateTime.tryParse((raw['saved_at'] as String?) ?? '')?.toLocal() ?? DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Buang seluruh cache (dipakai tombol "Kosongkan cache offline").
  @override
  Future<int> clear() async {
    try {
      final dir = await _cacheDir();
      var n = 0;
      await for (final e in dir.list()) {
        if (e is File) {
          await e.delete();
          n++;
        }
      }
      return n;
    } catch (_) {
      return 0;
    }
  }
}

CacheStore createCacheStore() => FileCacheStore();
