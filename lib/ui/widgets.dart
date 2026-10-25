import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/db.dart';
import '../core/offline.dart';
import '../data/models.dart';
import 'fmt.dart';
import 'theme.dart';

/// Permukaan datar: satu bidang + garis rambut. Tanpa gradien, tanpa bayangan.
/// Dipakai untuk kelompok data yang memang butuh wadah; baris biasa cukup
/// garis pemisah.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.highlight = false,
    this.radius = 12,
    this.background,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// Versi bertanda: garis aksen hijau. Untuk laga berikutnya / juara.
  final bool highlight;
  final double radius;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: background ?? t.colorScheme.card,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: highlight ? t.colorScheme.primary.withValues(alpha: 0.55) : t.colorScheme.border,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Label status/metadata. Huruf besar sempit, bukan badge berwarna-warni.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final c = color ?? t.colorScheme.mutedForeground;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text.toUpperCase(),
          style: TextStyle(
            fontFamily: AppThemes.display,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: c,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

/// Label isi daftar (mis. nama pemain dalam satu tim): garis rambut, bukan
/// chip Material yang berbingkai tebal.
class TagChip extends StatelessWidget {
  const TagChip(this.text, {super.key, this.onRemove, this.onTap});

  final String text;
  final VoidCallback? onRemove;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Container(
          height: 30,
          padding: EdgeInsets.only(left: 9, right: onRemove == null ? 9 : 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: t.colorScheme.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text, style: const TextStyle(fontSize: 12)),
              if (onRemove != null) ...[
                const SizedBox(width: 2),
                InkWell(
                  onTap: onRemove,
                  borderRadius: BorderRadius.circular(4),
                  // Ketukan diperluas ke ±24px meski glyph-nya 13px: tombol
                  // ini mengeluarkan pemain dari tim, dan di Wrap yang padat
                  // target 17px hampir selalu salah ketuk.
                  child: Padding(
                    padding: const EdgeInsets.all(5.5),
                    child: Icon(Icons.close, size: 13, color: t.colorScheme.mutedForeground),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Placeholder loading berbentuk baris — hindari layar kosong + spinner.
class SkeletonList extends StatefulWidget {
  const SkeletonList({super.key, this.count = 4, this.height = 64});

  final int count;
  final double height;

  @override
  State<SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<SkeletonList> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      children: [
        for (var i = 0; i < widget.count; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, _) => Container(
                height: widget.height,
                decoration: BoxDecoration(
                  color: t.colorScheme.card.withValues(alpha: 0.55 + 0.35 * _c.value),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: t.colorScheme.border.withValues(alpha: 0.6)),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Empty state — selalu kasih aksi biar user nggak bingung.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: t.colorScheme.muted,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 26, color: t.colorScheme.mutedForeground),
            ),
            const SizedBox(height: 16),
            Text(title, style: t.textTheme.large, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(message!, style: t.textTheme.muted, textAlign: TextAlign.center),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              ShadButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.error,
    required this.onRetry,
    this.title = 'Gagal memuat data',
    this.extra,
  });

  final Object error;
  final VoidCallback onRetry;
  final String title;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 32, color: t.colorScheme.mutedForeground),
            const SizedBox(height: 12),
            Text(title, style: t.textTheme.large, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
              '$error',
              style: t.textTheme.small,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            ShadButton.outline(onPressed: onRetry, child: const Text('Coba lagi')),
            ?extra,
          ],
        ),
      ),
    );
  }
}

/// Judul bagian: label kecil huruf besar + garis tipis sampai tepi kanan.
/// Menggantikan judul tebal yang bersaing dengan judul halaman.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.action, this.top = 18});

  final String text;
  final Widget? action;
  final double top;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: 10, top: top),
      child: Row(
        children: [
          Text(text.toUpperCase(), style: t.textTheme.h4),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 1, color: t.colorScheme.border)),
          if (action != null) ...[
            const SizedBox(width: 8),
            // Tinggi aksi dipaksa 40px: tombol teks ("Semua", "Buka") hanya
            // 32px sendirian — target ketuk terkecil di halaman, tepat di
            // tempat yang jadi pintu ke halaman lain.
            SizedBox(height: 40, child: action!),
          ],
        ],
      ),
    );
  }
}

/// Angka besar untuk ringkasan: label di atas, nilai sempit di bawah.
/// Tanpa wadah sendiri supaya tiga angka bisa berbagi satu strip.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.hint,
    this.color,
    this.icon,
  });

  final String label;
  final String value;
  final String? hint;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: t.colorScheme.mutedForeground),
              const SizedBox(width: 5),
            ],
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  style: t.textTheme.h4.copyWith(fontSize: 11, letterSpacing: 0.9),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: t.textTheme.h1.copyWith(
              fontSize: 34,
              color: color ?? t.colorScheme.foreground,
            ),
            maxLines: 1,
          ),
        ),
        if (hint != null)
          // Menyusut, bukan terpotong: "26/31 lunas" tetap terbaca utuh di
          // layar 320px tanpa menggeser garis pemisah.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              hint!,
              maxLines: 1,
              style: t.textTheme.small.copyWith(fontFeatures: AppThemes.tabular),
            ),
          ),
      ],
    );
  }
}

/// Satu baris data: label kiri, nilai kanan, garis pemisah rambut.
/// Dipakai untuk daftar apa pun yang lebih penting dibandingkan daripada
/// dibaca sebagai kartu.
///
/// [trailing] diletakkan di baris sendiri di bawah judul saat layar sempit,
/// supaya label panjang (mis. "Tim Elang MENANG") tidak menabrak judul.
class RowItem extends StatelessWidget {
  const RowItem({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.leading,
    this.onTap,
    this.trailingBelow = false,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? leading;
  final VoidCallback? onTap;

  /// Pindahkan [trailing] ke bawah judul (dipakai baris skor di HP).
  final bool trailingBelow;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: t.textTheme.large, maxLines: 1, overflow: TextOverflow.ellipsis),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(subtitle!, style: t.textTheme.small, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
      ],
    );

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: trailingBelow && trailing != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      texts,
                      const SizedBox(height: 3),
                      Align(alignment: Alignment.centerLeft, child: trailing!),
                    ],
                  )
                : texts,
          ),
          if (!trailingBelow && trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.colorScheme.border.withValues(alpha: 0.7))),
      ),
      child: onTap == null
          ? row
          : InkWell(onTap: onTap, borderRadius: BorderRadius.circular(8), child: row),
    );
  }
}

/// Satu strip angka ringkasan: beberapa [StatTile] dalam satu bidang,
/// dipisah garis rambut. Dipakai Beranda, Tanding, Iuran, Kas, Tim, Statistik.
class StatStrip extends StatelessWidget {
  const StatStrip({super.key, required this.children, this.padding});

  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return Container(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: Border.all(color: t.colorScheme.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                height: 44,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                color: t.colorScheme.border,
              ),
            Expanded(child: children[i]),
          ],
        ],
      ),
    );
  }
}

/// Tabel klasemen. Satu implementasi untuk Tanding, Tim, dan Turnamen.
///
/// Di layar sempit hanya MP/SG/POIN yang tampil supaya nama tim tetap terbaca;
/// kolom menang/seri/kalah dan GM/GK muncul saat ada ruang.
///
/// Singkatan dipilih yang lazim di tabel sepak bola Indonesia: MP = main
/// (jumlah pertandingan), M = menang, S = seri, K = kalah, GM = gol
/// memasukkan, GK = gol kemasukan, SG = selisih gol. Versi sebelumnya memakai
/// W/D/L dari bahasa Inggris, sehingga satu tabel memuat dua bahasa.
class StandingsTable extends StatelessWidget {
  const StandingsTable({super.key, required this.standings, this.top = 0});

  final List<Standing> standings;

  /// Berapa baris teratas yang dianggap lolos/ditonjolkan.
  final int top;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final head = t.textTheme.h4.copyWith(fontSize: 10.5, letterSpacing: 0.8);
    final cell = t.textTheme.table;

    Widget num(String text, {TextStyle? style}) => Text(
          text,
          textAlign: TextAlign.right,
          style: (style ?? cell).copyWith(fontFeatures: AppThemes.tabular),
        );

    // Lebar wadah, bukan lebar layar: di rail desktop tabel ini sempit walau
    // jendelanya lebar.
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 520;
        return Panel(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            children: [
              Row(
                children: [
                  const SizedBox(width: 22),
                  Expanded(child: Text('TIM', style: head)),
                  SizedBox(width: 24, child: Text('MP', textAlign: TextAlign.right, style: head)),
                  if (wide) ...[
                    SizedBox(width: 22, child: Text('M', textAlign: TextAlign.right, style: head)),
                    SizedBox(width: 22, child: Text('S', textAlign: TextAlign.right, style: head)),
                    SizedBox(width: 22, child: Text('K', textAlign: TextAlign.right, style: head)),
                    SizedBox(width: 28, child: Text('GM', textAlign: TextAlign.right, style: head)),
                    SizedBox(width: 28, child: Text('GK', textAlign: TextAlign.right, style: head)),
                  ],
                  SizedBox(width: 32, child: Text('SG', textAlign: TextAlign.right, style: head)),
                  SizedBox(width: 34, child: Text('POIN', textAlign: TextAlign.right, style: head)),
                ],
              ),
              for (var i = 0; i < standings.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 22,
                        child: Text(
                          '${i + 1}',
                          style: t.textTheme.h2.copyWith(
                            fontSize: 16,
                            color: i < top && standings[i].played > 0
                                ? t.colorScheme.primary
                                : t.colorScheme.mutedForeground,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          standings[i].name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: i < top && standings[i].played > 0
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      SizedBox(width: 24, child: num('${standings[i].played}')),
                      if (wide) ...[
                        SizedBox(width: 22, child: num('${standings[i].won}')),
                        SizedBox(width: 22, child: num('${standings[i].drawn}')),
                        SizedBox(width: 22, child: num('${standings[i].lost}')),
                        SizedBox(width: 28, child: num('${standings[i].goalsFor}')),
                        SizedBox(width: 28, child: num('${standings[i].goalsAgainst}')),
                      ],
                      SizedBox(
                        width: 32,
                        child: num(
                          standings[i].goalDiff > 0
                              ? '+${standings[i].goalDiff}'
                              : '${standings[i].goalDiff}',
                        ),
                      ),
                      SizedBox(
                        width: 34,
                        child: num(
                          '${standings[i].points}',
                          style: cell.copyWith(
                            fontFamily: AppThemes.display,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: t.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Baris satu pertandingan: skor di kiri, tim + waktu di tengah, status di
/// kanan (turun ke bawah di layar sempit).
class MatchRow extends StatelessWidget {
  const MatchRow({
    super.key,
    required this.match,
    this.onTap,
    this.showResult = true,
    this.onFinish,
    this.forTeamId,
  });

  final Match match;
  final VoidCallback? onTap;

  /// Tampilkan pemenang ("Tim A MENANG") alih-alih status saja.
  final bool showResult;

  /// Tombol "Selesai" di baris. Null saat laga sudah selesai atau user hanya
  /// boleh membaca.
  final VoidCallback? onFinish;

  /// Skor dan hasil dibaca dari sudut pandang tim ini. Di halaman tim, tim
  /// bisa menjadi tim away — tanpa ini "5–3" dan "KALAH" terbalik.
  final int? forTeamId;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final finished = match.finished;
    final asHome = forTeamId == null || match.homeTeamId == forTeamId;
    final own = asHome ? match.goalsFor : match.goalsAgainst;
    final opp = asHome ? match.goalsAgainst : match.goalsFor;
    final win = own > opp;
    final draw = own == opp;
    final color = !finished
        ? (match.ongoing ? t.colorScheme.primary : t.colorScheme.mutedForeground)
        : (draw
            ? t.colorScheme.mutedForeground
            : (win ? t.colorScheme.primary : AppThemes.bad(context)));

    final String status;
    if (finished) {
      // Poin dihitung dari sudut pandang baris ini, bukan "poin pemenang".
      // Dulu selalu memakai `pointsForWinner` (3), sehingga baris tim yang
      // KALAH pun berbunyi "KALAH · 3 POIN".
      final points = draw ? kPointsDraw : (win ? kPointsWin : 0);
      // Nama pemenang juga harus dari sudut pandang yang sama: kalau tim ini
      // bermain sebagai away, `match.homeName` adalah lawan.
      final winnerName = asHome
          ? (win ? match.homeName : match.awayName)
          : (win ? match.awayName : match.homeName);
      final result = showResult
          ? (draw ? 'SERI' : '$winnerName MENANG')
          : (win ? 'MENANG' : (draw ? 'SERI' : 'KALAH'));
      status = '$result · $points POIN';
    } else {
      status = match.ongoing ? 'BERLANGSUNG' : 'AKAN DATANG';
    }

    return RowItem(
      onTap: onTap,
      leading: SizedBox(
        width: 54,
        // Laga berjalan juga menampilkan skor sementara: sebelum menekan
        // "Selesai" skor yang akan dikunci harus terbaca di baris ini.
        child: finished || match.ongoing
            ? Text(
                '$own–$opp',
                style: t.textTheme.h1.copyWith(fontSize: 24, color: color),
              )
            : Icon(Icons.schedule, size: 18, color: color),
      ),
      title: forTeamId == null || asHome
          ? '${match.homeName} vs ${match.awayName}'
          : '${match.awayName} vs ${match.homeName}',
      subtitle:
          '${fmtDateTime(match.playedAt)}${match.venue == null ? '' : ' • ${match.venue}'}',
      trailingBelow: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            status,
            style: TextStyle(
              fontFamily: AppThemes.display,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.1,
              color: color,
            ),
          ),
          // Tombol tetap mendampingi status: "AKAN DATANG" jangan hilang hanya
          // karena baris ini bisa diselesaikan.
          if (onFinish != null) ...[
            const SizedBox(width: 12),
            ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: onFinish,
              leading: const Icon(Icons.check, size: 14),
              child: const Text('Selesai'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Satu baris skor: nama tim, tombol −, angka besar, tombol +. Disusun
/// bertumpuk (bukan dua kolom berdampingan) supaya di 390px tombol tidak
/// berdesakan dengan tanda pemisah skor. Dipakai laga internal & turnamen.
class ScoreStepper extends StatelessWidget {
  const ScoreStepper({
    super.key,
    required this.name,
    required this.value,
    required this.onChanged,
  });

  final String name;
  final int value;

  /// Null saat menyimpan, supaya skor tidak bisa diubah di tengah request.
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final enabled = onChanged != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        border: Border.all(color: t.colorScheme.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.textTheme.large.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          _StepButton(
            icon: Icons.remove,
            onTap: enabled && value > 0 ? () => onChanged!(value - 1) : null,
            label: 'Kurangi gol $name',
          ),
          SizedBox(
            width: 48,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: t.textTheme.h1Large.copyWith(fontSize: 30, color: t.colorScheme.foreground),
            ),
          ),
          _StepButton(
            icon: Icons.add,
            onTap: enabled ? () => onChanged!(value + 1) : null,
            label: 'Tambah gol $name',
          ),
        ],
      ),
    );
  }
}

/// Ringkasan hasil dari skor sementara: "Tim B menang 1–0 · 3 poin".
/// Dipakai dialog skor supaya akibat satu gol langsung terbaca.
String scoreOutcome(String homeName, String awayName, int home, int away) =>
    home > away
        ? '$homeName menang $home–$away · 3 poin'
        : (home < away
            ? '$awayName menang $away–$home · 3 poin'
            : 'Seri $home–$away · 1 poin');

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap, required this.label});

  final IconData icon;
  final VoidCallback? onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final enabled = onTap != null;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        // Nonaktif tetap bergaris: tombol − yang hilang total terbaca sebagai
        // tombol rusak, bukan sebagai "skor sudah 0".
        color: enabled ? t.colorScheme.muted : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: enabled ? Colors.transparent : t.colorScheme.border),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          // 40px mengikuti pedoman sentuh; stepper skor ditekan berulang
          // cepat saat mencatat gol, salah ketuk di sini mahal harganya.
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(
              icon,
              size: 18,
              color: enabled ? t.colorScheme.foreground : t.colorScheme.mutedForeground,
            ),
          ),
        ),
      ),
    );
  }
}

/// Deret chip periode bulan. [all] menambahkan pilihan "Semua".
class PeriodChips extends StatefulWidget {
  const PeriodChips({
    super.key,
    required this.periods,
    required this.selected,
    required this.onChanged,
    this.all = false,
    this.label,
  });

  /// Daftar periode `YYYY-MM`, terbaru dulu.
  final List<String> periods;
  final String? selected;
  final ValueChanged<String?> onChanged;
  final bool all;
  final String Function(String)? label;

  @override
  State<PeriodChips> createState() => _PeriodChipsState();
}

class _PeriodChipsState extends State<PeriodChips> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    // Gulirkan chip terpilih ke dalam layar setelah daftar dibangun. Tanpa ini
    // di HP sempit chip aktif bisa berada di luar layar (terpotong di tepi
    // kanan), sehingga pengguna tidak tahu periode mana yang sedang dilihat.
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
  }

  @override
  void didUpdateWidget(covariant PeriodChips old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
    }
  }

  void _revealSelected() {
    if (!mounted || !_controller.hasClients) return;
    final items = <String?>[if (widget.all) null, ...widget.periods];
    final index = items.indexOf(widget.selected);
    if (index < 0) return;
    // Lebar chip tidak seragam ("Semua" vs "November 2026"), jadi posisinya
    // diperkirakan dari rata-rata lalu dijepit ke rentang gulir yang sah.
    const estimate = 96.0;
    final target = (index * estimate - 40).clamp(0.0, _controller.position.maxScrollExtent);
    _controller.animateTo(
      target.toDouble(),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final items = <String?>[if (widget.all) null, ...widget.periods];
    return SizedBox(
      height: 38,
      child: ListView.separated(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final p = items[i];
          final isSelected = p == widget.selected;
          return Material(
            color: isSelected ? t.colorScheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            child: InkWell(
              borderRadius: BorderRadius.circular(7),
              onTap: () => widget.onChanged(p),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: isSelected ? t.colorScheme.primary : t.colorScheme.border,
                  ),
                ),
                child: Text(
                  p == null ? 'Semua' : (widget.label?.call(p) ?? periodLabel(p)),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected
                        ? t.colorScheme.primaryForeground
                        : t.colorScheme.mutedForeground,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Periode iuran untuk pemilih: bulan depan, bulan ini, lalu beberapa bulan ke
/// belakang — terbaru dulu.
///
/// Bulan depan ikut disertakan karena iuran sering dibayar di muka; tanpa itu
/// pembayaran bulan depan tidak bisa dicatat dan pengguna mencatatnya di bulan
/// yang salah. [monthsBack] menentukan seberapa jauh tunggakan bisa dicatat.
List<String> recentPeriods({int monthsBack = 12}) => [
      // Bulan depan (i = -1) → bulan ini (0) → bulan-bulan sebelumnya.
      for (var i = -1; i < monthsBack; i++)
        () {
          final now = DateTime.now();
          final d = DateTime(now.year, now.month - i);
          return '${d.year}-${d.month.toString().padLeft(2, '0')}';
        }(),
    ];

/// Bungkus Future + loading/error/retry + pull-to-refresh.
///
/// Stateful dengan sengaja: setiap `_reload()` mengganti `future`, dan kalau
/// widget ini memakai FutureBuilder polos, `connectionState` kembali
/// `waiting` sehingga SELURUH halaman diganti skeleton — pull-to-refresh
/// kehilangan indikatornya dan posisi scroll terlempar ke atas. Lebih buruk
/// lagi, reload yang gagal (jaringan putus sesaat) membuang data lama dan
/// menampilkan layar error penuh, padahal datanya masih valid untuk dibaca.
///
/// Aturannya sekarang:
///   * belum pernah ada data  → skeleton, lalu layar error kalau gagal;
///   * sudah ada data         → data tetap tampil selama refresh; kalau
///     refresh gagal, data lama dipertahankan dan kegagalannya dilaporkan
///     lewat [onRefreshError] (halaman menampilkan DegradedNotice/toast).
class AsyncView<T> extends StatefulWidget {
  const AsyncView({
    super.key,
    required this.future,
    required this.builder,
    required this.onRefresh,
    this.loading,
    this.onRefreshError,
  });

  final Future<T> future;
  final Widget Function(T data) builder;
  final Future<void> Function() onRefresh;
  final Widget? loading;

  /// Dipanggil saat refresh gagal padahal data lama masih ditampilkan.
  final void Function(Object error)? onRefreshError;

  @override
  State<AsyncView<T>> createState() => _AsyncViewState<T>();
}

class _AsyncViewState<T> extends State<AsyncView<T>> {
  /// Data terakhir yang berhasil dimuat. Dipertahankan lintas reload.
  T? _data;
  bool _hasData = false;

  @override
  void initState() {
    super.initState();
    _watch();
  }

  @override
  void didUpdateWidget(AsyncView<T> old) {
    super.didUpdateWidget(old);
    if (widget.future != old.future) _watch();
  }

  void _watch() {
    final f = widget.future;
    f.then((v) {
      if (!mounted) return;
      setState(() {
        _data = v;
        _hasData = true;
      });
    }, onError: (Object e) {
      if (!mounted) return;
      if (_hasData) {
        // Data lama masih sah: jangan ganti layar dengan error penuh. Beri
        // tahu lewat callback halaman, atau toast kalau halaman tidak
        // menyediakannya — kegagalan diam-diam lebih buruk daripada data
        // yang terlihat tidak berubah tanpa penjelasan.
        final handler = widget.onRefreshError;
        if (handler != null) {
          handler(e);
        } else if (context.mounted) {
          toast(context, 'Gagal menyegarkan: ${errText(e)}');
        }
        setState(() {}); // lepas status menunggu
      } else {
        setState(() {}); // biarkan FutureBuilder menampilkan ErrorState
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: widget.future,
      builder: (context, snap) {
        // Selama belum pernah ada data sama sekali, tampilkan loading/error.
        if (!_hasData) {
          if (snap.connectionState == ConnectionState.waiting) {
            return widget.loading ?? const SkeletonList();
          }
          if (snap.hasError) {
            return ErrorState(error: snap.error!, onRetry: () => widget.onRefresh());
          }
          final fresh = snap.data;
          if (fresh == null) return widget.loading ?? const SkeletonList();
          return RefreshIndicator(
            onRefresh: widget.onRefresh,
            child: widget.builder(fresh),
          );
        }
        // Sudah ada data: pertahankan isi halaman, refresh berjalan diam-diam.
        return RefreshIndicator(
          onRefresh: widget.onRefresh,
          child: widget.builder(_data as T),
        );
      },
    );
  }
}

/// Lebar baca maksimum. Di layar lebar isi tidak melar sampai 1400px.
const kContentMax = 980.0;

/// Semua daftar tetap bisa ditarik walau isinya pendek, supaya
/// pull-to-refresh bekerja juga di halaman yang baru berisi satu baris.
class AppScrollBehavior extends ScrollBehavior {
  const AppScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      AlwaysScrollableScrollPhysics(parent: super.getScrollPhysics(context));
}

/// Scaffold semua halaman: judul, subjudul, aksi, garis pemisah, isi.
/// Otomatis menaruh tombol kembali saat halaman ditumpuk.
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final canPop = Navigator.canPop(context);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kContentMax),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 14, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (canPop)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: iconAction(context, Icons.arrow_back_rounded,
                              () => Navigator.pop(context), tooltip: 'Kembali'),
                        ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: t.textTheme.h3, maxLines: 1, overflow: TextOverflow.ellipsis),
                            if (subtitle != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(subtitle!, style: t.textTheme.small),
                              ),
                          ],
                        ),
                      ),
                      ...actions,
                    ],
                  ),
                ),
                Container(height: 1, color: t.colorScheme.border),
                // Halaman turunan (Anggota, Kas, Booking, …) menutupi shell,
                // jadi bilah status shell tidak terlihat di sini. Tanpa ini
                // pengguna bisa mengisi data offline tanpa tahu ada perubahan
                // yang belum terkirim.
                const OfflineStrip(),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bilah status offline: data dari cache dan/atau perubahan yang belum
/// terkirim, plus tombol Sinkron.
///
/// Dipakai di shell **dan** di `PageScaffold`, karena halaman turunan menutupi
/// shell. Tanpa ini pengguna bisa mengisi data offline tanpa tahu bahwa
/// datanya belum ada di cloud.
///
/// Tidak mengambil tempat saat online dan tidak ada antrean.
class OfflineStrip extends StatefulWidget {
  const OfflineStrip({super.key, this.padding = const EdgeInsets.fromLTRB(20, 6, 8, 6)});

  final EdgeInsets padding;

  @override
  State<OfflineStrip> createState() => _OfflineStripState();
}

class _OfflineStripState extends State<OfflineStrip> {
  bool _busy = false;

  Future<void> _sync() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await Db.sync();
      if (!mounted) return;
      if (r.authExpired) {
        // Tanpa pesan ini tombol Sinkron tampak "diam": pengguna menekannya,
        // tidak terjadi apa-apa, dan tidak tahu harus masuk lagi.
        toast(context, 'Masuk lagi untuk mengirim ${r.remaining} perubahan');
      } else if (r.sent > 0) {
        toast(context, '${r.sent} perubahan terkirim');
      } else if (r.offline) {
        toast(context, 'Masih offline — coba lagi nanti');
      } else if (r.failed > 0) {
        toast(context, '${r.failed} perubahan ditolak server');
      } else {
        toast(context, 'Tidak ada yang perlu dikirim');
      }
    } catch (e) {
      if (mounted) toast(context, 'Gagal sinkron: ${errText(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: Outbox.pending,
      builder: (context, pending, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: Db.offline,
          builder: (context, offline, _) {
            if (!offline && pending == 0) return const SizedBox.shrink();
            final syncing = _busy || Outbox.syncing.value;
            return Container(
              color: t.colorScheme.muted,
              padding: widget.padding,
              child: Row(
                children: [
                  Icon(
                    syncing
                        ? Icons.sync
                        : (pending > 0 ? Icons.cloud_upload_outlined : Icons.cloud_off),
                    size: 14,
                    color: pending > 0 ? t.colorScheme.primary : t.colorScheme.mutedForeground,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _text(offline, pending, syncing),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.small,
                    ),
                  ),
                  if (pending > 0 && !syncing)
                    TextButton(
                      onPressed: _sync,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Sinkron'),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Jumlah perubahan lebih dulu: itu data yang belum ada di cloud, jadi
  /// paling berisiko kalau app ditutup atau dipasang ulang.
  String _text(bool offline, int pending, bool syncing) {
    if (syncing) return 'Menyinkronkan $pending perubahan…';
    if (pending > 0 && offline) {
      return 'Tanpa internet — $pending perubahan menunggu, dikirim saat tersambung';
    }
    if (pending > 0) return '$pending perubahan menunggu dikirim';
    if (Db.offlineSince == null) return 'Tanpa internet — menampilkan data tersimpan';
    return 'Offline — data tersimpan ${fmtDate(Db.offlineSince!)} '
        '${fmtTime(Db.offlineSince!)}';
  }
}

/// Tombol ikon untuk header. Persegi, garis rambut, tanpa isi warna.
Widget iconAction(
  BuildContext context,
  IconData icon,
  VoidCallback onTap, {
  String? tooltip,
}) {
  final t = ShadTheme.of(context);
  final color = t.colorScheme.mutedForeground;
  return Tooltip(
    message: tooltip ?? '',
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        // 40px, bukan 34: pedoman sentuh Android/iOS meminta ~44px, dan
        // tombol ikon berjajar (ubah/hapus) paling sering salah ketuk di HP
        // kecil. Tampilannya tetap ringkas karena garis tepinya tipis.
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            border: Border.all(color: t.colorScheme.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    ),
  );
}

/// Peringatan bahwa sebagian data gagal dimuat, tanpa menutupi halaman.
///
/// Dipakai saat satu sumber gagal (mis. tabel/izin belum ada di server):
/// menyebut nama sumbernya supaya masalahnya bisa diperbaiki, bukan sekadar
/// "gagal memuat data".
class DegradedNotice extends StatelessWidget {
  const DegradedNotice({super.key, required this.failures, this.onRetry});

  final List<String> failures;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: t.colorScheme.destructive.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.colorScheme.destructive.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 17, color: t.colorScheme.destructive),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sebagian data gagal dimuat',
                  style: t.textTheme.large.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  failures.join(' • '),
                  style: t.textTheme.small.copyWith(color: t.colorScheme.mutedForeground),
                ),
              ],
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 6),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Coba lagi'),
            ),
          ],
        ],
      ),
    );
  }
}
