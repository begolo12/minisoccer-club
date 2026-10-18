import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../data/models.dart';
import 'fmt.dart';

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
            if (ctx.mounted) toast(ctx, 'Gagal simpan: $e');
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

Future<bool> showMatchForm(BuildContext context) async {
  final opponent = TextEditingController();
  final venue = TextEditingController();
  var date = DateTime.now().add(const Duration(days: 7));
  var time = const TimeOfDay(hour: 20, minute: 0);
  var isHome = true;
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
          if (opponent.text.trim().isEmpty) {
            toast(ctx, 'Nama lawan wajib diisi');
            return;
          }
          setLocal(() => saving = true);
          try {
            await Match.insert(
              opponent: opponent.text.trim(),
              playedAt: DateTime(date.year, date.month, date.day, time.hour, time.minute),
              venue: _nullIfEmpty(venue.text),
              isHome: isHome,
            );
            if (ctx.mounted) Navigator.pop(ctx, true);
          } catch (e) {
            if (ctx.mounted) toast(ctx, 'Gagal simpan: $e');
          } finally {
            if (ctx.mounted) setLocal(() => saving = false);
          }
        }

        return ShadDialog(
          title: const Text('Jadwal tanding'),
          description: const Text('Catat pertandingan yang akan datang.'),
          actions: [
            ShadButton.outline(onPressed: saving ? null : () => Navigator.pop(ctx, false), child: const Text('Batal')),
            ShadButton(onPressed: saving ? null : save, child: const Text('Simpan')),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ShadInput(controller: opponent, placeholder: const Text('Nama lawan'), textCapitalization: TextCapitalization.words),
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
              const SizedBox(height: 14),
              ShadSwitch(
                value: isHome,
                label: Text(isHome ? 'Kandang' : 'Tandang'),
                onChanged: (v) => setLocal(() => isHome = v),
              ),
            ],
          ),
        );
      },
    ),
  );
  return ok ?? false;
}

Future<bool> showFinishMatch(BuildContext context, Match match) async {
  final gf = TextEditingController(text: match.goalsFor.toString());
  final ga = TextEditingController(text: match.goalsAgainst.toString());
  var saving = false;

  final ok = await showShadDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        Future<void> save() async {
          setLocal(() => saving = true);
          try {
            await match.finish(gf: int.tryParse(gf.text) ?? 0, ga: int.tryParse(ga.text) ?? 0);
            if (ctx.mounted) Navigator.pop(ctx, true);
          } catch (e) {
            if (ctx.mounted) toast(ctx, 'Gagal simpan: $e');
          } finally {
            if (ctx.mounted) setLocal(() => saving = false);
          }
        }

        return ShadDialog(
          title: Text('Hasil vs ${match.opponent}'),
          description: const Text('Skor akhir. Statistik W/D/L otomatis terupdate.'),
          actions: [
            ShadButton.outline(onPressed: saving ? null : () => Navigator.pop(ctx, false), child: const Text('Batal')),
            ShadButton(onPressed: saving ? null : save, child: const Text('Simpan hasil')),
          ],
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Text('Kita', style: ShadTheme.of(ctx).textTheme.small),
                    const SizedBox(height: 6),
                    ShadInput(controller: gf, textAlign: TextAlign.center, keyboardType: TextInputType.number),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('—'),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text('Lawan', style: ShadTheme.of(ctx).textTheme.small),
                    const SizedBox(height: 6),
                    ShadInput(controller: ga, textAlign: TextAlign.center, keyboardType: TextInputType.number),
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
  var members = await Member.all();
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
          setLocal(() => saving = true);
          try {
            await Payment.insert(memberId: selected, amount: amt, period: per, note: _nullIfEmpty(note.text));
            if (ctx.mounted) Navigator.pop(ctx, true);
          } catch (e) {
            if (ctx.mounted) toast(ctx, 'Gagal simpan: $e');
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

Future<bool> showTransactionForm(BuildContext context) async {
  final amount = TextEditingController();
  final note = TextEditingController();
  var kind = 'expense';
  var category = Transaction.expenseCategories.keys.first;
  var date = DateTime.now();
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
            await Transaction.insert(
              kind: kind,
              category: category,
              amount: amt,
              occurredAt: date,
              note: _nullIfEmpty(note.text),
            );
            if (ctx.mounted) Navigator.pop(ctx, true);
          } catch (e) {
            if (ctx.mounted) toast(ctx, 'Gagal simpan: $e');
          } finally {
            if (ctx.mounted) setLocal(() => saving = false);
          }
        }

        return ShadDialog(
          title: const Text('Catat transaksi'),
          description: const Text(
            'Pemasukan atau pengeluaran di luar iuran anggota.',
          ),
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
            );
            if (ctx.mounted) Navigator.pop(ctx, true);
          } catch (e) {
            if (ctx.mounted) toast(ctx, 'Gagal simpan: $e');
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
            ],
          ),
        );
      },
    ),
  );
  return ok ?? false;
}

Future<bool> showAnnouncementForm(BuildContext context) async {
  final title = TextEditingController();
  final body = TextEditingController();
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
            await Announcement.insert(title: title.text.trim(), body: body.text.trim());
            if (ctx.mounted) Navigator.pop(ctx, true);
          } catch (e) {
            if (ctx.mounted) toast(ctx, 'Gagal simpan: $e');
          } finally {
            if (ctx.mounted) setLocal(() => saving = false);
          }
        }

        return ShadDialog(
          title: const Text('Pengumuman baru'),
          description: const Text('Info singkat untuk semua anggota.'),
          actions: [
            ShadButton.outline(onPressed: saving ? null : () => Navigator.pop(ctx, false), child: const Text('Batal')),
            ShadButton(onPressed: saving ? null : save, child: const Text('Kirim')),
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
