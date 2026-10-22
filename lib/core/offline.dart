/// Antrean tulis offline (outbox) — inti mode offline-first.
///
/// Alur:
///   1. Tulis dicoba ke server dulu (perilaku online tidak berubah).
///   2. Kalau gagal karena **jaringan**, tulis masuk antrean ini dan efeknya
///      ditambal ke cache (`row_patch.dart`), jadi pengguna melihat datanya
///      langsung dan bisa terus mengisi.
///   3. Saat jaringan kembali, antrean dikirim ulang **berurutan**. Karena
///      dikirim setelah keadaan cloud, tulisan lokal menimpa data cloud —
///      data offline yang diutamakan, sesuai yang diminta.
///
/// Antrean disimpan ke disk supaya tidak hilang saat app ditutup atau HP mati.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'net.dart';
import 'outbox_store.dart';
import 'row_patch.dart';

/// Satu tulis yang belum terkirim.
class PendingWrite {
  const PendingWrite({
    required this.seq,
    required this.sql,
    required this.params,
    required this.createdAt,
    this.tempId,
    this.failed = false,
    this.lastError,
  });

  final int seq;
  final String sql;
  final Map<String, Object?> params;
  final DateTime createdAt;

  /// Id sementara (negatif) untuk `INSERT ... RETURNING id`. Dipetakan ke id
  /// asli saat sinkron, lalu dipakai menulis ulang tulis berikutnya.
  final int? tempId;

  /// True kalau server menolak permanen (mis. baris induk sudah dihapus).
  /// Tetap disimpan supaya pengguna bisa melihat dan membuangnya sendiri.
  final bool failed;
  final String? lastError;

  PendingWrite copyWith({bool? failed, String? lastError}) => PendingWrite(
        seq: seq,
        sql: sql,
        params: params,
        createdAt: createdAt,
        tempId: tempId,
        failed: failed ?? this.failed,
        lastError: lastError ?? this.lastError,
      );

  Map<String, dynamic> toJson() => {
        'seq': seq,
        'sql': sql,
        'params': params,
        'created_at': createdAt.toIso8601String(),
        if (tempId != null) 'temp_id': tempId,
        if (failed) 'failed': true,
        if (lastError != null) 'last_error': lastError,
      };

  static PendingWrite? fromJson(Map<String, dynamic> m) {
    final sql = m['sql'];
    if (sql is! String || sql.isEmpty) return null;
    return PendingWrite(
      seq: (m['seq'] as num?)?.toInt() ?? 0,
      sql: sql,
      params: (m['params'] as Map?)?.cast<String, Object?>() ?? const {},
      createdAt: DateTime.tryParse((m['created_at'] as String?) ?? '') ?? DateTime.now(),
      tempId: (m['temp_id'] as num?)?.toInt(),
      failed: m['failed'] == true,
      lastError: m['last_error'] as String?,
    );
  }
}

/// Hasil satu kali sinkronisasi.
class SyncResult {
  const SyncResult({
    this.sent = 0,
    this.remaining = 0,
    this.failed = 0,
    this.offline = false,
    this.authExpired = false,
  });

  final int sent;
  final int remaining;
  final int failed;

  /// True kalau berhenti karena jaringan masih mati.
  final bool offline;

  /// True kalau berhenti karena sesi habis. Berbeda dari [offline]: pengguna
  /// harus masuk lagi, bukan menunggu sinyal — dan tanpa membedakannya, tombol
  /// Sinkron tampak "diam" tanpa penjelasan sampai token kedaluwarsa berhari-hari.
  final bool authExpired;

  bool get ok => remaining == 0 && failed == 0;
}

/// Antrean tulis yang belum tersimpan di server.
class Outbox {
  Outbox._();

  /// Jumlah tulis yang menunggu. Dipakai banner di shell.
  static final ValueNotifier<int> pending = ValueNotifier(0);

  /// True selama proses sinkron berjalan.
  static final ValueNotifier<bool> syncing = ValueNotifier(false);

  static final List<PendingWrite> _queue = [];
  static final Map<int, int> _idMap = {};
  static int _nextTempId = -1;
  static int _seq = 0;
  static bool _flushing = false;
  static bool _loaded = false;

  /// Kegagalan membaca antrean dari disk, kalau ada. Ditampilkan di
  /// Pengaturan supaya pengguna tahu datanya tidak hilang diam-diam.
  static String? loadError;

  /// Rantai penulisan disk. Semua `_persist()` berjalan berurutan lewat sini.
  ///
  /// Kenapa perlu: `enqueue()` bisa dipanggil saat `flush()` sedang berjalan
  /// (pengguna menambah data sementara sinkron berlangsung). Dua penulisan
  /// bersamaan ke berkas yang sama bisa saling menimpa — antrean yang baru
  /// masuk hilang, atau berkasnya jadi JSON rusak dan SELURUH antrean tidak
  /// terbaca. Satu rantai Future membuat penulisan selalu berurutan.
  static Future<void> _writeChain = Future.value();

  static List<PendingWrite> get items => List.unmodifiable(_queue);
  static int get failedCount => _queue.where((w) => w.failed).length;

  /// Muat antrean dari disk (sekali per proses).
  ///
  /// `_loaded` hanya diset setelah pembacaan **berhasil**. Dulu ia diset di
  /// baris pertama, sehingga satu kegagalan I/O sesaat (folder belum siap, HP
  /// penuh) membuat antrean dianggap kosong sepanjang sesi: banner tidak
  /// muncul, sinkron tidak pernah jalan, dan data hanya tersimpan di disk
  /// sampai app di-restart.
  static Future<void> load() async {
    if (_loaded) return;
    final raw = await readOutbox();

    // Tidak ada berkas = memang belum ada antrean. Ini bukan kegagalan.
    if (raw == null) {
      _loaded = true;
      return;
    }
    if (raw.trim().isEmpty) {
      _loaded = true;
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        // Isi tidak dikenali: jangan hapus, tapi jangan klaim termuat penuh
        // supaya percobaan berikutnya masih bisa membaca ulang.
        loadError = 'Antrean offline tidak terbaca (format tidak dikenali).';
        _loaded = true;
        return;
      }
      final list = (decoded['items'] as List?) ?? const [];
      for (final e in list) {
        if (e is! Map) continue;
        final w = PendingWrite.fromJson(Map<String, dynamic>.from(e));
        if (w != null) _queue.add(w);
      }
      final storedNext = (decoded['next_temp_id'] as num?)?.toInt();
      final storedSeq = (decoded['seq'] as num?)?.toInt();
      if (storedSeq != null) _seq = storedSeq;
      _nextTempId = storedNext ?? _nextTempId;
      // Pemetaan id sementara → id asli ikut disimpan: kalau app ditutup di
      // tengah sinkron, tulis berikutnya yang masih menunjuk id sementara
      // harus tetap memakai id asli yang sudah didapat.
      final map = (decoded['id_map'] as Map?) ?? const {};
      for (final e in map.entries) {
        final k = int.tryParse('${e.key}');
        final v = (e.value as num?)?.toInt();
        if (k != null && v != null) _idMap[k] = v;
      }
      // Jangan pernah memakai ulang id sementara yang masih ada di antrean.
      for (final w in _queue) {
        final t = w.tempId;
        if (t != null && t <= _nextTempId) _nextTempId = t - 1;
        if (w.seq >= _seq) _seq = w.seq + 1;
      }
      pending.value = _queue.length;
      loadError = null;
      _loaded = true;
    } catch (e) {
      // JSON rusak (mis. app dimatikan saat menulis). Antrean tidak bisa
      // dipulihkan otomatis, tapi pengguna harus tahu — bukan diam-diam
      // dianggap kosong.
      loadError = 'Antrean offline rusak dan tidak bisa dibaca.';
      _loaded = true;
    }
  }

  /// Masukkan tulis ke antrean. Return id sementara untuk
  /// `INSERT ... RETURNING id`, atau null untuk tulis biasa.
  static Future<int?> enqueue(String sql, Map<String, Object?> params) async {
    await load();
    final op = parseWrite(sql, params);
    final tempId = (op?.returnsId ?? false) ? _nextTempId-- : null;
    _queue.add(PendingWrite(
      seq: _seq++,
      sql: sql,
      params: params,
      createdAt: DateTime.now(),
      tempId: tempId,
    ));
    pending.value = _queue.length;
    await _persist();
    return tempId;
  }

  /// Ganti id sementara di parameter dengan id asli hasil sinkron.
  static Map<String, Object?> _rewrite(Map<String, Object?> params) {
    if (_idMap.isEmpty) return params;
    var changed = false;
    final out = <String, Object?>{};
    for (final e in params.entries) {
      final v = e.value;
      if (v is int && v < 0 && _idMap.containsKey(v)) {
        out[e.key] = _idMap[v];
        changed = true;
      } else {
        out[e.key] = v;
      }
    }
    return changed ? out : params;
  }

  /// Parameter id negatif yang belum punya padanan id asli.
  ///
  /// Return nama kolomnya (untuk pesan), atau null kalau semua id sudah aman.
  static String? _unresolvedIds(Map<String, Object?> params) {
    for (final e in params.entries) {
      final v = e.value;
      if (v is int && v < 0 && !_idMap.containsKey(v)) return e.key;
    }
    return null;
  }

  /// Kirim antrean ke server, berurutan.
  ///
  /// [query] dipakai untuk statement `RETURNING` (butuh id balik), [execute]
  /// untuk sisanya. [isRetryable] menentukan apakah sebuah kegagalan berarti
  /// "coba lagi nanti" (jaringan mati, sesi kedaluwarsa) atau "server menolak
  /// tulis ini" (data induk hilang, nilai tidak sah). Yang pertama
  /// menghentikan proses tanpa membuang antrean; yang kedua menandai satu
  /// tulis gagal lalu lanjut, supaya satu tulis bermasalah tidak memblokir
  /// seluruh antrean.
  /// [isAuthExpired] menandai kegagalan karena sesi habis. `Unauthorized`
  /// didefinisikan di `db.dart` yang mengimpor berkas ini, jadi tidak bisa
  /// dirujuk langsung di sini tanpa impor melingkar — pemanggil yang
  /// menentukannya.
  static Future<SyncResult> flush({
    required Future<List<Map<String, dynamic>>> Function(String, Map<String, Object?>)
        query,
    required Future<int> Function(String, Map<String, Object?>) execute,
    bool Function(Object)? isRetryable,
    bool Function(Object)? isAuthExpired,
  }) async {
    final retryable = isRetryable ?? isNetworkFailure;
    final authExpiredTest = isAuthExpired ?? (_) => false;
    await load();
    if (_flushing || _queue.isEmpty) {
      return SyncResult(remaining: _queue.length, failed: failedCount);
    }
    _flushing = true;
    syncing.value = true;
    var sent = 0;
    var offline = false;
    var authExpired = false;
    final keep = <PendingWrite>[];

    try {
      for (var i = 0; i < _queue.length; i++) {
        final w = _queue[i];
        // Yang sudah ditolak permanen tidak dikirim lagi; tetap disimpan
        // supaya pengguna bisa memutuskan.
        if (w.failed) {
          keep.add(w);
          continue;
        }
        final params = _rewrite(w.params);
        final op = parseWrite(w.sql, params);

        // Id negatif yang belum dipetakan berarti induknya tidak pernah
        // sampai ke server (insert-nya ditolak). Mengirimnya akan ditolak FK
        // satu per satu dan menumpuk sebagai kegagalan yang membingungkan.
        // Lebih jujur: tandai gagal dengan sebab yang bisa dimengerti.
        final orphan = _unresolvedIds(params);
        if (orphan != null) {
          keep.add(w.copyWith(
            failed: true,
            lastError: 'Data induknya gagal dikirim, jadi perubahan ini tidak '
                'bisa diterapkan.',
          ));
          continue;
        }

        try {
          if (op != null && op.returnsId && w.tempId != null) {
            final rows = await query(w.sql, params);
            final id = rows.isNotEmpty ? rows.first['id'] : null;
            if (id is num) {
              _idMap[w.tempId!] = id.toInt();
            } else if (id is String) {
              final parsed = int.tryParse(id);
              if (parsed != null) _idMap[w.tempId!] = parsed;
            }
          } else {
            final affected = await execute(w.sql, params);
            // UPDATE/DELETE yang mengenai 0 baris berarti barisnya sudah tidak
            // ada di cloud (mis. dihapus admin lain saat kita offline).
            // Melaporkannya "terkirim" membuat pengguna mengira perubahannya
            // tersimpan padahal tidak.
            final isUpdateOrDelete = op != null && (op.isUpdate || op.isDelete);
            if (isUpdateOrDelete && affected == 0) {
              keep.add(w.copyWith(
                failed: true,
                lastError: 'Data ini sudah tidak ada di server, jadi '
                    'perubahannya tidak bisa diterapkan.',
              ));
              continue;
            }
          }
          sent++;
        } catch (e) {
          if (retryable(e)) {
            // Masih offline / sesi habis: sisanya dicoba lain waktu.
            keep.add(w);
            keep.addAll(_queue.skip(i + 1));
            offline = isNetworkFailure(e);
            authExpired = authExpiredTest(e);
            break;
          }
          // Server menolak tulis ini (data induk hilang, nilai tidak sah).
          keep.add(w.copyWith(failed: true, lastError: '$e'));
        }
      }
      _queue
        ..clear()
        ..addAll(keep);
      // Urutkan ulang supaya urutan asli tetap terjaga setelah ada yang gagal.
      _queue.sort((a, b) => a.seq.compareTo(b.seq));
      pending.value = _queue.length;
      await _persist();
    } finally {
      _flushing = false;
      syncing.value = false;
    }

    // Pemanggil (`Db.sync`) yang membuang cache dan menaikkan `Db.writes`
    // supaya halaman memuat ulang setelah antrean terkirim.
    return SyncResult(
      sent: sent,
      remaining: _queue.length,
      failed: failedCount,
      offline: offline,
      authExpired: authExpired,
    );
  }

  /// Buang seluruh antrean (dipakai Pengaturan setelah pengguna setuju).
  static Future<void> clear() async {
    await load();
    _queue.clear();
    _idMap.clear();
    pending.value = 0;
    await _persist();
  }

  /// Buang satu tulis yang gagal permanen.
  static Future<void> removeFailed() async {
    await load();
    _queue.removeWhere((w) => w.failed);
    pending.value = _queue.length;
    await _persist();
  }

  /// Tulis antrean ke disk, berurutan lewat [_writeChain].
  ///
  /// Snapshot diambil **di dalam** rantai, bukan saat dipanggil: kalau diambil
  /// lebih awal, penulisan yang mengantre bisa menyimpan keadaan yang sudah
  /// basi dan menghapus tulis yang baru masuk.
  static Future<void> _persist() {
    final next = _writeChain.then((_) async {
      await writeOutbox(jsonEncode({
        'items': _queue.map((w) => w.toJson()).toList(),
        'next_temp_id': _nextTempId,
        'seq': _seq,
        'id_map': _idMap.map((k, v) => MapEntry('$k', v)),
      }));
    });
    // Rantai tidak boleh putus karena satu kegagalan: kegagalan tulis sudah
    // ditangani `writeOutbox` (tidak melempar), dan rantai yang putus akan
    // membuat semua penulisan berikutnya tidak pernah jalan.
    _writeChain = next.catchError((_) {});
    return next;
  }

  /// Untuk tes: kosongkan antrean di memori tanpa menyentuh disk.
  @visibleForTesting
  static void resetForTest() {
    _queue.clear();
    _idMap.clear();
    _nextTempId = -1;
    _seq = 0;
    _flushing = false;
    _loaded = true;
    pending.value = 0;
    syncing.value = false;
  }

  /// Untuk tes: lupakan isi memori DAN paksa [load] membaca ulang dari disk.
  /// Ini mensimulasikan aplikasi ditutup lalu dibuka lagi — jalur yang dipakai
  /// pengguna saat HP mati atau app di-swipe, dan satu-satunya cara menguji
  /// bahwa antrean benar-benar tersimpan di berkas.
  @visibleForTesting
  static void reloadFromDiskForTest() {
    _queue.clear();
    _idMap.clear();
    _nextTempId = -1;
    _seq = 0;
    _flushing = false;
    _loaded = false;
    pending.value = 0;
    syncing.value = false;
  }

  /// Untuk tes: lihat pemetaan id sementara.
  @visibleForTesting
  static Map<int, int> get idMapForTest => Map.unmodifiable(_idMap);
}
