/// Pemeriksa pembaruan dari GitHub Releases + pemasang APK.
///
/// Alur: cek `/releases/latest` → bandingkan tag dengan versi terpasang →
/// unduh aset APK ke cache → buka installer sistem. Langkah terakhir tetap
/// butuh satu ketukan "Pasang" dari user; Android tidak mengizinkan aplikasi
/// biasa memasang APK secara senyap (itu hanya untuk device owner / MDM).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'errors.dart';

import 'db.dart';
import 'update_models.dart';
import 'version.dart';

export 'update_models.dart';
export 'update_platform_stub.dart'
    if (dart.library.io) 'update_platform_io.dart' show canSelfUpdate, downloadApk, installApk;

const kRepoSlug = 'begolo12/minisoccer-club';
const kLatestReleaseApi = 'https://api.github.com/repos/$kRepoSlug/releases/latest';

/// Pemeriksaan otomatis dibatasi sekali per 12 jam: API GitHub tanpa token
/// hanya memberi 60 permintaan/jam per IP, dan angka versi tidak berubah
/// dalam hitungan menit.
const _checkInterval = Duration(hours: 12);
const _lastCheckKey = 'update_checked_at';

/// Pemeriksa versi. Tanpa efek samping: hanya membaca API publik GitHub.
class UpdateChecker {
  UpdateChecker({this.client, this.current = kAppVersion});

  /// Klien HTTP; null = buat sendiri per pemeriksaan (dan tutup setelahnya).
  final http.Client? client;
  final String current;

  /// Ambil rilis terbaru. [client] bisa disuntik di tes.
  Future<UpdateCheck> check() async {
    final httpClient = client ?? http.Client();
    try {
      final res = await httpClient
          .get(
            Uri.parse(kLatestReleaseApi),
            headers: const {
              'accept': 'application/vnd.github+json',
              'user-agent': 'minisoccer-club/$kAppVersion',
            },
          )
          .timeout(const Duration(seconds: 20));

      if (res.statusCode == 404) {
        return UpdateCheck(current: current, error: 'Belum ada rilis di GitHub.');
      }
      if (res.statusCode == 403) {
        return UpdateCheck(
          current: current,
          error: 'GitHub membatasi pemeriksaan. Coba lagi nanti.',
        );
      }
      if (res.statusCode != 200) {
        return UpdateCheck(current: current, error: 'GitHub membalas ${res.statusCode}.');
      }

      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        return UpdateCheck(current: current, error: 'Balasan GitHub tidak dikenali.');
      }
      final release = parseRelease(decoded);
      if (release == null) {
        return UpdateCheck(current: current, error: 'Rilis terbaru tanpa berkas APK.');
      }
      // Versi lebih baru saja yang ditawarkan; rilis lama atau sama diabaikan
      // supaya tidak ada tombol "turun versi".
      final newer = compareVersions(release.version, current) > 0;
      return UpdateCheck(current: current, release: newer ? release : null);
    } on TimeoutException {
      return UpdateCheck(current: current, error: 'GitHub tidak merespons.');
    } catch (e) {
      // Di web, CSP produksi hanya mengizinkan koneksi ke domain sendiri
      // (`connect-src 'self'`), jadi permintaan ke api.github.com diblokir
      // browser. Itu bukan gangguan jaringan biasa, dan pesan aslinya
      // ("ClientException: Failed to fetch, uri=...") tidak berguna bagi
      // pengguna — sebutkan jalan keluarnya.
      if (kIsWeb && e.toString().contains('Failed to fetch')) {
        return UpdateCheck(
          current: current,
          error: 'Pemeriksaan pembaruan hanya tersedia di aplikasi Android. '
              'Di web, versi baru otomatis terpakai saat halaman dimuat ulang.',
        );
      }
      return UpdateCheck(current: current, error: 'Gagal memeriksa pembaruan: ${errText(e)}');
    } finally {
      if (client == null) httpClient.close();
    }
  }
}

/// Status pembaruan yang dibagi antar layar (Pengaturan + badge di Lainnya).
///
/// Diisi sekali saat app dibuka (maks. sekali per 12 jam), dan bisa dipaksa
/// ulang lewat tombol "Cek pembaruan".
class UpdateService {
  UpdateService._();

  static final ValueNotifier<UpdateCheck?> latest = ValueNotifier(null);
  static bool _running = false;

  /// Pemeriksaan latar saat start. Tidak pernah melempar: kegagalan hanya
  /// mengisi [UpdateCheck.error] dan tidak mengganggu layar lain.
  ///
  /// Di web tidak dijalankan sama sekali: CSP produksi memblokir
  /// `api.github.com`, dan versi web selalu terbaru setelah halaman dimuat
  /// ulang — memeriksa hanya akan menghasilkan error yang tidak berguna.
  static Future<void> autoCheck() async {
    if (kIsWeb) return;
    if (_running) return;
    _running = true;
    try {
      final last = await SecureStore.read(_lastCheckKey);
      final at = DateTime.tryParse(last ?? '');
      final fresh = at != null && DateTime.now().difference(at) < _checkInterval;
      if (fresh && latest.value != null) return;
      latest.value = await UpdateChecker().check();
      await SecureStore.write(_lastCheckKey, DateTime.now().toIso8601String());
    } catch (_) {
      // Diam: ini pemeriksaan latar, bukan aksi user.
    } finally {
      _running = false;
    }
  }

  /// Dipanggil tombol "Cek pembaruan" — hasilnya selalu ditampilkan.
  static Future<UpdateCheck> checkNow() async {
    final check = await UpdateChecker().check();
    latest.value = check;
    await SecureStore.write(_lastCheckKey, DateTime.now().toIso8601String());
    return check;
  }

  /// Untuk preview/tes: tanam hasil tanpa jaringan.
  @visibleForTesting
  static void seed(UpdateCheck check) => latest.value = check;
}
