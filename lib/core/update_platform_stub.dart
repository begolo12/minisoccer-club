/// Versi web / platform tanpa `dart:io`: tidak bisa memasang APK.
library;

import 'update_models.dart';

/// Web hanya bisa memeriksa versi, tidak memasang.
bool get canSelfUpdate => false;

Future<String> downloadApk(
  ReleaseInfo release, {
  void Function(int received, int total)? onProgress,
}) async {
  throw UnsupportedError('Pembaruan APK hanya tersedia di aplikasi Android.');
}

Future<InstallOutcome> installApk(String path) async => InstallOutcome.failed;


/// Di web tidak ada pembaruan mandiri, jadi arsitektur perangkat tidak berarti.
String? deviceAbi() => null;
