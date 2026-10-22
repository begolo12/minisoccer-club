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
  const SyncResult({this.sent = 0, this.remaining = 0, this.failed = 0, this.offline = false});

  final int sent;
  final int remaining;
  final int failed;

  /// True kalau berhenti karena jaringan masih mati.
  final bool offline;

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

  static List<PendingWrite> get items => List.unmodifiable(_queue);
  static int get failedCount => _queue.where((w) => w.failed).length;

  /// Muat antrean dari disk (sekali per proses).
  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final raw = await readOutbox();
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
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
    } catch (_) {
      // Antrean rusak: lebih baik mulai kosong daripada gagal start.
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

  /// Kirim antrean ke server, berurutan.
  ///
  /// [query] dipakai untuk statement `RETURNING` (butuh id balik), [execute]
  /// untuk sisanya. [isRetryable] menentukan apakah sebuah kegagalan berarti
  /// "coba lagi nanti" (jaringan mati, sesi kedaluwarsa) atau "server menolak
  /// tulis ini" (data induk hilang, nilai tidak sah). Yang pertama
  /// menghentikan proses tanpa membuang antrean; yang kedua menandai satu
  /// tulis gagal lalu lanjut, supaya satu tulis bermasalah tidak memblokir
  /// seluruh antrean.
  static Future<SyncResult> flush({
    required Future<List<Map<String, dynamic>>> Function(String, Map<String, Object?>)
        query,
    required Future<int> Function(String, Map<String, Object?>) execute,
    bool Function(Object)? isRetryable,
  }) async {
    final retryable = isRetryable ?? isNetworkFailure;
    await load();
    if (_flushing || _queue.isEmpty) {
      return SyncResult(remaining: _queue.length, failed: failedCount);
    }
    _flushing = true;
    syncing.value = true;
    var sent = 0;
    var offline = false;
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
            await execute(w.sql, params);
          }
          sent++;
        } catch (e) {
          if (retryable(e)) {
            // Masih offline / sesi habis: sisanya dicoba lain waktu.
            keep.add(w);
            keep.addAll(_queue.skip(i + 1));
            offline = isNetworkFailure(e);
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

  static Future<void> _persist() async {
    await writeOutbox(jsonEncode({
      'items': _queue.map((w) => w.toJson()).toList(),
      'next_temp_id': _nextTempId,
      'seq': _seq,
      'id_map': _idMap.map((k, v) => MapEntry('$k', v)),
    }));
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

  /// Untuk tes: lihat pemetaan id sementara.
  @visibleForTesting
  static Map<int, int> get idMapForTest => Map.unmodifiable(_idMap);
}
