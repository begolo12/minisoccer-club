import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

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
  const ErrorState({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

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
            Text('Gagal memuat data', style: t.textTheme.large),
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
          if (action != null) ...[const SizedBox(width: 8), action!],
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
              child: Text(
                label.toUpperCase(),
                style: t.textTheme.h4.copyWith(fontSize: 11, letterSpacing: 0.9),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
          Text(hint!, style: t.textTheme.small.copyWith(fontFeatures: AppThemes.tabular)),
      ],
    );
  }
}

/// Satu baris data: label kiri, nilai kanan, garis pemisah rambut.
/// Dipakai untuk daftar apa pun yang lebih penting dibandingkan daripada
/// dibaca sebagai kartu.
class RowItem extends StatelessWidget {
  const RowItem({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.leading,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? leading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.textTheme.large, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: t.textTheme.small, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
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

/// Bungkus Future + loading/error/retry + pull-to-refresh.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.future,
    required this.builder,
    required this.onRefresh,
    this.loading,
  });

  final Future<T> future;
  final Widget Function(T data) builder;
  final Future<void> Function() onRefresh;
  final Widget? loading;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return loading ?? const SkeletonList();
        }
        if (snap.hasError) {
          return ErrorState(error: snap.error!, onRetry: () => onRefresh());
        }
        return RefreshIndicator(
          onRefresh: onRefresh,
          child: builder(snap.data as T),
        );
      },
    );
  }
}

/// Lebar baca maksimum. Di layar lebar isi tidak melar sampai 1400px.
const kContentMax = 980.0;

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
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    );
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
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            border: Border.all(color: t.colorScheme.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 17, color: color),
        ),
      ),
    ),
  );
}
