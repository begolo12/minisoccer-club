import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../data/models.dart';
import 'fmt.dart';
import 'widgets.dart';

/// Kumpulan form (bottom-sheet style dialog) yang dipakai lintas halaman.
/// Return true kalau ada perubahan data.

Future<bool> showMemberForm(BuildContext context, {Member? member}) async {
  final name = TextEditingController(text: member?.name ?? '');
  final phone = TextEditingController(text: member?.phone ?? '');
  final jersey = TextEditingController(text: member?.jersey?.toString() ?? '');
  var position = member?.position ?? 'Bebas';
  var active = member?.active ?? true;
  var saving = false;

  final ok = await showShadDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        Future<void> save() async {
          if (name.text.trim().isEmpty) {
            toast(ctx, 'Nama tidak boleh kosong');
            return;
          }
          setLocal(() => saving = true);
          try {
            if (member == null) {
              await Member.insert(
                name: name.text.trim(),
                phone: _nullIfEmpty(phone.text),
                position: position,
                jersey: int.tryParse(jersey.text),
              );
            } else {
              await member.update(
                name: name.text.trim(),
                phone: _nullIfEmpty(phone.text),
                position: position,
                jersey: int.tryParse(jersey.text),
                active: active,
              );
            }
            if (ctx.mounted) Navigator.pop(ctx, true);
          } catch (e) {
            if (ctx.mounted) toast(ctx, 'Gagal simpan: ${errText(e)}');
          } finally {
            if (ctx.mounted) setLocal(() => saving = false);
          }
        }

        return ShadDialog(
          title: Text(member == null ? 'Tambah anggota' : 'Edit anggota'),
          description: Text(member == null
              ? 'Isi data pemain. Bisa dilengkapi nanti.'
              : 'Perbarui data pemain.'),
          actions: [
            ShadButton.outline(onPressed: saving ? null : () => Navigator.pop(ctx, false), child: const Text('Batal')),
            ShadButton(
              onPressed: saving ? null : save,
              child: saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Simpan'),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ShadInput(controller: name, placeholder: const Text('Nama lengkap'), textCapitalization: TextCapitalization.words),
              const SizedBox(height: 10),
              ShadInput(controller: phone, placeholder: const Text('No. HP (opsional)'), keyboardType: TextInputType.phone),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ShadSelect<String>(
                      placeholder: const Text('Posisi'),
                      initialValue: position,
                      options: const ['Kiper', 'Bek', 'Gelandang', 'Penyerang', 'Bebas']
                          .map((p) => ShadOption(value: p, child: Text(p)))
                          .toList(),
                      selectedOptionBuilder: (c, v) => Text(v),
                      onChanged: (v) => setLocal(() => position = v ?? 'Bebas'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 96,
                    child: ShadInput(controller: jersey, placeholder: const Text('No.'), keyboardType: TextInputType.number),
                  ),
                ],
              ),
              if (member != null) ...[
                const SizedBox(height: 14),
                ShadSwitch(
                  value: active,
                  label: const Text('Anggota aktif'),
                  onChanged: (v) => setLocal(() => active = v),
                ),
              ],
            ],
          ),
        );
      },
    ),
  );
  return ok ?? false;
}

/// Form jadwal laga. [match] terisi = mengubah jadwal yang ada; tanpa itu
/// form membuat laga baru.
Future<bool> showMatchForm(BuildContext context, {Match? match}) async {
  final teams = await Team.all();
  if (!context.mounted) return false;
  if (teams.length < 2) {
    toast(context, 'Buat minimal 2 tim dulu di menu Tim');
    return false;
  }
  final editing = match != null;
  var homeId = match?.homeTeamId ?? teams.first.id;
  var awayId = match?.awayTeamId ?? teams[1].id;
  // Tim yang sudah dihapus tidak ada di daftar; jatuh ke dua tim pertama
  // supaya dropdown tidak kosong.
  if (!teams.any((t) => t.id == homeId)) homeId = teams.first.id;
  if (!teams.any((t) => t.id == awayId)) awayId = teams[1].id;
  final venue = TextEditingController(text: match?.venue ?? '');
  final when = match?.playedAt ?? DateTime.now().add(const Duration(days: 7));
  var date = DateTime(when.year, when.month, when.day);
  var time = TimeOfDay(hour: when.hour, minute: when.minute);
  var saving = false;

  final ok = await showShadDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        Future<void> pickDate() async {
          final d = await showDatePicker(
            context: ctx,
            initialDate: date,
            firstDate: DateTime.now().subtract(const Duration(days: 365)),
            lastDate: DateTime.now().add(const Duration(days: 730)),
          );
          if (d != null) setLocal(() => date = d);
        }

        Future<void> pickTime() async {
          final t = await showTimePicker(context: ctx, initialTime: time);
          if (t != null) setLocal(() => time = t);
        }

        Future<void> save() async {
          if (homeId == awayId) {
            toast(ctx, 'Pilih dua tim yang berbeda');
            return;
          }
          setLocal(() => saving = true);
          try {
            final at = DateTime(date.year, date.month, date.day, time.hour, time.minute);
            if (editing) {
              await match.update(
                homeTeamId: homeId,
                awayTeamId: awayId,
                playedAt: at,
                venue: _nullIfEmpty(venue.text),
              );
            } else {
              await Match.insert(
                homeTeamId: homeId,
                awayTeamId: awayId,
                playedAt: at,
                venue: _nullIfEmpty(venue.text),
              );
            }
            if (ctx.mounted) Navigator.pop(ctx, true);
          } catch (e) {
            if (ctx.mounted) toast(ctx, 'Gagal simpan: ${errText(e)}');
          } finally {
            if (ctx.mounted) setLocal(() => saving = false);
          }
        }

        return ShadDialog(
          title: Text(editing ? 'Ubah jadwal' : 'Jadwal tanding'),
          description: Text(editing
              ? 'Ganti tanggal, lokasi, atau tim. Hasil yang sudah dikunci tidak '
                  'bisa dipindah ke tim lain.'
              : 'Pilih dua tim klub yang akan bertemu.'),
          actions: [
            ShadButton.outline(onPressed: saving ? null : () => Navigator.pop(ctx, false), child: const Text('Batal')),
            ShadButton(onPressed: saving ? null : save, child: const Text('Simpan')),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: ShadSelect<int>(
                      placeholder: const Text('Tim 1'),
                      initialValue: homeId,
                      options: teams.map((t) => ShadOption(value: t.id, child: Text(t.name))).toList(),
                      selectedOptionBuilder: (c, v) =>
                          Text(teams.firstWhere((t) => t.id == v).name),
                      onChanged: (v) => setLocal(() => homeId = v ?? homeId),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('vs'),
                  ),
                  Expanded(
                    child: ShadSelect<int>(
                      placeholder: const Text('Tim 2'),
                      initialValue: awayId,
                      options: teams.map((t) => ShadOption(value: t.id, child: Text(t.name))).toList(),
                      selectedOptionBuilder: (c, v) =>
                          Text(teams.firstWhere((t) => t.id == v).name),
                      onChanged: (v) => setLocal(() => awayId = v ?? awayId),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ShadInput(controller: venue, placeholder: const Text('Lokasi (opsional)')),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ShadButton.outline(
                      onPressed: pickDate,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.calendar_today_outlined, size: 15),
                          const SizedBox(width: 8),
                          Flexible(child: Text(fmtDate(date), overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ShadButton.outline(
                    onPressed: pickTime,
                    child: Row(
                      children: [
                        const Icon(Icons.schedule, size: 15),
                        const SizedBox(width: 8),
                        Text('${time.hour.toString().padLeft(2, '0')}.${time.minute.toString().padLeft(2, '0')}'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );
  return ok ?? false;
}

/// Selesaikan laga: skor diisi lewat stepper, bukan keyboard angka. Satu
/// ketukan "Selesai pertandingan" mengunci hasil, dan klasemen langsung
/// memakai poinnya (menang 3, seri 1, kalah 0).
///
/// Kalau laga sudah punya sesi, skor tidak bisa diubah di sini: jumlah sesi
/// adalah hasil yang sah, dan dua sumber skor yang berbeda akan saling
/// menimpa begitu sesi berikutnya disimpan.
Future<bool> showFinishMatch(BuildContext context, Match match) async {
  final sessions = await MatchSession.forMatch(match.id);
  if (!context.mounted) return false;
  final fromSessions = sessions.isNotEmpty;
  var home = fromSessions ? sessions.fold<int>(0, (s, e) => s + e.scoreHome) : match.goalsFor;
  var away = fromSessions ? sessions.fold<int>(0, (s, e) => s + e.scoreAway) : match.goalsAgainst;
  var saving = false;
  // Ketukan pertama pada 0–0 hanya memunculkan peringatan; ketukan kedua yang
  // menyimpan. Laga yang belum dimainkan hampir tidak pernah berakhir 0–0.
  var confirmZero = false;

  final ok = await showShadDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        Future<void> save() async {
          if (!match.ongoing && !match.finished && home == 0 && away == 0 && !confirmZero) {
            setLocal(() => confirmZero = true);
            return;
          }
          setLocal(() => saving = true);
          try {
            await match.finish(gf: home, ga: away);
            if (ctx.mounted) Navigator.pop(ctx, true);
          } catch (e) {
            if (ctx.mounted) toast(ctx, 'Gagal simpan: ${errText(e)}');
          } finally {
            if (ctx.mounted) setLocal(() => saving = false);
          }
        }

        final t = ShadTheme.of(ctx);
        return ShadDialog(
          title: Text('${match.homeName} vs ${match.awayName}'),
          description: Text(fromSessions
              ? 'Skor mengikuti ${sessions.length} sesi. Ubah rinciannya di daftar sesi.'
              : 'Atur skor akhir, lalu selesaikan pertandingan.'),
          actions: [
            if (match.finished)
              ShadButton.ghost(
                onPressed: saving
                    ? null
                    : () async {
                        setLocal(() => saving = true);
                        try {
                          await match.reopen();
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } catch (e) {
                          if (ctx.mounted) {
                            setLocal(() => saving = false);
                            toast(ctx, 'Gagal membuka lagi: $e');
                          }
                        }
                      },
                child: const Text('Buka lagi'),
              ),
            ShadButton.outline(
              onPressed: saving ? null : () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            ShadButton(
              onPressed: saving ? null : save,
              leading: const Icon(Icons.check, size: 16),
              child: Text(
                confirmZero
                    ? 'Yakin 0–0?'
                    : (match.finished ? 'Simpan koreksi' : 'Selesai pertandingan'),
              ),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (fromSessions)
                Panel(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${match.homeName} $home–$away ${match.awayName}',
                          maxLines: 2,
                          style: t.textTheme.large.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        '${sessions.length} sesi',
                        style: t.textTheme.small,
                      ),
                    ],
                  ),
                )
              else ...[
                ScoreStepper(
                  name: match.homeName,
                  value: home,
                  onChanged: saving
                      ? null
                      : (v) => setLocal(() {
                            home = v;
                            confirmZero = false;
                          }),
                ),
                const SizedBox(height: 8),
                ScoreStepper(
                  name: match.awayName,
                  value: away,
                  onChanged: saving
                      ? null
                      : (v) => setLocal(() {
                            away = v;
                            confirmZero = false;
                          }),
                ),
              ],
              if (confirmZero) ...[
                const SizedBox(height: 10),
                Text(
                  'Laga ini belum berjalan. Tekan sekali lagi untuk mencatat '
                  'hasil 0–0 sebagai seri.',
                  textAlign: TextAlign.center,
                  style: t.textTheme.small.copyWith(color: t.colorScheme.destructive),
                ),
              ],
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: t.colorScheme.muted.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Text(
                      scoreOutcome(match.homeName, match.awayName, home, away),
                      textAlign: TextAlign.center,
                      style: t.textTheme.large.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Menang 3 poin · seri 1 poin · kalah 0',
                      textAlign: TextAlign.center,
                      style: t.textTheme.small,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
  return ok ?? false;
}

Future<bool> showPaymentForm(BuildContext context, {String? period, int? memberId}) async {
  // Hanya anggota aktif: iuran anggota nonaktif tidak masuk label "Lunas"
  // di halaman Iuran, jadi mencatatnya di sini menghasilkan data yatim.
  final members = await Member.all(activeOnly: true);
  if (!context.mounted) return false;
  if (members.isEmpty) {
    toast(context, 'Tambah anggota dulu');
    return false;
  }
  // Isi awal memakai nominal yang paling sering dibayar, bukan angka mati.
  double? standard;
  try {
    standard = await Payment.standardAmount();
  } catch (_) {
    standard = null;
  }
  if (!context.mounted) return false;
  final amount = TextEditingController(text: standard == null ? '' : fmtNumber(standard));
  final note = TextEditingController();
  var selected = memberId ?? members.first.id;
  var per = period ?? periodNow();
  var saving = false;

  final ok = await showShadDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        Future<void> save() async {
          final amt = double.tryParse(amount.text.replaceAll('.', '').replaceAll(',', '.')) ?? 0;
          if (amt <= 0) {
            toast(ctx, 'Nominal harus lebih dari 0');
            return;
          }
          if (await Payment.existsFor(selected, per)) {
            final name = members.firstWhere((m) => m.id == selected).name;
            if (ctx.mounted) {
              toast(ctx, 'Iuran $name untuk ${periodLabel(per)} sudah tercatat');
            }
            return;
          }
          setLocal(() => saving = true);
          try {
            await Payment.insert(memberId: selected, amount: amt, period: per, note: _nullIfEmpty(note.text));
            if (ctx.mounted) Navigator.pop(ctx, true);
          } catch (e) {
            if (ctx.mounted) toast(ctx, 'Gagal simpan: ${errText(e)}');
          } finally {
            if (ctx.mounted) setLocal(() => saving = false);
          }
        }

        final periods = List.generate(6, (i) {
          final d = DateTime(DateTime.now().year, DateTime.now().month - i);
          return '${d.year}-${d.month.toString().padLeft(2, '0')}';
        });

        return ShadDialog(
          title: const Text('Catat iuran'),
          description: Text('Periode ${periodLabel(per)}'),
          actions: [
            ShadButton.outline(onPressed: saving ? null : () => Navigator.pop(ctx, false), child: const Text('Batal')),
            ShadButton(onPressed: saving ? null : save, child: const Text('Simpan')),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ShadSelect<int>(
                placeholder: const Text('Anggota'),
                initialValue: selected,
                options: members.map((m) => ShadOption(value: m.id, child: Text(m.name))).toList(),
                selectedOptionBuilder: (c, v) => Text(members.firstWhere((m) => m.id == v).name),
                onChanged: (v) => setLocal(() => selected = v ?? selected),
              ),
              const SizedBox(height: 10),
              ShadInput(controller: amount, placeholder: const Text('Nominal, misal 100000'), keyboardType: TextInputType.number),
              const SizedBox(height: 10),
              ShadSelect<String>(
                placeholder: const Text('Periode'),
                initialValue: per,
                options: periods.map((p) => ShadOption(value: p, child: Text(periodLabel(p)))).toList(),
                selectedOptionBuilder: (c, v) => Text(periodLabel(v)),
                onChanged: (v) => setLocal(() => per = v ?? per),
              ),
              const SizedBox(height: 10),
              ShadInput(controller: note, placeholder: const Text('Catatan (opsional)')),
            ],
          ),
        );
      },
    ),
  );
  return ok ?? false;
}

/// Form transaksi kas. [transaction] terisi = mengoreksi catatan yang ada.
Future<bool> showTransactionForm(
  BuildContext context, {
  Transaction? transaction,
}) async {
  final editing = transaction != null;
  final amount = TextEditingController(
    text: transaction == null ? '' : fmtNumber(transaction.amount),
  );
  final note = TextEditingController(text: transaction?.note ?? '');
  var kind = transaction?.kind ?? 'expense';
  var category = transaction?.category ?? Transaction.expenseCategories.keys.first;
  var date = transaction?.occurredAt ?? DateTime.now();
  var saving = false;

  final ok = await showShadDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final categories = Transaction.categoriesFor(kind);

        Future<void> save() async {
          final amt =
              double.tryParse(
                amount.text.replaceAll('.', '').replaceAll(',', '.'),
              ) ??
              0;
          if (amt <= 0) {
            toast(ctx, 'Nominal harus lebih dari 0');
            return;
          }
          setLocal(() => saving = true);
          try {
            if (editing) {
              await transaction.update(
                kind: kind,
                category: category,
                amount: amt,
                occurredAt: date,
                note: _nullIfEmpty(note.text),
              );
            } else {
              await Transaction.insert(
                kind: kind,
                category: category,
                amount: amt,
                occurredAt: date,
                note: _nullIfEmpty(note.text),
              );
            }
            if (ctx.mounted) Navigator.pop(ctx, true);
          } catch (e) {
            if (ctx.mounted) toast(ctx, 'Gagal simpan: ${errText(e)}');
          } finally {
            if (ctx.mounted) setLocal(() => saving = false);
          }
        }

        return ShadDialog(
          title: Text(editing ? 'Koreksi transaksi' : 'Catat transaksi'),
          description: Text(editing
              ? 'Ubah nominal, kategori, atau tanggal catatan ini.'
              : 'Pemasukan atau pengeluaran di luar iuran anggota.'),
          actions: [
            ShadButton.outline(
              onPressed: saving ? null : () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            ShadButton(
              onPressed: saving ? null : save,
              child: const Text('Simpan'),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ShadSelect<String>(
                placeholder: const Text('Jenis'),
                initialValue: kind,
                options: const [
                  ShadOption(value: 'income', child: Text('Pemasukan')),
                  ShadOption(value: 'expense', child: Text('Pengeluaran')),
                ],
                selectedOptionBuilder: (c, v) =>
                    Text(v == 'income' ? 'Pemasukan' : 'Pengeluaran'),
                onChanged: (v) => setLocal(() {
                  kind = v ?? 'expense';
                  category = Transaction.categoriesFor(kind).keys.first;
                }),
              ),
              const SizedBox(height: 10),
              ShadSelect<String>(
                key: ValueKey(kind),
                placeholder: const Text('Kategori'),
                initialValue: category,
                options: categories.entries
                    .map((e) => ShadOption(value: e.key, child: Text(e.value)))
                    .toList(),
                selectedOptionBuilder: (c, v) => Text(categories[v] ?? v),
                onChanged: (v) => setLocal(() => category = v ?? category),
              ),
              const SizedBox(height: 10),
              ShadInput(
                controller: amount,
                placeholder: const Text('Nominal, misal 350000'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ShadButton.outline(
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: date,
                          firstDate: DateTime.now().subtract(
                            const Duration(days: 365),
                          ),
                          lastDate: DateTime.now().add(
                            const Duration(days: 30),
                          ),
                        );
                        if (d != null) setLocal(() => date = d);
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.calendar_today_outlined, size: 15),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              fmtDate(date),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ShadInput(
                controller: note,
                placeholder: const Text('Catatan (opsional)'),
              ),
            ],
          ),
        );
      },
    ),
  );
  return ok ?? false;
}

Future<bool> showBookingForm(BuildContext context) async {
  final title = TextEditingController(text: 'Sewa lapangan');
  final cost = TextEditingController();
  var date = DateTime.now().add(const Duration(days: 1));
  var time = const TimeOfDay(hour: 20, minute: 0);
  var duration = 90;
  // Biaya sewa adalah uang keluar; default-nya ikut dicatat ke kas supaya
  // saldo di Kas klub tidak berbeda dengan "Total sewa" di halaman ini.
  var postToCash = true;
  var saving = false;

  final ok = await showShadDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        Future<void> save() async {
          setLocal(() => saving = true);
          try {
            await Booking.insert(
              title: title.text.trim().isEmpty ? 'Sewa lapangan' : title.text.trim(),
              startsAt: DateTime(date.year, date.month, date.day, time.hour, time.minute),
              durationMin: duration,
              cost: double.tryParse(cost.text.replaceAll('.', '')) ?? 0,
              postToCash: postToCash,
            );
            if (ctx.mounted) Navigator.pop(ctx, true);
          } catch (e) {
            if (ctx.mounted) toast(ctx, 'Gagal simpan: ${errText(e)}');
          } finally {
            if (ctx.mounted) setLocal(() => saving = false);
          }
        }

        return ShadDialog(
          title: const Text('Booking lapangan'),
          description: const Text('Catat jadwal sewa biar nggak bentrok.'),
          actions: [
            ShadButton.outline(onPressed: saving ? null : () => Navigator.pop(ctx, false), child: const Text('Batal')),
            ShadButton(onPressed: saving ? null : save, child: const Text('Simpan')),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ShadInput(controller: title, placeholder: const Text('Judul, misal Sewa lapangan A')),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ShadButton.outline(
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: date,
                          firstDate: DateTime.now().subtract(const Duration(days: 30)),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (d != null) setLocal(() => date = d);
                      },
                      child: Text(fmtDate(date)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ShadButton.outline(
                    onPressed: () async {
                      final t = await showTimePicker(context: ctx, initialTime: time);
                      if (t != null) setLocal(() => time = t);
                    },
                    child: Text('${time.hour.toString().padLeft(2, '0')}.${time.minute.toString().padLeft(2, '0')}'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ShadSelect<int>(
                placeholder: const Text('Durasi'),
                initialValue: duration,
                options: const [60, 90, 120, 150]
                    .map((d) => ShadOption(value: d, child: Text('$d menit')))
                    .toList(),
                selectedOptionBuilder: (c, v) => Text('$v menit'),
                onChanged: (v) => setLocal(() => duration = v ?? duration),
              ),
              const SizedBox(height: 10),
              ShadInput(controller: cost, placeholder: const Text('Biaya (opsional)'), keyboardType: TextInputType.number),
              const SizedBox(height: 12),
              ShadCheckbox(
                value: postToCash,
                label: const Text('Catat biaya ini ke kas'),
                onChanged: saving ? null : (v) => setLocal(() => postToCash = v),
              ),
            ],
          ),
        );
      },
    ),
  );
  return ok ?? false;
}

/// Form pengumuman. [announcement] terisi = mengubah yang sudah terbit.
Future<bool> showAnnouncementForm(
  BuildContext context, {
  Announcement? announcement,
}) async {
  final editing = announcement != null;
  final title = TextEditingController(text: announcement?.title ?? '');
  final body = TextEditingController(text: announcement?.body ?? '');
  var saving = false;

  final ok = await showShadDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        Future<void> save() async {
          if (title.text.trim().isEmpty || body.text.trim().isEmpty) {
            toast(ctx, 'Judul & isi wajib diisi');
            return;
          }
          setLocal(() => saving = true);
          try {
            if (editing) {
              await announcement.update(
                title: title.text.trim(),
                body: body.text.trim(),
              );
            } else {
              await Announcement.insert(title: title.text.trim(), body: body.text.trim());
            }
            if (ctx.mounted) Navigator.pop(ctx, true);
          } catch (e) {
            if (ctx.mounted) toast(ctx, 'Gagal simpan: ${errText(e)}');
          } finally {
            if (ctx.mounted) setLocal(() => saving = false);
          }
        }

        return ShadDialog(
          title: Text(editing ? 'Ubah pengumuman' : 'Pengumuman baru'),
          description: Text(editing
              ? 'Perbaiki teksnya. Tanggal terbit tidak berubah.'
              : 'Info singkat untuk semua anggota.'),
          actions: [
            ShadButton.outline(onPressed: saving ? null : () => Navigator.pop(ctx, false), child: const Text('Batal')),
            ShadButton(
              onPressed: saving ? null : save,
              child: Text(editing ? 'Simpan' : 'Kirim'),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ShadInput(controller: title, placeholder: const Text('Judul'), textCapitalization: TextCapitalization.sentences),
              const SizedBox(height: 10),
              ShadInput(controller: body, placeholder: const Text('Isi pengumuman'), maxLines: 4, minLines: 4),
            ],
          ),
        );
      },
    ),
  );
  return ok ?? false;
}

String? _nullIfEmpty(String s) => s.trim().isEmpty ? null : s.trim();
