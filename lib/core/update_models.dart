/// Model + aturan pembaruan APK. Tanpa `dart:io` supaya bisa dipakai di web
/// (web hanya memeriksa, tidak memasang).
library;

/// Satu rilis GitHub yang punya aset APK.
class ReleaseInfo {
  const ReleaseInfo({
    required this.tag,
    required this.version,
    required this.notes,
    required this.apkUrl,
    required this.sizeBytes,
    required this.publishedAt,
    this.sha256,
  });

  /// `v1.8.0`
  final String tag;

  /// `1.8.0` — tanpa `v`, siap dibandingkan dengan [kAppVersion].
  final String version;
  final String notes;
  final String apkUrl;
  final int sizeBytes;
  final DateTime publishedAt;

  /// Digest `sha256:...` dari GitHub. Null untuk rilis lama.
  final String? sha256;
}

/// Hasil satu kali pemeriksaan.
class UpdateCheck {
  const UpdateCheck({
    required this.current,
    this.release,
    this.error,
  });

  final String current;
  final ReleaseInfo? release;

  /// Terisi kalau pemeriksaan gagal (jaringan, rate limit, rilis tidak ada).
  final String? error;

  bool get hasUpdate => release != null;

  String get status {
    if (error != null) return error!;
    final r = release;
    if (r == null) return 'Versi terpasang paling baru.';
    return 'Versi ${r.version} tersedia.';
  }
}

/// Hasil membuka installer Android.
enum InstallOutcome {
  /// Intent installer terbuka; user tinggal menekan "Pasang".
  started,

  /// Izin "pasang aplikasi tak dikenal" belum diberikan; layar pengaturan
  /// sudah dibuka dan user perlu mengulang.
  needsPermission,

  /// Intent tidak bisa dibuka (mis. tidak ada aplikasi installer).
  failed,
}

/// Apakah pembaruan ini perlu DITAWARKAN ke pengguna?
///
/// [dismissedVersion] adalah versi yang pernah ditutup pengguna dengan
/// "Nanti". Satu versi hanya ditawarkan sekali, supaya dialog tidak muncul
/// setiap aplikasi dibuka — tetapi versi yang lebih baru tetap ditawarkan.
bool shouldOfferUpdate(UpdateCheck? check, String? dismissedVersion) {
  final release = check?.release;
  if (release == null) return false;
  if (dismissedVersion != null && dismissedVersion == release.version) return false;
  return true;
}

/// Bandingkan dua versi numerik per komponen: `1.7.0` < `1.10.0`.
/// Bagian non-angka (mis. `-beta`) diabaikan; jumlah komponen boleh berbeda.
int compareVersions(String a, String b) {
  List<int> parts(String v) => v
      .trim()
      .replaceFirst(RegExp(r'^[vV]'), '')
      .split(RegExp(r'[.+-]'))
      .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
      .toList();

  final x = parts(a);
  final y = parts(b);
  final n = x.length > y.length ? x.length : y.length;
  for (var i = 0; i < n; i++) {
    final xi = i < x.length ? x[i] : 0;
    final yi = i < y.length ? y[i] : 0;
    if (xi != yi) return xi.compareTo(yi);
  }
  return 0;
}

/// Ambil rilis dari balasan `GET /repos/{owner}/{repo}/releases/latest`.
///
/// Return null kalau rilis tidak punya aset `.apk` — lebih baik "tidak ada
/// pembaruan" daripada tombol unduh yang menunjuk ke file yang salah.
/// Pilih aset APK yang paling kecil untuk perangkat ini.
///
/// Rilis bisa memuat tiga berkas: `app-armeabi-v7a-release.apk` (HP lama
/// 32-bit, ~19 MB), `app-arm64-v8a-release.apk` (HP sekarang, ~21 MB), dan
/// `app-release.apk` universal (~38 MB). Memilih yang universal selalu
/// benar, tetapi di jaringan lambat itu dua kali lipat unduhan tanpa manfaat.
///
/// [abi] berisi potongan nama arsitektur (`armeabi-v7a`, `arm64-v8a`,
/// `x86_64`). Kalau tidak ada aset yang cocok, jatuh ke APK universal — lebih
/// baik mengunduh berkas besar yang pasti terpasang daripada menawarkan
/// berkas yang tidak ada.
ReleaseInfo? parseRelease(Map<String, dynamic> json, {String? abi}) {
  final tag = (json['tag_name'] as String?)?.trim();
  if (tag == null || tag.isEmpty) return null;

  final assets = (json['assets'] as List?) ?? const [];
  Map<String, dynamic>? apk;
  Map<String, dynamic>? universal;
  for (final raw in assets) {
    if (raw is! Map) continue;
    final name = (raw['name'] as String?)?.toLowerCase() ?? '';
    if (!name.endsWith('.apk')) continue;
    final asset = Map<String, dynamic>.from(raw);
    if (abi != null && abi.isNotEmpty && name.contains(abi.toLowerCase())) {
      apk = asset;
      break;
    }
    universal ??= asset;
  }
  apk ??= universal;
  if (apk == null) return null;

  final url = (apk['browser_download_url'] as String?) ?? '';
  if (url.isEmpty) return null;

  final digest = (apk['digest'] as String?) ?? '';
  return ReleaseInfo(
    tag: tag,
    version: tag.replaceFirst(RegExp(r'^[vV]'), ''),
    notes: ((json['body'] as String?) ?? '').trim(),
    apkUrl: url,
    sizeBytes: (apk['size'] as num?)?.toInt() ?? 0,
    publishedAt: DateTime.tryParse((json['published_at'] as String?) ?? '')?.toLocal() ??
        DateTime.now(),
    sha256: digest.startsWith('sha256:') ? digest.substring(7) : null,
  );
}

/// Ukuran file untuk label tombol: `57,4 MB`.
String fmtBytes(int bytes) {
  if (bytes <= 0) return '—';
  final mb = bytes / (1024 * 1024);
  if (mb >= 1) return '${mb.toStringAsFixed(1).replaceAll('.', ',')} MB';
  return '${(bytes / 1024).round()} KB';
}
