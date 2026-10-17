import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'theme.dart';

/// Kartu dasar app: permukaan card + garis tipis gradien "oil".
/// Semua kartu pakai ini supaya radius, border, dan sheen-nya seragam.
class OilCard extends StatelessWidget {
  const OilCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
    this.highlight = false,
    this.radius = 16,
    this.background,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// Versi lebih terang: border gradien penuh + sheen. Untuk item terpilih/juara.
  final bool highlight;
  final double radius;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final dark = t.brightness == Brightness.dark;

    final body = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background ?? t.colorScheme.card,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: highlight
                    ? [
                        AppThemes.oilA.withValues(alpha: dark ? 0.75 : 0.9),
                        AppThemes.oilB.withValues(alpha: dark ? 0.55 : 0.7),
                        AppThemes.oilC.withValues(alpha: dark ? 0.45 : 0.6),
                      ]
                    : [
                        (dark ? Colors.white : Colors.black).withValues(alpha: dark ? 0.10 : 0.07),
                        t.colorScheme.border,
                        (dark ? Colors.white : Colors.black).withValues(alpha: dark ? 0.04 : 0.03),
                      ],
              ),
              boxShadow: highlight
                  ? [
                      BoxShadow(
                        color: AppThemes.oilA.withValues(alpha: dark ? 0.18 : 0.14),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            padding: const EdgeInsets.all(1), // tebal garis
            child: body,
          ),
        ),
      ),
    );
  }
}

/// Chip kecil untuk status/metadata. Lebih ringan dari ShadBadge.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color, this.icon});

  final String text;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final c = color ?? t.colorScheme.mutedForeground;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: c),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c, letterSpacing: 0.2),
          ),
        ],
      ),
    );
  }
}

/// Placeholder loading berbentuk kartu — hindari layar kosong + spinner.
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
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        for (var i = 0; i < widget.count; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, __) => Container(
                height: widget.height,
                decoration: BoxDecoration(
                  color: t.colorScheme.card.withValues(alpha: 0.55 + 0.35 * _c.value),
                  borderRadius: BorderRadius.circular(16),
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
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: t.colorScheme.muted,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 30, color: t.colorScheme.mutedForeground),
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
            Icon(Icons.cloud_off_rounded, size: 36, color: t.colorScheme.mutedForeground),
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

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Row(
        children: [
          Text(text, style: t.textTheme.large),
          const Spacer(),
          if (action != null) action!,
        ],
      ),
    );
  }
}

/// Kartu statistik ringkas.
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
    return OilCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: color ?? t.colorScheme.mutedForeground),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  label,
                  style: t.textTheme.small,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: t.textTheme.h3.copyWith(color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(hint!, style: t.textTheme.small, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
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

/// Scaffold halaman tab dengan judul besar + aksi.
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
    final dark = t.brightness == Brightness.dark;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              dark
                  ? t.colorScheme.primary.withValues(alpha: 0.06)
                  : t.colorScheme.primary.withValues(alpha: 0.05),
              t.colorScheme.background,
              t.colorScheme.background,
            ],
            stops: const [0, 0.28, 1],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: t.textTheme.h3),
                          if (subtitle != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(subtitle!, style: t.textTheme.small),
                            ),
                        ],
                      ),
                    ),
                    ...actions,
                  ],
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tombol ikon bulat untuk app bar.
Widget iconAction(BuildContext context, IconData icon, VoidCallback onTap, {String? tooltip}) {
  final t = ShadTheme.of(context);
  return Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: t.colorScheme.secondary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: t.colorScheme.secondaryForeground),
        ),
      ),
    ),
  );
}
