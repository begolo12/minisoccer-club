import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../data/auth.dart';
import '../data/models.dart';
import 'fmt.dart';
import 'forms.dart';
import 'theme.dart';
import 'widgets.dart';

class _PayData {
  final List<Payment> payments;
  final List<Member> members;

  _PayData(this.payments, this.members);

  static Future<_PayData> load(String period) async {
    final r = await Future.wait([Payment.all(period: period), Member.all(activeOnly: true)]);
    return _PayData(r[0] as List<Payment>, r[1] as List<Member>);
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

  List<String> get _periods => List.generate(6, (i) {
        final d = DateTime(DateTime.now().year, DateTime.now().month - i);
        return '${d.year}-${d.month.toString().padLeft(2, '0')}';
      });

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
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _periods.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final p = _periods[i];
                final selected = p == _period;
                return Material(
                  color: selected ? t.colorScheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(7),
                    onTap: () {
                      setState(() => _period = p);
                      _reload();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: selected ? t.colorScheme.primary : t.colorScheme.border,
                        ),
                      ),
                      child: Text(
                        periodLabel(p),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                          color: selected
                              ? t.colorScheme.primaryForeground
                              : t.colorScheme.mutedForeground,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
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

                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        border: Border.all(color: t.colorScheme.border),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: StatTile(
                              label: 'Terkumpul',
                              value: fmtMoney(total),
                              color: AppThemes.money(context),
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 44,
                            margin: const EdgeInsets.symmetric(horizontal: 14),
                            color: t.colorScheme.border,
                          ),
                          Expanded(
                            flex: 2,
                            child: StatTile(
                              label: 'Lunas',
                              value: '$paid/${d.members.length}',
                              hint: unpaid.isEmpty ? 'semua lunas' : '${unpaid.length} belum',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (unpaid.isNotEmpty) ...[
                      const SectionTitle('Belum bayar'),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final m in unpaid)
                            Material(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(7),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(7),
                                onTap: Auth.canWrite
                                    ? () async {
                                        if (await showPaymentForm(context,
                                            period: _period, memberId: m.id)) {
                                          _reload();
                                        }
                                      }
                                    : null,
                                child: Container(
                                  height: 32,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(7),
                                    border: Border.all(
                                      color: AppThemes.bad(context).withValues(alpha: 0.4),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(m.name, style: const TextStyle(fontSize: 12.5)),
                                      if (Auth.canWrite) ...[
                                        const SizedBox(width: 6),
                                        Tooltip(
                                          message: 'Tandai sudah bayar',
                                          child: Icon(Icons.check, size: 13, color: AppThemes.bad(context)),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
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
