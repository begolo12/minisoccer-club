import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/soft.dart';
import '../data/auth.dart';
import '../data/models.dart';
import 'fmt.dart';
import 'forms.dart';
import 'theme.dart';
import 'widgets.dart';

class _PayData {
  final List<Payment> payments;
  final List<Member> members;
  final double? standard;

  /// Sumber yang gagal dimuat; halaman tetap menampilkan sisanya.
  final List<String> failures;

  _PayData(this.payments, this.members, this.standard, this.failures);

  static Future<_PayData> load(String period) async {
    final r = await Future.wait<Soft<Object?>>([
      soft('Iuran bulan ini', () => Payment.all(period: period), fallback: const <Payment>[]),
      soft('Daftar anggota', () => Member.all(activeOnly: true), fallback: const <Member>[]),
      soft('Nominal iuran', Payment.standardAmount, fallback: null),
    ]);
    final failures = settle(r);
    return _PayData(
      r[0].value! as List<Payment>,
      r[1].value! as List<Member>,
      r[2].value as double?,
      failures,
    );
  }
}

class PaymentsPage extends StatefulWidget {
  const PaymentsPage({super.key});

  @override
  State<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends State<PaymentsPage> {
  String _period = periodNow();
  late Future<_PayData> _future;

  @override
  void initState() {
    super.initState();
    _future = _PayData.load(_period);
  }

  Future<void> _reload() async {
    final f = _PayData.load(_period);
    setState(() => _future = f);
    await f;
  }

  List<String> get _periods => recentPeriods();

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return PageScaffold(
      title: 'Iuran',
      subtitle: periodLabel(_period),
      actions: [
        if (Auth.canWrite)
          iconAction(context, Icons.add, () async {
            if (await showPaymentForm(context, period: _period)) _reload();
          }, tooltip: 'Catat iuran'),
      ],
      child: Column(
        children: [
          PeriodChips(
            periods: _periods,
            selected: _period,
            onChanged: (p) {
              if (p == null) return;
              setState(() => _period = p);
              _reload();
            },
          ),
          const SizedBox(height: 12),
          Expanded(
            child: AsyncView<_PayData>(
              future: _future,
              onRefresh: _reload,
              builder: (d) {
                final total = d.payments.fold<double>(0, (s, p) => s + p.amount);
                final paidIds = d.payments.map((p) => p.memberId).toSet();
                final unpaid = d.members.where((m) => !paidIds.contains(m.id)).toList();
                final paid = d.members.length - unpaid.length;
                final missing = (d.standard ?? 0) * unpaid.length;

                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                  children: [
                    if (d.failures.isNotEmpty)
                      DegradedNotice(failures: d.failures, onRetry: _reload),
                    StatStrip(
                      children: [
                        StatTile(
                          label: 'Terkumpul',
                          value: fmtMoney(total),
                          color: AppThemes.money(context),
                        ),
                        StatTile(
                          label: 'Lunas',
                          value: '$paid/${d.members.length}',
                          hint: unpaid.isEmpty ? 'semua lunas' : '${unpaid.length} belum',
                          color: unpaid.isEmpty ? t.colorScheme.primary : null,
                        ),
                        if (missing > 0)
                          StatTile(
                            label: 'Kurang',
                            value: fmtMoney(missing),
                            hint: '${unpaid.length} anggota',
                            color: AppThemes.bad(context),
                          ),
                      ],
                    ),
                    if (unpaid.isNotEmpty) ...[
                      const SectionTitle('Belum bayar'),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final m in unpaid)
                            _UnpaidChip(
                              name: m.name,
                              onTap: Auth.canWrite
                                  ? () async {
                                      if (await showPaymentForm(context,
                                          period: _period, memberId: m.id)) {
                                        _reload();
                                      }
                                    }
                                  : null,
                            ),
                        ],
                      ),
                    ],
                    const SectionTitle('Riwayat pembayaran'),
                    if (d.payments.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: EmptyState(
                          icon: Icons.account_balance_wallet_outlined,
                          title: 'Belum ada iuran tercatat',
                          message: 'Catat pembayaran pertama untuk ${periodLabel(_period)}.',
                          actionLabel: Auth.canWrite ? 'Catat iuran' : null,
                          onAction: Auth.canWrite
                              ? () async {
                                  if (await showPaymentForm(context, period: _period)) _reload();
                                }
                              : null,
                        ),
                      )
                    else
                      for (final p in d.payments)
                        RowItem(
                          leading: Icon(Icons.check_circle, size: 15, color: t.colorScheme.primary),
                          title: p.memberName,
                          subtitle: '${fmtDate(p.paidAt)}${p.note != null ? " • ${p.note}" : ""}',
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                fmtMoney(p.amount),
                                style: t.textTheme.table.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppThemes.money(context),
                                ),
                              ),
                              if (Auth.canWrite) ...[
                                const SizedBox(width: 6),
                                iconAction(context, Icons.delete_outline, () async {
                                  if (await confirm(context, 'Hapus iuran?', 'Catatan ${p.memberName} dihapus.')) {
                                    if (!context.mounted) return;
                                    if (await attempt(context, () => Payment.delete(p.id), fail: 'Gagal menghapus')) {
                                      _reload();
                                    }
                                  }
                                }, tooltip: 'Hapus'),
                              ],
                            ],
                          ),
                        ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Nama anggota yang belum bayar. Bisa diketuk untuk mencatat pembayarannya.
class _UnpaidChip extends StatelessWidget {
  const _UnpaidChip({required this.name, this.onTap});

  final String name;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bad = AppThemes.bad(context);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Container(
          height: 32,
          padding: const EdgeInsets.only(left: 10, right: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: bad.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name, style: const TextStyle(fontSize: 12.5)),
              if (onTap != null) ...[
                const SizedBox(width: 6),
                Icon(Icons.check, size: 13, color: bad),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
