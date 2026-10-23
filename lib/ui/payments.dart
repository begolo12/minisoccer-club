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

  /// Daftar lengkap yang belum bayar, dengan pencarian.
  ///
  /// Muncul hanya kalau pesertanya banyak: di daftar utama delapan nama
  /// pertama sudah cukup untuk pekerjaan sehari-hari, dan sisanya dibuka di
  /// sini supaya halaman tidak didominasi satu bagian.
  Future<void> _showAllUnpaid(_PayData d) async {
    final selected = d.selected;
    if (selected == null) return;
    await showShadDialog<void>(
      context: context,
      builder: (ctx) => _AllUnpaidDialog(
        rows: d.unpaid,
        entryFee: selected.entryFee,
        canWrite: Auth.canWrite,
        onRecord: (memberId) async {
          Navigator.pop(ctx);
          await _record(d, memberId: memberId);
        },
      ),
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
                  SectionTitle(
                    'Belum bayar',
                    action: unpaid.length > 8
                        ? TextButton(
                            onPressed: () => _showAllUnpaid(d),
                            child: Text('Lihat semua (${unpaid.length})'),
                          )
                        : null,
                  ),
                  // Daftar baris, bukan kumpulan chip. Dengan 13 anggota
                  // menunggak, chip membungkus jadi empat baris yang sulit
                  // dipindai dan tiap chip hanya 32px — di HP itu sering
                  // salah ketuk. Satu baris per orang: nama terbaca, dan
                  // tombol "Catat" selalu di tempat yang sama.
                  for (final r in unpaid.take(8))
                    RowItem(
                      title: r.member.name,
                      subtitle: r.member.position,
                      trailing: Auth.canWrite
                          ? ShadButton.outline(
                              size: ShadButtonSize.sm,
                              onPressed: () => _record(d, memberId: r.member.id),
                              leading: const Icon(Icons.add, size: 14),
                              child: const Text('Catat'),
                            )
                          : Text(
                              selected.entryFee > 0 ? fmtMoney(selected.entryFee) : 'Belum bayar',
                              style: ShadTheme.of(context).textTheme.table.copyWith(
                                    color: AppThemes.bad(context),
                                  ),
                            ),
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



/// Daftar seluruh anggota yang belum bayar, dengan pencarian.
///
/// Dipakai saat peserta turnamen banyak: menampilkan semuanya di halaman
/// utama membuat bagian lain terdorong jauh ke bawah.
class _AllUnpaidDialog extends StatefulWidget {
  const _AllUnpaidDialog({
    required this.rows,
    required this.entryFee,
    required this.canWrite,
    required this.onRecord,
  });

  final List<DuesRow> rows;
  final double entryFee;
  final bool canWrite;
  final Future<void> Function(int memberId) onRecord;

  @override
  State<_AllUnpaidDialog> createState() => _AllUnpaidDialogState();
}

class _AllUnpaidDialogState extends State<_AllUnpaidDialog> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final rows = _query.isEmpty
        ? widget.rows
        : widget.rows.where((r) => r.member.name.toLowerCase().contains(_query)).toList();

    return ShadDialog(
      title: Text('Belum bayar (${widget.rows.length})'),
      description: Text(
        widget.entryFee > 0
            ? 'Iuran ${fmtMoney(widget.entryFee)} per anggota'
            : 'Ketuk "Catat" untuk mencatat pembayaran',
      ),
      actions: [
        ShadButton.outline(
          onPressed: () => Navigator.pop(context),
          child: const Text('Tutup'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.rows.length > 6) ...[
            ShadInput(
              controller: _search,
              placeholder: const Text('Cari nama…'),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              leading: const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.search, size: 16),
              ),
            ),
            const SizedBox(height: 10),
          ],
          // Tinggi dibatasi: dialog yang tumbuh melebihi layar HP membuat
          // tombol tutup tidak terjangkau.
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 380),
            child: Material(
              type: MaterialType.transparency,
              child: rows.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text('Tidak ada nama yang cocok.', style: t.textTheme.muted),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final r in rows)
                          RowItem(
                            title: r.member.name,
                            subtitle: r.member.position,
                            trailing: widget.canWrite
                                ? ShadButton.outline(
                                    size: ShadButtonSize.sm,
                                    onPressed: () => widget.onRecord(r.member.id),
                                    leading: const Icon(Icons.add, size: 14),
                                    child: const Text('Catat'),
                                  )
                                : null,
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
