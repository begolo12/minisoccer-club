import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/soft.dart';
import '../data/auth.dart';
import '../data/models.dart';
import 'fmt.dart';
import 'forms.dart';
import 'theme.dart';
import 'widgets.dart';

/// Data halaman Iuran: turnamen yang bisa dipilih, tagihan turnamen terpilih,
/// dan riwayat pembayarannya.
///
/// Iuran ditarik **per turnamen**, bukan per bulan: tim yang ikut tiap turnamen
/// berbeda, jadi yang ditagih adalah anggota dari tim yang terdaftar di
/// turnamen itu.
class _PayData {
  final List<Tournament> tournaments;
  final Tournament? selected;
  final List<DuesRow> bill;
  final List<Payment> payments;
  final List<String> failures;

  _PayData({
    required this.tournaments,
    required this.selected,
    required this.bill,
    required this.payments,
    required this.failures,
  });

  double get collected => payments.fold<double>(0, (s, p) => s + p.amount);

  List<DuesRow> get unpaid => bill.where((r) => !r.paid).toList();
  int get paidCount => bill.where((r) => r.paid).length;

  /// Perkiraan uang yang belum masuk: nominal turnamen × jumlah yang belum bayar.
  double get missing => (selected?.entryFee ?? 0) * unpaid.length;

  static Future<_PayData> load(int? tournamentId) async {
    final r = await Future.wait<Soft<Object?>>([
      soft('Turnamen', Tournament.all, fallback: const <Tournament>[]),
    ]);
    final failures = settle(r);
    final tournaments = r[0].value! as List<Tournament>;

    // Turnamen terpilih: yang diminta kalau masih ada, kalau tidak yang paling
    // relevan — berjalan dulu, lalu yang akan datang.
    Tournament? selected;
    for (final t in tournaments) {
      if (t.id == tournamentId) selected = t;
    }
    selected ??= tournaments.isEmpty ? null : tournaments.first;

    var bill = const <DuesRow>[];
    var payments = const <Payment>[];
    if (selected != null) {
      final r2 = await Future.wait<Soft<Object?>>([
        soft('Tagihan', () => Payment.bill(selected!.id), fallback: const <DuesRow>[]),
        soft('Riwayat iuran', () => Payment.all(tournamentId: selected!.id),
            fallback: const <Payment>[]),
      ]);
      failures.addAll(settle(r2));
      bill = r2[0].value! as List<DuesRow>;
      payments = r2[1].value! as List<Payment>;
    }

    return _PayData(
      tournaments: tournaments,
      selected: selected,
      bill: bill,
      payments: payments,
      failures: failures,
    );
  }
}

class PaymentsPage extends StatefulWidget {
  const PaymentsPage({super.key});

  @override
  State<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends State<PaymentsPage> {
  int? _tournamentId;
  late Future<_PayData> _future;

  @override
  void initState() {
    super.initState();
    _future = _PayData.load(_tournamentId);
  }

  Future<void> _reload() async {
    final f = _PayData.load(_tournamentId);
    setState(() => _future = f);
    await f;
  }

  Future<void> _record(_PayData d, {int? memberId}) async {
    final t = d.selected;
    if (t == null) return;
    final saved = await showPaymentForm(
      context,
      tournamentId: t.id,
      memberId: memberId,
      entryFee: t.entryFee,
    );
    if (saved) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Iuran',
      subtitle: 'Per turnamen',
      actions: [
        if (Auth.canWrite)
          FutureBuilder<_PayData>(
            future: _future,
            builder: (context, snap) => iconAction(
              context,
              Icons.add,
              () {
                final d = snap.data;
                // Tombol tetap aktif: menonaktifkannya tanpa alasan membuat
                // pengguna bingung. Ketuk → beri tahu langkah berikutnya.
                if (d?.selected == null) {
                  toast(context, 'Buat turnamen dulu — iuran ditarik per turnamen');
                  return;
                }
                _record(d!);
              },
              tooltip: 'Catat iuran',
            ),
          ),
      ],
      child: AsyncView<_PayData>(
        future: _future,
        onRefresh: _reload,
        builder: (d) => d.tournaments.isEmpty ? _noTournaments(d) : _content(d),
      ),
    );
  }

  /// Belum ada turnamen = belum ada yang bisa ditagih. Arahkan ke langkah
  /// berikutnya, jangan tampilkan halaman kosong tanpa penjelasan.
  Widget _noTournaments(_PayData d) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      children: [
        if (d.failures.isNotEmpty) DegradedNotice(failures: d.failures, onRetry: _reload),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: EmptyState(
            icon: Icons.emoji_events_outlined,
            title: 'Belum ada turnamen',
            message: 'Iuran ditarik per turnamen. Buat turnamen dulu, lalu catat '
                'iuran anggota yang ikut.',
            actionLabel: null,
          ),
        ),
      ],
    );
  }

  Widget _content(_PayData d) {
    final t = ShadTheme.of(context);
    final selected = d.selected!;
    final unpaid = d.unpaid;

    return Column(
      children: [
        _TournamentChips(
          tournaments: d.tournaments,
          selectedId: selected.id,
          onChanged: (id) {
            setState(() => _tournamentId = id);
            _reload();
          },
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
            children: [
              if (d.failures.isNotEmpty) DegradedNotice(failures: d.failures, onRetry: _reload),
              StatStrip(
                children: [
                  StatTile(
                    label: 'Terkumpul',
                    value: fmtMoney(d.collected),
                    color: AppThemes.money(context),
                  ),
                  StatTile(
                    label: 'Lunas',
                    value: '${d.paidCount}/${d.bill.length}',
                    hint: d.bill.isEmpty
                        ? 'belum ada peserta'
                        : (unpaid.isEmpty ? 'semua lunas' : '${unpaid.length} belum'),
                    color: d.bill.isNotEmpty && unpaid.isEmpty
                        ? t.colorScheme.primary
                        : null,
                  ),
                  if (d.missing > 0)
                    StatTile(
                      label: 'Kurang',
                      value: fmtMoney(d.missing),
                      hint: '${unpaid.length} anggota',
                      color: AppThemes.bad(context),
                    ),
                ],
              ),
              if (selected.entryFee > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Iuran ${fmtMoney(selected.entryFee)} per anggota',
                    style: t.textTheme.small,
                  ),
                ),

              // Peserta = anggota dari tim yang ikut turnamen ini. Kalau timnya
              // belum diisi pemain, tidak ada yang bisa ditagih — jelaskan.
              if (d.bill.isEmpty) ...[
                const SizedBox(height: 12),
                EmptyState(
                  icon: Icons.group_outlined,
                  title: 'Belum ada peserta',
                  message: 'Tambahkan tim ke turnamen ini dan isi pemainnya. '
                      'Anggota dari tim itulah yang muncul di daftar iuran.',
                  actionLabel: null,
                ),
              ] else ...[
                if (unpaid.isNotEmpty) ...[
                  const SectionTitle('Belum bayar'),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final r in unpaid)
                        _UnpaidChip(
                          name: r.member.name,
                          onTap: Auth.canWrite ? () => _record(d, memberId: r.member.id) : null,
                        ),
                    ],
                  ),
                ],
                const SectionTitle('Riwayat pembayaran'),
                if (d.payments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      'Belum ada pembayaran untuk ${selected.name}.',
                      style: t.textTheme.small,
                    ),
                  )
                else
                  for (final p in d.payments)
                    RowItem(
                      leading: Icon(Icons.check_circle, size: 15, color: t.colorScheme.primary),
                      title: p.memberName,
                      subtitle:
                          '${fmtDate(p.paidAt)}${p.note != null ? " • ${p.note}" : ""}',
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
                              final name = p.memberName;
                              final title = selected.name;
                              final ok = await confirm(context, 'Hapus iuran?',
                                  'Catatan $name untuk $title dihapus.');
                              if (!ok) return;
                              // `context` di sini milik State, jadi penjaganya
                              // `mounted` (bukan `context.mounted`).
                              if (!mounted) return;
                              if (await attempt(context, () => Payment.delete(p.id),
                                  fail: 'Gagal menghapus')) {
                                _reload();
                              }
                            }, tooltip: 'Hapus'),
                          ],
                        ],
                      ),
                    ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Pemilih turnamen. Menggantikan pemilih bulan: iuran terikat turnamen, dan
/// tiap turnamen punya daftar peserta sendiri.
class _TournamentChips extends StatelessWidget {
  const _TournamentChips({
    required this.tournaments,
    required this.selectedId,
    required this.onChanged,
  });

  final List<Tournament> tournaments;
  final int selectedId;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: tournaments.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final item = tournaments[i];
          final active = item.id == selectedId;
          return GestureDetector(
            onTap: () => onChanged(item.id),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: active ? t.colorScheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: active ? t.colorScheme.primary : t.colorScheme.border,
                ),
              ),
              child: Text(
                item.name,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  color: active ? t.colorScheme.primaryForeground : t.colorScheme.foreground,
                ),
              ),
            ),
          );
        },
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
