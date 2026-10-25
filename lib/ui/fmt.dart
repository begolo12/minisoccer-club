import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/errors.dart';

export '../core/errors.dart';

/// Format tanggal/jam Indonesia tanpa dependensi locale intl tambahan.
String fmtDate(DateTime d) {
  const bulan = ['Jan','Feb','Mar','Apr','Mei','Jun','Jul','Agu','Sep','Okt','Nov','Des'];
  return '${d.day} ${bulan[d.month - 1]} ${d.year}';
}

String fmtDay(DateTime d) {
  const hari = ['Sen','Sel','Rab','Kam','Jum','Sab','Min'];
  return hari[d.weekday - 1];
}

String fmtTime(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}.${d.minute.toString().padLeft(2, '0')}';

String fmtDateTime(DateTime d) => '${fmtDay(d)}, ${fmtDate(d)} • ${fmtTime(d)}';

/// Tanggal pendek untuk kolom sempit: "21 Okt".
String fmtShortDate(DateTime d) {
  const bulan = ['Jan','Feb','Mar','Apr','Mei','Jun','Jul','Agu','Sep','Okt','Nov','Des'];
  return '${d.day} ${bulan[d.month - 1]}';
}

String fmtMoney(num v) =>
    v < 0 ? '-Rp ${fmtNumber(v.abs())}' : 'Rp ${fmtNumber(v)}';

/// Nominal ringkas untuk label sempit: "Rp 1,95 jt", "Rp 350 rb".
///
/// Satuan dipilih dari hasil PEMBULATAN, bukan dari nilai mentah: 999.999
/// dibulatkan ke ribuan menjadi 1.000 rb, dan "Rp 1000 rb" salah — seharusnya
/// naik ke "Rp 1,00 jt". Karena itu ambangnya memakai batas bawah satuan
/// berikutnya dikurangi setengah satuan pembulatan.
String fmtShortMoney(num v) {
  final a = v.abs();
  String body;
  if (a >= 999_500_000) {
    body = '${(a / 1e9).toStringAsFixed(2).replaceAll('.', ',')} M';
  } else if (a >= 999_500) {
    body = '${(a / 1e6).toStringAsFixed(2).replaceAll('.', ',')} jt';
  } else if (a >= 9_500) {
    body = '${(a / 1e3).toStringAsFixed(0)} rb';
  } else {
    body = fmtNumber(a);
  }
  return v < 0 ? '-Rp $body' : 'Rp $body';
}

/// Angka ribuan tanpa awalan "Rp" — dipakai di label sempit.
String fmtNumber(num v) {
  final s = v.abs().toStringAsFixed(0);
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return v < 0 ? '-${buf.toString()}' : buf.toString();
}

/// Baca nominal uang yang diketik pengguna.
///
/// Input uang di app ini ditulis dengan gaya Indonesia (titik = ribuan, koma =
/// desimal), tapi orang juga mengetik gaya lain: "1.500.000", "1500000",
/// "1.500,50", bahkan "100000.50". Aturan lama — buang semua titik, ganti koma
/// jadi titik — membuat "100000.50" terbaca 10000050: nominal jadi 100× lebih
/// besar dan tetap lolos validasi "harus > 0". Uang yang salah catat lebih
/// buruk daripada input yang ditolak, jadi di sini pola yang ambigu ditolak.
///
/// Aturan:
///   * hanya angka, titik, koma, spasi, dan tanda minus di depan;
///   * kalau ada titik DAN koma → yang paling kanan adalah pemisah desimal;
///   * hanya koma → pemisah desimal;
///   * hanya titik → ribuan kalau berpola `1.234` / `1.234.567`, selain itu
///     desimal (`100000.50`), dan `1.500` dibaca ribuan (kebiasaan Indonesia).
///
/// Return null kalau tidak bisa dibaca sebagai angka — pemanggil wajib
/// menampilkan pesan, bukan diam-diam menyimpan 0.
double? parseMoney(String input) {
  var s = input.trim().replaceAll(' ', '').replaceAll('Rp', '').replaceAll('rp', '');
  if (s.isEmpty) return null;

  var negative = false;
  if (s.startsWith('-')) {
    negative = true;
    s = s.substring(1);
  }
  if (s.isEmpty) return null;
  // Selain digit dan pemisah = bukan nominal.
  if (!RegExp(r'^[0-9.,]+$').hasMatch(s)) return null;

  final hasDot = s.contains('.');
  final hasComma = s.contains(',');

  String normalized;
  if (hasDot && hasComma) {
    // Yang paling kanan adalah desimal; sisanya pemisah ribuan.
    final lastDot = s.lastIndexOf('.');
    final lastComma = s.lastIndexOf(',');
    if (lastComma > lastDot) {
      normalized = '${s.substring(0, lastComma).replaceAll('.', '').replaceAll(',', '')}'
          '.${s.substring(lastComma + 1)}';
    } else {
      normalized = '${s.substring(0, lastDot).replaceAll('.', '').replaceAll(',', '')}'
          '.${s.substring(lastDot + 1)}';
    }
  } else if (hasComma) {
    final parts = s.split(',');
    if (parts.length != 2) return null; // "1,234,567" gaya Inggris: ambigu
    normalized = '${parts[0]}.${parts[1]}';
  } else if (hasDot) {
    final parts = s.split('.');
    final looksGrouped = parts.length > 1 &&
        parts[0].length <= 3 &&
        parts.skip(1).every((p) => p.length == 3);
    if (looksGrouped) {
      normalized = parts.join();
    } else if (parts.length == 2) {
      // "100000.50" → desimal; "1.500" sudah tertangkap looksGrouped.
      normalized = '${parts[0]}.${parts[1]}';
    } else {
      return null;
    }
  } else {
    normalized = s;
  }

  final v = double.tryParse(normalized);
  if (v == null) return null;
  return negative ? -v : v;
}

String periodNow() {
  final n = DateTime.now();
  return '${n.year}-${n.month.toString().padLeft(2, '0')}';
}

String periodLabel(String p) {
  const bulan = ['Januari','Februari','Maret','April','Mei','Juni','Juli','Agustus','September','Oktober','November','Desember'];
  final parts = p.split('-');
  if (parts.length != 2) return p;
  final m = int.tryParse(parts[1]);
  if (m == null || m < 1 || m > 12) return p;
  return '${bulan[m - 1]} ${parts[0]}';
}

/// Dialog konfirmasi destruktif (shadcn). Return true kalau user setuju.
Future<bool> confirm(
  BuildContext context,
  String title,
  String message, {
  String confirmLabel = 'Hapus',
}) async {
  final ok = await showShadDialog<bool>(
    context: context,
    builder: (ctx) => ShadDialog(
      title: Text(title),
      description: Text(message),
      actions: [
        ShadButton.outline(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Batal'),
        ),
        ShadButton.destructive(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Toast pendek gaya shadcn. Jatuh ke SnackBar kalau Sonner tidak terpasang.
///
/// Pesan yang menandai kegagalan tampil lebih lama: penjelasan error tidak
/// sempat dibaca dalam 2 detik, dan toast yang hilang sama dengan tidak ada.
void toast(BuildContext context, String msg) {
  final isError = msg.startsWith('Gagal') ||
      msg.startsWith('Tidak bisa') ||
      msg.contains(' ditolak') ||
      msg.contains(' belum bisa');
  final duration = Duration(seconds: isError ? 5 : 2);
  final sonner = ShadSonner.maybeOf(context);
  if (sonner != null) {
    sonner.show(ShadToast(
      title: Text(msg),
      duration: duration,
    ));
    return;
  }
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      duration: duration,
    ));
}

/// Jalankan aksi tulis dan tampilkan pesan kalau gagal, supaya error jaringan
/// tidak berhenti sebagai exception tanpa penjelasan.
Future<bool> attempt(
  BuildContext context,
  Future<void> Function() action, {
  String fail = 'Gagal menyimpan',
}) async {
  try {
    await action();
    return true;
  } catch (e) {
    if (context.mounted) toast(context, '$fail: ${errText(e)}');
    return false;
  }
}
