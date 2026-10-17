import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../data/models.dart';
import 'fmt.dart';
import 'forms.dart';
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
                return ChoiceChip(
                  label: Text(periodLabel(p), style: TextStyle(fontSize: 12, color: selected ? t.colorScheme.primaryForeground : null)),
                  selected: selected,
                  onSelected: (_) {
                    setState(() => _period = p);
                    _reload();
                  },
                  showCheckmark: false,
                  selectedColor: t.colorScheme.primary,
                  backgroundColor: t.colorScheme.card,
                  side: BorderSide(color: t.colorScheme.border),
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

                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: StatTile(
                            label: 'Terkumpul',
                            value: fmtMoney(total),
                            color: t.colorScheme.primary,
                            icon: Icons.savings_outlined,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: StatTile(
                            label: 'Sudah bayar',
                            value: '${paidIds.length}/${d.members.length}',
                            hint: unpaid.isEmpty ? 'Lengkap 🎉' : '${unpaid.length} belum',
                            icon: Icons.check_circle_outline,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (unpaid.isNotEmpty) ...[
                      const SectionTitle('Belum bayar'),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final m in unpaid)
                            ActionChip(
                              label: Text(m.name, style: const TextStyle(fontSize: 12)),
                              onPressed: () async {
                                if (await showPaymentForm(context, period: _period, memberId: m.id)) _reload();
                              },
                              backgroundColor: t.colorScheme.card,
                              side: BorderSide(color: t.colorScheme.border),
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
                          actionLabel: 'Catat iuran',
                          onAction: () async {
                            if (await showPaymentForm(context, period: _period)) _reload();
                          },
                        ),
                      )
                    else
                      for (final p in d.payments)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: t.colorScheme.card,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: t.colorScheme.border),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.check_circle, size: 16, color: t.colorScheme.primary),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(p.memberName, maxLines: 1, overflow: TextOverflow.ellipsis),
                                      Text(
                                        '${fmtDate(p.paidAt)}${p.note != null ? " • ${p.note}" : ""}',
                                        style: t.textTheme.small,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                Text(fmtMoney(p.amount), style: const TextStyle(fontWeight: FontWeight.w600)),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 15),
                                  onPressed: () async {
                                    if (await confirm(context, 'Hapus iuran?', 'Catatan ${p.memberName} dihapus.')) {
                                      await Payment.delete(p.id);
                                      _reload();
                                    }
                                  },
                                ),
                              ],
                            ),
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
