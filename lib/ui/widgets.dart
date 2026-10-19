import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.colorScheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.colorScheme.border),
      ),
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
          // Nilai uang (mis. "Rp 1.250.000") tidak boleh dipotong ellipsis di
          // tile selebar sepertiga layar — kecilkan agar tetap terbaca utuh.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: t.textTheme.h3.copyWith(color: color),
              maxLines: 1,
            ),
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
          return loading ?? const Center(child: CircularProgressIndicator());
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
    return Scaffold(
      body: SafeArea(
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
            Expanded(child: child),
          ],
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
