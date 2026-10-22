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
String fmtShortMoney(num v) {
  final a = v.abs();
  String body;
  if (a >= 1e9) {
    body = '${(a / 1e9).toStringAsFixed(2).replaceAll('.', ',')} M';
  } else if (a >= 1e6) {
    body = '${(a / 1e6).toStringAsFixed(2).replaceAll('.', ',')} jt';
  } else if (a >= 1e4) {
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
void toast(BuildContext context, String msg) {
  final sonner = ShadSonner.maybeOf(context);
  if (sonner != null) {
    sonner.show(ShadToast(
      title: Text(msg),
      duration: const Duration(seconds: 2),
    ));
    return;
  }
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
}

/// Jalankan aksi tulis dan tampilkan pesan kalau gagal, supaya error jaringan
/// tidak berhenti sebagai exception tanpa penjelasan.
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
