import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

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

String fmtMoney(num v) {
  final s = v.toStringAsFixed(0);
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return 'Rp $buf';
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
