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

  /// Transaksi manual menurut id, untuk membuka form koreksi dari baris buku
  /// kas. `CashEntry` hanya menyimpan id-nya.
  final Map<int, Transaction> byId;

  _FinanceData(this.entries, this.summary, this.byId);

  static Future<_FinanceData> load(String? period) async {
    final results = await Future.wait([
      Payment.all(period: period),
      Transaction.all(period: period),
    ]);
    final transactions = results[1] as List<Transaction>;
    final entries = mergeCashLedger(
      payments: results[0] as List<Payment>,
      transactions: transactions,
    );
    return _FinanceData(
      entries,
      CashSummary.fromEntries(entries),
      {for (final t in transactions) t.id: t},
    );
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

  String _periodName(String? p) => p == null ? 'Semua' : periodLabel(p);

  Future<void> _add() async {
    if (!Auth.canWrite) return;
    if (await showTransactionForm(context)) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Kas klub',
      subtitle: _periodName(_period),
      actions: [
        if (Auth.canWrite)
          iconAction(context, Icons.add, _add, tooltip: 'Catat transaksi'),
      ],
      child: Column(
        children: [
          PeriodChips(
            periods: recentPeriods(),
            selected: _period,
            all: true,
            onChanged: (p) {
              setState(() => _period = p);
              _reload();
            },
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
                    StatStrip(
                      children: [
                        StatTile(
                          label: 'Masuk',
                          value: fmtMoney(s.income),
                          hint: s.dues > 0
                              ? 'iuran ${fmtShortMoney(s.dues)}'
                              : 'tanpa iuran',
                        ),
                        StatTile(
                          label: 'Keluar',
                          value: fmtMoney(s.expense),
                          hint: '$expenses catatan',
                        ),
                        StatTile(
                          label: 'Saldo',
                          value: fmtMoney(s.balance),
                          hint: s.balance < 0 ? 'defisit' : 'tersedia',
                          color: s.balance < 0
                              ? AppThemes.bad(context)
                              : AppThemes.money(context),
                        ),
                      ],
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
                      // Saat periode "Semua" dipilih, buku kas menyeberangi
                      // beberapa bulan — beri batas bulan supaya saldo tidak
                      // terbaca sebagai satu deret tanpa jeda.
                      for (var i = 0; i < d.entries.length; i++) ...[
                        if (_period == null &&
                            (i == 0 || d.entries[i - 1].date.month != d.entries[i].date.month))
                          _MonthLabel(month: d.entries[i].date),
                        _LedgerRow(
                          entry: d.entries[i],
                          transaction: d.entries[i].transactionId == null
                              ? null
                              : d.byId[d.entries[i].transactionId],
                          onChanged: _reload,
                        ),
                      ],
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
}

/// Pemisah bulan di buku kas "Semua": label kecil, bukan judul bagian —
/// jangan bersaing dengan "BUKU KAS" di atasnya.
class _MonthLabel extends StatelessWidget {
  const _MonthLabel({required this.month});

  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final label = periodLabel(
      '${month.year}-${month.month.toString().padLeft(2, '0')}',
    );
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 2),
      child: Text(label.toUpperCase(), style: t.textTheme.h4.copyWith(fontSize: 11)),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({
    required this.entry,
    required this.onChanged,
    this.transaction,
  });

  final CashEntry entry;
  final Future<void> Function() onChanged;

  /// Terisi hanya untuk transaksi manual (bukan iuran, bukan sewa booking).
  final Transaction? transaction;

  /// Transaksi kadang memakai judul yang sama dengan keterangannya
  /// ("Sewa lapangan" + "Sewa lapangan latihan rutin"); jangan diulang.
  String _subtitle(CashEntry e) {
    final detail = e.detail.trim();
    if (detail.isEmpty) return fmtDate(e.date);
    final dupe = detail.toLowerCase() == e.label.trim().toLowerCase();
    return dupe ? fmtDate(e.date) : '${fmtDate(e.date)} • $detail';
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final income = entry.isIncome;
    final amount = income
        ? '+${fmtMoney(entry.amount)}'
        : '-${fmtMoney(-entry.amount)}';
    return RowItem(
      // Ketuk baris untuk mengoreksi nominal/kategori/tanggal. Iuran dan
      // sewa lapangan tidak bisa diedit di sini: iuran dikelola di halaman
      // Iuran, sewa mengikuti booking-nya.
      onTap: transaction == null
          ? null
          : () async {
              if (await showTransactionForm(context, transaction: transaction)) {
                await onChanged();
              }
            },
      leading: Icon(
        entry.dues
            ? Icons.check_circle_outline
            : (income ? Icons.south_west : Icons.north_east),
        size: 16,
        color: income ? t.colorScheme.primary : t.colorScheme.mutedForeground,
      ),
      title: entry.dues ? 'Iuran' : entry.label,
      subtitle: _subtitle(entry),
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
          // Slot aksi selalu disediakan: tanpa ini nominal iuran bergeser ke
          // kanan dan kolom angka tidak lagi rata dengan baris transaksi.
          if (Auth.canWrite) ...[
            const SizedBox(width: 6),
            SizedBox(
              width: 34,
              child: entry.transactionId == null
                  ? null
                  : iconAction(context, Icons.delete_outline, () async {
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
            ),
          ],
        ],
      ),
    );
  }
}

