import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'cache.dart';
import 'cache_store.dart';
import 'db_web.dart' as driver;
import 'net.dart' as net;
import 'offline.dart';
import 'row_patch.dart';

/// Dilempar driver saat token ditolak server (sesi habis).
class Unauthorized implements Exception {
  @override
  String toString() => 'Sesi berakhir. Masuk lagi untuk melanjutkan — perubahan yang belum terkirim tetap tersimpan.';
}

/// Baris yang hendak diubah sudah tidak ada di server.
///
/// Terjadi saat admin lain menghapus baris itu (atau membatalkan sewa) lebih
/// dulu. Lebih jujur memberi tahu daripada melaporkan "tersimpan" padahal
/// tidak ada yang berubah.
class StaleRowException implements Exception {
  @override
  String toString() =>
      'Data ini sudah tidak ada di server — mungkin dihapus pengurus lain. Muat ulang lalu coba lagi.';
}

/// Akses DB dari UI. Semua platform lewat `/api/sql` (Vercel Function),
/// jadi tidak ada kredensial Postgres di HP maupun browser.
///
/// **Offline-first.** Tulis dicoba ke server dulu; kalau gagal karena jaringan,
/// tulis masuk antrean ([Outbox]) dan efeknya ditambal ke cache, jadi pengguna
/// tetap bisa mengisi data tanpa internet. Saat online, antrean dikirim ulang
/// dan menimpa data cloud — data lokal yang diutamakan.
class Db {
  /// Token sesi (diisi `Auth` setelah login).
  static String? authToken;

  /// Scope cache: siapa yang sedang membaca.
  ///
  /// Cache dibaca per role karena isi query yang sama bisa berbeda isinya:
  /// admin melihat nomor HP dan alamat anggota, anggota hanya nomor HP, tamu
  /// tidak keduanya. Tanpa scope, hasil yang dibaca admin tersimpan di kunci
  /// yang sama dengan yang dibaca tamu — lalu tamu membacanya dari cache dan
  /// melewati penyaringan privasi di server.
  ///
  /// Diisi `Auth` saat login/logout (role ada di sana, bukan di sini).
  static String cacheScope = 'public';

  /// Dipanggil sekali saat server menolak token. Root memakainya untuk
  /// kembali ke layar masuk, jadi user tidak melihat error di tiap halaman.
  static Future<void> Function()? onSessionExpired;

  /// Naik setiap tulis berhasil (ke server maupun ke antrean offline).
  /// Halaman yang dibuka lagi setelah angka ini berubah memuat ulang datanya.
  static final ValueNotifier<int> writes = ValueNotifier(0);

  /// True sejak satu pembacaan jatuh ke cache. Halaman menampilkan banner
  /// "mode offline" selama ini menyala.
  static final ValueNotifier<bool> offline = ValueNotifier(false);

  /// Waktu data cache terakhir dipakai (untuk label banner).
  static DateTime? offlineSince;

  /// Sinkron berjalan sekarang.
  static bool get syncing => Outbox.syncing.value;

  /// Jumlah tulis yang belum terkirim.
  static int get pendingWrites => Outbox.pending.value;

  /// Pembacaan: server dulu, cache saat jaringan mati.
  ///
  /// Statement tulis yang lewat sini (`INSERT ... RETURNING id`) juga ikut
  /// masuk antrean saat offline, dan mengembalikan id sementara supaya
  /// pemanggil bisa melanjutkan (mis. buat tim lalu tambah pemain).
  static Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, Object?> params = const {},
  }) async {
    final write = _isWrite(sql);
    // Idempoten: id dibuat SEBELUM percobaan pertama, lalu dipakai lagi kalau
    // tulis ini berakhir di antrean. Tanpa id yang sama, tulis yang sebenarnya
    // sudah sampai (hanya jawabannya yang hilang karena timeout) dijalankan
    // dua kali saat sinkron dan buku kas mencatat uang yang sama dua kali.
    final writeId = write ? driver.newWriteId() : null;
    final key = cacheKey(sql, params, scope: cacheScope);
    try {
      final rows = await driver.query(sql, params: params, writeId: writeId);
      if (write) {
        writes.value++;
      } else {
        await activeCacheStore.writeEntry(CacheEntry(
          key: key,
          sql: sql,
          params: params,
          rows: rows,
          savedAt: DateTime.now(),
        ));
      }
      _markOnline();
      return rows;
    } on Unauthorized {
      await _expire();
      rethrow;
    } catch (e) {
      // Hanya kegagalan jaringan yang jatuh ke cache/antrean; query yang
      // ditolak (400/403) adalah bug atau izin, bukan alasan menyimpan data
      // yang mungkin tidak sah.
      if (!net.isNetworkFailure(e)) rethrow;

      if (write) {
        final tempId = await Outbox.enqueue(sql, params, writeId: writeId);
        await _patchCache(sql, params, tempId);
        writes.value++;
        _markOffline();
        return tempId == null ? const [] : [
          {'id': tempId},
        ];
      }

      final hit = await activeCacheStore.readRows(key);
      if (hit == null) rethrow;
      _markOffline(hit.savedAt);
      return hit.rows;
    }
  }

  static Future<int> execute(
    String sql, {
    Map<String, Object?> params = const {},
  }) async {
    final write = _isWrite(sql);
    final writeId = write ? driver.newWriteId() : null;
    try {
      final n = await driver.execute(sql, params: params, writeId: writeId);
      if (write) writes.value++;
      _markOnline();
      return n;
    } on Unauthorized {
      await _expire();
      rethrow;
    } catch (e) {
      if (!write || !net.isNetworkFailure(e)) rethrow;
      await Outbox.enqueue(sql, params, writeId: writeId);
      await _patchCache(sql, params, null);
      writes.value++;
      _markOffline();
      return 1;
    }
  }

  /// INSERT satu baris yang mengembalikan id-nya.
  ///
  /// Id ini penting untuk mode offline: kalau baris baru langsung dipakai
  /// (mis. buat anggota lalu edit), tulis berikutnya harus memakai id asli,
  /// bukan id tampilan. Saat offline, `Db.query` mengembalikan id sementara
  /// (negatif) yang dipetakan ke id asli saat sinkron.
  ///
  /// Return null kalau server tidak mengembalikan id (mis. baris sudah ada
  /// karena `ON CONFLICT DO NOTHING`).
  static Future<int?> insertId(
    String sql, {
    Map<String, Object?> params = const {},
  }) async {
    final rows = await query(sql, params: params);
    if (rows.isEmpty) return null;
    final v = rows.first['id'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }

  /// Id tampilan untuk baris yang ditambal tanpa id asli (mis. INSERT tanpa
  /// `RETURNING id`). Negatif dan jauh dari rentang id asli, supaya tidak
  /// pernah bertabrakan dengan id dari server maupun id sementara antrean.
  static int _displayId = -1000000;

  /// Terapkan efek tulis ke semua entri cache yang menyentuh tabelnya.
  static Future<void> _patchCache(
    String sql,
    Map<String, Object?> params,
    int? tempId,
  ) async {
    final op = parseWrite(sql, params);
    if (op == null || !op.patchable) return;
    // Baris hasil INSERT wajib punya id: tanpa itu `Member.fromMap` (yang
    // membaca `m['id'] as int`) gagal dan seluruh daftar tidak bisa dibaca —
    // data offline terlihat "tidak tersimpan" padahal antreannya benar.
    final id = tempId ?? (op.isInsert ? _displayId-- : null);
    await _applyToCache([op], id);
  }

  /// Tambal cache untuk tulis yang SQL-nya tidak bisa diurai penambal
  /// otomatis.
  ///
  /// Satu pemakainya: pembagian biaya patungan, yang sengaja dikirim sebagai
  /// satu `UPDATE ... FROM (VALUES ...)` massal. Bentuk itu tidak dikenali
  /// [parseWrite], jadi tanpa panggilan ini baris di cache tetap memakai angka
  /// lama: saat offline orang yang baru ditambahkan tampil dengan bagian Rp 0,
  /// dan tombol "sudah setor" mencatat Rp 0 ke kas.
  static Future<void> patchCacheRows({
    required String table,
    required Map<int, Map<String, Object?>> valuesById,
  }) async {
    if (valuesById.isEmpty) return;
    await _applyToCache([
      for (final e in valuesById.entries)
        WriteOp(
          kind: 'update',
          table: table,
          values: e.value,
          whereEq: {'id': e.key},
          patchable: true,
        ),
    ], null);
  }

  static Future<void> _applyToCache(List<WriteOp> ops, int? tempId) async {
    try {
      final entries = await activeCacheStore.listEntries();
      for (final entry in entries) {
        var rows = entry.rows;
        for (final op in ops) {
          rows = applyOp(
            rows,
            op,
            querySql: entry.sql,
            // Parameter query ASAL entri ini, bukan parameter tulis: syarat
            // WHERE milik query itulah yang menentukan baris mana yang boleh
            // ditambahkan.
            queryParams: entry.params,
            tempId: tempId,
          );
        }
        if (identical(rows, entry.rows)) continue;
        final ordered = sortLikeQuery(rows, entry.sql);
        final trimmed = trimLikeQuery(ordered, entry.sql, entry.params);
        await activeCacheStore.writeEntry(entry.copyWith(rows: trimmed));
      }
    } catch (_) {
      // Penambalan adalah kenyamanan; kegagalannya tidak boleh menggagalkan
      // penyimpanan ke antrean yang sudah berhasil.
    }
  }

  static void _markOffline([DateTime? since]) {
    offlineSince = since ?? offlineSince ?? DateTime.now();
    if (!offline.value) offline.value = true;
  }

  static void _markOnline() {
    if (offline.value) {
      offline.value = false;
      offlineSince = null;
    }
  }

  /// Kegagalan yang pantas ditutup cache: server tidak terjangkau atau
  /// timeout. `ApiException` dari server (mis. "Query gagal dijalankan")
  /// tidak termasuk — itu jawaban, bukan gangguan jaringan.
  static bool isNetworkFailure(Object e) => net.isNetworkFailure(e);

  /// Kirim antrean tulis offline ke server.
  ///
  /// Dipanggil saat app dibuka, saat app kembali ke depan, saat tab berpindah,
  /// dan dari tombol di banner.
  static Future<SyncResult> sync() async {
    await Outbox.load();
    if (Outbox.pending.value == 0) return const SyncResult();

    final result = await Outbox.flush(
      query: (sql, params, {String? writeId}) =>
          driver.query(sql, params: params, writeId: writeId),
      execute: (sql, params, {String? writeId}) =>
          driver.execute(sql, params: params, writeId: writeId),
      // Sesi kedaluwarsa BUKAN alasan membuang tulisan pengguna: pengguna
      // tinggal masuk lagi, lalu antrean dikirim. Hanya penolakan server
      // yang menandai tulis gagal permanen.
      isRetryable: (e) => e is Unauthorized || net.isNetworkFailure(e),
      isAuthExpired: (e) => e is Unauthorized,
    );

    if (result.sent > 0) {
      _markOnline();
      // Cache hanya dibuang kalau antrean benar-benar habis.
      //
      // Dulu cache selalu dibuang asal ada yang terkirim. Akibatnya: kalau
      // masih ada tulisan yang gagal atau belum terkirim, baris hasil
      // tambalannya ikut terhapus — data yang baru diisi lenyap dari layar dan
      // hanya tersisa sebagai entri gagal. Dan kalau koneksi putus lagi setelah
      // sinkron, tidak ada cache sama sekali sehingga semua halaman jadi layar
      // error, padahal sebelumnya bisa dibaca.
      if (result.remaining == 0 && result.failed == 0) {
        await activeCacheStore.clear();
      }
      writes.value++;
    } else if (result.authExpired) {
      // Sesi habis (token berlaku 12 jam, jadi antrean sore hari bisa kena
      // besok pagi). Beri tahu lewat jalur yang sama dengan permintaan lain
      // yang ditolak server: kembali ke layar masuk. Antrean tetap utuh dan
      // dikirim lagi setelah pengguna masuk.
      await _expire();
    } else if (result.offline) {
      _markOffline();
    }
    return result;
  }

  /// Muat antrean tersimpan. Dipanggil sekali saat app start.
  static Future<void> loadOffline() async {
    await Outbox.load();
    if (Outbox.pending.value > 0) offline.value = true;
  }

  /// Kosongkan cache offline (dipakai Pengaturan).
  static Future<int> clearOfflineCache() async {
    offline.value = false;
    offlineSince = null;
    return activeCacheStore.clear();
  }

  /// Buang antrean tulis yang belum terkirim (dipakai Pengaturan).
  static Future<void> clearOutbox() async {
    await Outbox.clear();
    if (Outbox.pending.value == 0) {
      offline.value = false;
      offlineSince = null;
    }
  }

  /// Buang tulis yang ditolak permanen.
  static Future<void> dropFailedWrites() => Outbox.removeFailed();

  /// Jalankan UPDATE/DELETE yang WAJIB mengenai baris.
  ///
  /// `execute` mengembalikan 0 kalau barisnya sudah tidak ada di cloud (mis.
  /// dihapus admin lain). Tanpa pemeriksaan ini, menyunting baris yang sudah
  /// hilang tampak berhasil dan pengguna mengira perubahannya tersimpan.
  static Future<void> executeExpect(
    String sql, {
    Map<String, Object?> params = const {},
    int expect = 1,
  }) async {
    final n = await execute(sql, params: params);
    if (n < expect) throw StaleRowException();
  }

  static bool _isWrite(String sql) {
    final head = sql.trimLeft().toUpperCase();
    return head.startsWith('INSERT') || head.startsWith('UPDATE') || head.startsWith('DELETE');
  }

  static Future<void> _expire() async {
    final handler = onSessionExpired;
    if (handler != null) await handler();
  }

  static Future<void> close() async => driver.close();
}

/// Wrapper secure storage sederhana biar import-nya di satu tempat.
class SecureStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Nilai yang tidak bisa didekripsi (storage rusak, kunci berubah, atau
  /// sisa versi lama) dibuang supaya app tidak gagal start dengan layar kosong.
  static Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      try {
        await _storage.delete(key: key);
      } catch (_) {}
      return null;
    }
  }

  static Future<void> write(String key, String value) => _storage.write(key: key, value: value);
  static Future<void> delete(String key) => _storage.delete(key: key);
}
