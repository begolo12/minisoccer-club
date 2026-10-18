import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../data/auth.dart';
import '../data/models.dart';
import 'fmt.dart';
import 'forms.dart';
import 'theme.dart';
import 'widgets.dart';

/// Buku kas klub: iuran anggota + pemasukan/pengeluaran lain.
///
/// Iuran tetap disimpan per anggota di tabel `payments`; halaman ini
/// menggabungkannya dengan `transactions` supaya saldo klub terlihat utuh.
class _FinanceData {
  final List<CashEntry> entries;
  final CashSummary summary;

  _FinanceData(this.entries, this.summary);

  static Future<_FinanceData> load(String? period) async {
    final results = await Future.wait([
      Payment.all(period: period),
      Transaction.all(period: period),
    ]);
    final entries = mergeCashLedger(
      payments: results[0] as List<Payment>,
      transactions: results[1] as List<Transaction>,
    );
    return _FinanceData(entries, CashSummary.fromEntries(entries));
  }
}

class FinancePage extends StatefulWidget {
  const FinancePage({super.key});

  @override
  State<FinancePage> createState() => _FinancePageState();
}

class _FinancePageState extends State<FinancePage> {
  String? _period = periodNow();
  late Future<_FinanceData> _future;

  @override
  void initState() {
    super.initState();
    _future = _FinanceData.load(_period);
  }

  Future<void> _reload() async {
    final f = _FinanceData.load(_period);
    setState(() => _future = f);
    await f;
  }

  List<String?> get _periods => [null, for (var i = 0; i < 6; i++) _month(i)];

  String _month(int monthsAgo) {
    final d = DateTime(DateTime.now().year, DateTime.now().month - monthsAgo);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}';
  }

  String _periodName(String? p) => p == null ? 'Semua' : periodLabel(p);

  Future<void> _add() async {
    if (!Auth.canWrite) return;
    if (await showTransactionForm(context)) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return PageScaffold(
      title: 'Kas klub',
      subtitle: _periodName(_period),
      actions: [
        if (Auth.canWrite)
          iconAction(context, Icons.add, _add, tooltip: 'Catat transaksi'),
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
                return _PeriodChip(
                  label: _periodName(p),
                  selected: p == _period,
                  onTap: () {
                    setState(() => _period = p);
                    _reload();
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: AsyncView<_FinanceData>(
              future: _future,
              onRefresh: _reload,
              builder: (d) {
                final s = d.summary;
                final expenses = d.entries.where((e) => !e.isIncome).length;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
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
                              label: 'Masuk',
                              value: fmtMoney(s.income),
                              hint: 'iuran ${fmtNumber(s.dues)}',
                            ),
                          ),
                          _divider(t),
                          Expanded(
                            flex: 3,
                            child: StatTile(
                              label: 'Keluar',
                              value: fmtMoney(s.expense),
                              hint: '$expenses catatan',
                            ),
                          ),
                          _divider(t),
                          Expanded(
                            flex: 3,
                            child: StatTile(
                              label: 'Saldo',
                              value: fmtMoney(s.balance),
                              hint: s.balance < 0 ? 'defisit' : 'tersedia',
                              color: s.balance < 0
                                  ? AppThemes.bad(context)
                                  : AppThemes.money(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (d.entries.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: EmptyState(
                          icon: Icons.account_balance_wallet_outlined,
                          title: 'Belum ada catatan kas',
                          message: _period == null
                              ? 'Iuran dan transaksi akan tampil di sini.'
                              : 'Catat pemasukan atau pengeluaran untuk ${periodLabel(_period!)}.',
                          actionLabel: Auth.canWrite ? 'Catat transaksi' : null,
                          onAction: Auth.canWrite ? _add : null,
                        ),
                      )
                    else ...[
                      const SectionTitle('Buku kas'),
                      for (final e in d.entries)
                        _LedgerRow(entry: e, onChanged: _reload),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider(ShadThemeData t) => Container(
    width: 1,
    height: 44,
    margin: const EdgeInsets.symmetric(horizontal: 10),
    color: t.colorScheme.border,
  );
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return Material(
      color: selected ? t.colorScheme.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
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
            label,
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
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.entry, required this.onChanged});

  final CashEntry entry;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final income = entry.isIncome;
    final amount = income
        ? '+${fmtMoney(entry.amount)}'
        : '-${fmtMoney(-entry.amount)}';
    return RowItem(
      leading: Icon(
        entry.dues
            ? Icons.check_circle_outline
            : (income ? Icons.south_west : Icons.north_east),
        size: 16,
        color: income ? t.colorScheme.primary : t.colorScheme.mutedForeground,
      ),
      title: entry.dues ? 'Iuran' : entry.label,
      subtitle:
          '${fmtDate(entry.date)}${entry.detail.isEmpty ? '' : ' • ${entry.detail}'}',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            amount,
            style: t.textTheme.table.copyWith(
              fontWeight: FontWeight.w600,
              color: income ? t.colorScheme.primary : t.colorScheme.foreground,
              fontFeatures: AppThemes.tabular,
            ),
          ),
          if (entry.transactionId != null && Auth.canWrite) ...[
            const SizedBox(width: 6),
            iconAction(context, Icons.delete_outline, () async {
              if (await confirm(
                context,
                'Hapus transaksi?',
                '${entry.label} ${fmtMoney(entry.amount.abs())} dihapus dari buku kas.',
              )) {
                if (!context.mounted) return;
                if (await attempt(context, () => Transaction.delete(entry.transactionId!),
                    fail: 'Gagal menghapus')) {
                  await onChanged();
                }
              }
            }, tooltip: 'Hapus'),
          ],
        ],
      ),
    );
  }
}
