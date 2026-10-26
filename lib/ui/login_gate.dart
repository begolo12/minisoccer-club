// Gerbang "perlu masuk" untuk data uang klub.
//
// Aplikasi ini memang bisa dibuka tanpa akun: jadwal, klasemen, dan
// pengumuman wajar dilihat siapa pun yang punya tautannya. Tapi kas, iuran,
// dan biaya sewa adalah pembukuan klub — server menolak membacanya tanpa
// sesi (`api/_guard.js`), dan halaman-halaman ini menampilkan penjelasan
// yang bisa ditindaklanjuti alih-alih layar error.
//
// Satu tempat, bukan lima salinan: pesan dan tombolnya harus sama di Iuran,
// Kas, Sewa lapangan, dan riwayat iuran anggota.
import 'package:flutter/material.dart';

import '../data/auth.dart';
import 'login.dart';
import 'widgets.dart';

/// Buka layar masuk. True kalau pengguna benar-benar masuk.
Future<bool> openLogin(BuildContext context) async {
  final ok = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (ctx) => LoginPage(onSignedIn: () => Navigator.pop(ctx, true)),
    ),
  );
  return ok == true;
}

/// Isi halaman untuk tamu yang membuka bagian uang klub.
class LockedMoney extends StatelessWidget {
  const LockedMoney({
    super.key,
    required this.title,
    this.what = 'kas, iuran, dan biaya sewa',
  });

  /// Nama halaman, supaya judulnya tetap jelas ("Iuran", "Kas klub").
  final String title;

  /// Apa yang terkunci, untuk kalimat penjelas.
  final String what;

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: title,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        children: [
          const SizedBox(height: 40),
          EmptyState(
            icon: Icons.lock_outline,
            title: 'Khusus anggota klub',
            // Jangan berbunyi seperti kerusakan: sebutkan alasannya, dan
            // sebutkan juga bahwa data lain tetap bisa dilihat.
            message: 'Data $what hanya untuk yang sudah masuk. '
                'Jadwal, klasemen, dan pengumuman tetap bisa dilihat tanpa akun.',
            actionLabel: Auth.isGuest ? 'Masuk' : null,
            onAction: Auth.isGuest
                ? () async {
                    if (await openLogin(context) && context.mounted) {
                      // Halaman ini dibangun ulang oleh pemanggil saat sesi
                      // berubah; di sini cukup memastikan tidak ada layar
                      // setengah jadi yang tertinggal.
                      Navigator.of(context).maybePop();
                    }
                  }
                : null,
          ),
        ],
      ),
    );
  }
}
