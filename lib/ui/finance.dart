import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/soft.dart';
import '../data/auth.dart';
import '../data/models.dart';
import 'export.dart';
import 'fmt.dart';
import 'login_gate.dart';
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

  /// Sumber yang gagal dimuat; buku kas tetap tampil dari sumber yang berhasil
  /// (mis. hanya iuran, saat tabel `transactions` bermasalah).
  final List<String> failures;

  _FinanceData(this.entries, this.summary, this.byId, this.failures);

  static Future<_FinanceData> load(String? period) async {
    final results = await Future.wait<Soft<Object?>>([
      // Kas dihitung dari kapan uangnya MASUK (`paid_at`), bukan turnamen mana
      // yang dibayar: turnamen bulan lalu bisa dibayar bulan ini. Periode
      // iuran HARUS ikut pemilih periode — sebelumnya selalu bulan berjalan,
      // sehingga saldo "Semua" kehilangan semua iuran bulan-bulan sebelumnya
      // dan saldo bulan lampau tercampur iuran bulan ini.
      soft(
        'Iuran',
        () => period == null
            ? Payment.all()
            : Payment.inMonth(_monthOf(period)),
        fallback: const <Payment>[],
      ),
      soft('Kas', () => Transaction.all(period: period), fallback: const <Transaction>[]),
    ]);
    final failures = settle(results);
    final transactions = results[1].value! as List<Transaction>;
    final entries = mergeCashLedger(
      payments: results[0].value! as List<Payment>,
      transactions: transactions,
    );
    return _FinanceData(
      entries,
      CashSummary.fromEntries(entries),
      {for (final t in transactions) t.id: t},
      failures,
    );
  }

  /// Awal bulan dari periode `YYYY-MM`.
  static DateTime _monthOf(String period) {
    final p = period.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]));
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

  /// Buku kas hanya untuk yang sudah masuk (server menolak tamu), jadi
  /// muatannya dibuat saat ada sesi — lihat catatan di `payments.dart`.
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    Auth.session.addListener(_onAuth);
    _ensureLoaded();
  }

  void _ensureLoaded() {
    if (!Auth.signedIn || _loaded) return;
    _loaded = true;
    _future = _FinanceData.load(_period);
  }

  void _onAuth() {
    if (!mounted) return;
    setState(() {
      _loaded = false;
      _ensureLoaded();
    });
  }

  @override
  void dispose() {
    Auth.session.removeListener(_onAuth);
    super.dispose();
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

  /// Ekspor buku kas yang sedang tampil (periode ikut dipatuhi) sebagai CSV.
  ///
  /// Urutan dibalik jadi kronologis dan saldo berjalan dihitung di sini:
  /// laporan yang dibaca orang luar (Excel/Sheets) harus mulai dari awal
  /// bulan dan berakhir di saldo yang sama dengan yang tampil di app.
  Future<void> _export() async {
    final _FinanceData d;
    try {
      d = await _future;
    } catch (e) {
      if (!mounted) return;
      toast(context, 'Data belum termuat: ${errText(e)}');
      return;
    }
    if (d.entries.isEmpty) {
      if (!mounted) return;
      toast(context, 'Belum ada catatan untuk diekspor');
      return;
    }
    var saldo = 0.0;
    final rows = <List<Object?>>[
      ['Tanggal', 'Jenis', 'Kategori', 'Keterangan', 'Masuk', 'Keluar', 'Saldo'],
    ];
    // Kronologis (terlama dulu) supaya laporan terbaca mulai dari awal
    // periode dan saldo berjalannya berakhir persis di saldo app.
    for (final e in d.entries.reversed) {
      saldo += e.amount;
      rows.add([
        '${e.date.year}-${e.date.month.toString().padLeft(2, '0')}-'
            '${e.date.day.toString().padLeft(2, '0')}',
        e.isIncome ? 'Masuk' : 'Keluar',
        e.label,
        e.detail,
        e.isIncome ? e.amount : null,
        e.isIncome ? null : -e.amount,
        saldo,
      ]);
    }
    if (!mounted) return;
    await showCsvExport(
      context,
      title: 'Ekspor buku kas',
      description: _period == null
          ? 'Semua catatan kas (${rows.length - 1} baris), CSV siap dibuka di Excel/Sheets.'
          : 'Buku kas ${periodLabel(_period!)} (${rows.length - 1} baris), '
              'CSV siap dibuka di Excel/Sheets.',
      filename: 'kas-${_period ?? 'semua'}.csv',
      csv: buildCsv(rows),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!Auth.signedIn) return const LockedMoney(title: 'Kas klub');
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
                    if (d.failures.isNotEmpty)
                      DegradedNotice(failures: d.failures, onRetry: _reload),
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
                      SectionTitle(
                        'Buku kas',
                        action: TextButton.icon(
                          onPressed: _export,
                          icon: const Icon(Icons.ios_share, size: 15),
                          label: const Text('Ekspor'),
                        ),
                      ),
                      // Saat periode "Semua" dipilih, buku kas menyeberangi
                      // beberapa bulan — beri batas bulan supaya saldo tidak
                      // terbaca sebagai satu deret tanpa jeda.
                      for (var i = 0; i < d.entries.length; i++) ...[
                        if (_period == null &&
                            (i == 0 || d.entries[i - 1].date.month != d.entries[i].date.month))
                          _MonthLabel(month: d.entries[i].date),
                        _LedgerRow(
                          entry: d.entries[i],
                          // Baris kas yang lahir dari booking tidak boleh
                          // diedit/dihapus dari sini: nominalnya harus sama
                          // dengan `bookings.cost`, kalau tidak "Total sewa"
                          // dan saldo kas menghitung angka berbeda untuk uang
                          // yang sama (dan mencatat ulang manual = dobel).
                          transaction: _manualTx(d, d.entries[i]),
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

/// Transaksi yang boleh dikoreksi dari buku kas.
///
/// Null untuk iuran (dikelola di halaman Iuran) dan untuk pengeluaran sewa
/// yang lahir dari booking (dikelola lewat booking-nya). Tanpa penyaringan
/// ini, mengubah nominal sewa di Kas memutus tautan `booking_id` sehingga
/// "Total sewa" dan saldo kas menampilkan angka berbeda.
Transaction? _manualTx(_FinanceData d, CashEntry entry) {
  final id = entry.transactionId;
  if (id == null) return null;
  final tx = d.byId[id];
  if (tx == null || tx.managed) return null;
  return tx;
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
              // Nominal selalu amber; arah uang dibaca dari tanda +/− dan
              // ikon panah. Dulu pemasukan hijau dan pengeluaran netral,
              // padahal angka yang sama tampil amber di Beranda.
              color: AppThemes.money(context),
              fontFeatures: AppThemes.tabular,
            ),
          ),
          // Slot aksi selalu disediakan: tanpa ini nominal iuran bergeser ke
          // kanan dan kolom angka tidak lagi rata dengan baris transaksi.
          if (Auth.canWrite) ...[
            const SizedBox(width: 6),
            SizedBox(
              width: 40,
              // `transaction` null untuk iuran DAN sewa booking; keduanya
              // tidak boleh dihapus dari buku kas.
              child: transaction == null
                  ? null
                  : iconAction(context, Icons.delete_outline, () async {
                      if (await confirm(
                        context,
                        'Hapus transaksi?',
                        '${entry.label} ${fmtMoney(entry.amount.abs())} dihapus dari buku kas.',
                      )) {
                        if (!context.mounted) return;
                        if (await attempt(context, () => Transaction.delete(transaction!.id),
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

