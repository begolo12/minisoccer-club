/// Bagian pembaruan yang butuh platform (Android): unduh berkas + buka
/// installer sistem. Versi web/iOS memakai `update_platform_stub.dart`.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'update_models.dart';

/// Hanya Android yang bisa memasang APK. iOS dan desktop tidak.
bool get canSelfUpdate => Platform.isAndroid;

const _channel = MethodChannel('app/installer');

/// Unduh APK ke cache lalu kembalikan path-nya. [onProgress] dipanggil dengan
/// (byte diterima, total byte; 0 kalau server tidak mengirim Content-Length).
Future<String> downloadApk(
  ReleaseInfo release, {
  void Function(int received, int total)? onProgress,
}) async {
  final dir = Directory('${(await getTemporaryDirectory()).path}/updates');
  await dir.create(recursive: true);
  final file = File('${dir.path}/minisoccer-${release.version}.apk');
  // Sisa unduhan versi lain dibuang supaya cache tidak menumpuk 57 MB tiap
  // rilis.
  await for (final old in dir.list()) {
    if (old is File && old.path != file.path) {
      try {
        await old.delete();
      } catch (_) {}
    }
  }

  final client = http.Client();
  try {
    // Timeout pada pengiriman awal: server yang tidak menjawab tanpa ini
    // membuat dialog pasang (non-dismissable) menunggu selamanya.
    final res = await client
        .send(http.Request('GET', Uri.parse(release.apkUrl)))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw Exception('Unduhan gagal (HTTP ${res.statusCode})');
    }
    final total = res.contentLength ?? release.sizeBytes;
    final sink = file.openWrite();
    final hasher = release.sha256 == null ? null : _HashSink();
    final digestSink = hasher == null ? null : sha256.startChunkedConversion(hasher);
    var received = 0;
    try {
      // `Stream.timeout` mengawasi JEDA antar potongan, bukan durasi total:
      // sinyal yang hilang di tengah unduhan tidak melempar apa pun tanpa
      // ini, dan dialog pembaruan macet sampai app dibunuh paksa.
      await for (final chunk in res.stream.timeout(
        const Duration(seconds: 30),
        onTimeout: (sinkOut) => sinkOut.addError(
          Exception('Unduhan berhenti di tengah — sinyal tidak stabil. Coba lagi.'),
        ),
      )) {
        sink.add(chunk);
        digestSink?.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
    } finally {
      await sink.close();
      digestSink?.close();
    }

    if (received == 0) throw Exception('Berkas kosong');
    final expected = release.sha256;
    if (expected != null) {
      final got = hasher!.value?.toString();
      if (got != expected.toLowerCase()) {
        await file.delete();
        throw Exception('Berkas unduhan rusak (sha256 tidak cocok)');
      }
    }
    return file.path;
  } finally {
    client.close();
  }
}

/// Buka installer paket Android untuk APK yang sudah diunduh.
///
/// Android tidak mengizinkan aplikasi biasa memasang APK tanpa konfirmasi:
/// intent ini memunculkan layar "Pasang", dan ketukan terakhir milik user.
Future<InstallOutcome> installApk(String path) async {
  final result = await _channel.invokeMethod<String>('install', {'path': path});
  return switch (result) {
    'started' => InstallOutcome.started,
    'permission' => InstallOutcome.needsPermission,
    _ => InstallOutcome.failed,
  };
}

/// Kumpulan digest dari chunked conversion `crypto`.
class _HashSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}


/// Arsitektur CPU perangkat, dipakai memilih APK terkecil yang cocok.
///
/// `Abi.current()` berasal dari `dart:ffi` dan membaca arsitektur proses yang
/// sedang berjalan — persis yang menentukan APK mana yang bisa dipasang.
String? deviceAbi() {
  if (!Platform.isAndroid) return null;
  final name = Abi.current().toString(); // Abi.androidArm64, Abi.androidArm, …
  return switch (name) {
    'androidArm64' => 'arm64-v8a',
    'androidArm' => 'armeabi-v7a',
    'androidX64' => 'x86_64',
    'androidIA32' => 'x86',
    _ => null,
  };
}
