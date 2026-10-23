import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../data/models.dart';
import 'fmt.dart';
import 'money_input.dart';
import 'widgets.dart';

/// Kumpulan form (bottom-sheet style dialog) yang dipakai lintas halaman.
/// Return true kalau ada perubahan data.

Future<bool> showMemberForm(BuildContext context, {Member? member}) async {
  final name = TextEditingController(text: member?.name ?? '');
  final phone = TextEditingController(text: member?.phone ?? '');
  final address = TextEditingController(text: member?.address ?? '');
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
                address: _nullIfEmpty(address.text),
                position: position,
                jersey: int.tryParse(jersey.text),
              );
            } else {
              await member.update(
                name: name.text.trim(),
                phone: _nullIfEmpty(phone.text),
                address: _nullIfEmpty(address.text),
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
              ShadInput(controller: name, placeholder: const Text('Nama lengkap'), autofocus: true, textCapitalization: TextCapitalization.words, textInputAction: TextInputAction.next),
              const SizedBox(height: 10),
              ShadInput(controller: phone, placeholder: const Text('No. HP (opsional)'), keyboardType: TextInputType.phone),
              const SizedBox(height: 10),
              ShadInput(controller: address, placeholder: const Text('Alamat (opsional)'), textCapitalization: TextCapitalization.words),
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
  // Await sebelum dialog bisa gagal (jaringan/server). Tanpa try/catch,
  // exception naik ke pemanggil dan tombol "Jadwal" tampak tidak bereaksi
  // sama sekali — tanpa pesan apa pun.
  final List<Team> teams;
  try {
    teams = await Team.all();
  } catch (e) {
    if (context.mounted) toast(context, 'Gagal memuat tim: ${errText(e)}');
    return false;
  }
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
            SaveButton(saving: saving, onPressed: save),
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
              ShadInput(controller: venue, placeholder: const Text('Lokasi (opsional)'), textInputAction: TextInputAction.done),
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
  // Rincian sesi dipakai untuk mengisi angka awal dialog. Saat OFFLINE bacaan
  // ini bisa gagal (sesi belum pernah dibuka di perangkat), dan dulu dialognya
  // tidak terbuka sama sekali — padahal menyelesaikan laga justru dilakukan di
  // lapangan tanpa sinyal. Kalau gagal, angka awal diambil dari laga itu
  // sendiri dan dialognya tetap terbuka.
  var sessions = const <MatchSession>[];
  try {
    sessions = await MatchSession.forMatch(match.id);
  } catch (_) {
    sessions = const <MatchSession>[];
  }
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
                            toast(ctx, 'Gagal membuka lagi: ${errText(e)}');
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

/// Form catat iuran untuk satu turnamen.
///
/// Iuran terikat turnamen, jadi pilihannya bukan bulan melainkan anggota yang
/// ikut turnamen itu (anggota dari tim yang terdaftar). Nominal awal diambil
/// dari `tournaments.entry_fee`, supaya bendahara tidak mengetik ulang angka
/// yang sama untuk setiap anggota.
Future<bool> showPaymentForm(
  BuildContext context, {
  required int tournamentId,
  int? memberId,
  double entryFee = 0,
}) async {
  // Peserta turnamen = anggota dari tim yang terdaftar. Kalau daftar peserta
  // kosong (tim belum diisi pemain), jatuh ke semua anggota aktif supaya
  // pencatatan tetap mungkin dilakukan.
  var failed = false;
  List<DuesRow> bill;
  try {
    bill = await Payment.bill(tournamentId);
  } catch (_) {
    bill = const [];
    failed = true;
  }
  if (!context.mounted) return false;

  List<Member> candidates = bill.map((r) => r.member).toList();
  if (candidates.isEmpty) {
    try {
      candidates = await Member.all(activeOnly: true);
      failed = false;
    } catch (_) {
      candidates = const [];
      failed = true;
    }
  }
  if (!context.mounted) return false;
  if (candidates.isEmpty) {
    // Bedakan "memang belum ada anggota" dari "tidak bisa dimuat": menuduh
    // pengguna belum menambah anggota padahal daftarnya cuma tidak terbaca
    // saat offline membuatnya menambah data yang sudah ada.
    toast(
      context,
      failed
          ? 'Daftar anggota belum tersimpan di perangkat. Buka halaman Anggota sekali saat online.'
          : 'Tambahkan anggota dulu',
    );
    return false;
  }

  // Nominal awal: nominal turnamen, atau yang paling sering dibayar, atau kosong.
  var initial = entryFee;
  if (initial <= 0) {
    try {
      initial = await Payment.usualAmountFor(tournamentId) ?? 0;
    } catch (_) {
      initial = 0;
    }
  }
  if (!context.mounted) return false;

  final amount = TextEditingController(
    text: initial > 0 ? fmtNumber(initial) : '',
  );
  final note = TextEditingController();
  var selected = memberId ?? candidates.first.id;
  var saving = false;

  final ok = await showShadDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        Future<void> save() async {
          // `saving` diset SEBELUM await apa pun: dua ketukan cepat pada
          // Simpan bisa menjalankan dua alur simpan dan menghasilkan iuran
          // ganda.
          setLocal(() => saving = true);
          final amt = parseFormattedMoney(amount.text);
          if (amt <= 0) {
            setLocal(() => saving = false);
            toast(ctx, 'Nominal harus diisi angka lebih dari 0');
            return;
          }
          try {
            // Cek duplikat hanya kalau server terjangkau.
            //
            // Dulu panggilan ini tanpa penjagaan: saat OFFLINE ia melempar
            // "Tidak bisa menghubungi server", ditangkap catch di bawah, dan
            // dialog menampilkan "Gagal simpan" — pencatatan iuran gagal total
            // padahal seharusnya masuk antrean. Kalau tidak bisa memeriksa,
            // penyimpanan diteruskan; index unik (member_id, tournament_id) di
            // database tetap menjadi penjaga terakhir saat sinkron.
            var duplicate = false;
            try {
              duplicate = await Payment.existsFor(selected, tournamentId);
            } catch (_) {
              duplicate = false;
            }
            if (duplicate) {
              if (ctx.mounted) {
                final name = candidates.firstWhere((m) => m.id == selected).name;
                toast(ctx, 'Iuran $name untuk turnamen ini sudah tercatat');
              }
              return;
            }
            await Payment.insert(
              memberId: selected,
              amount: amt,
              tournamentId: tournamentId,
              note: _nullIfEmpty(note.text),
            );
            if (ctx.mounted) Navigator.pop(ctx, true);
          } catch (e) {
            if (ctx.mounted) toast(ctx, 'Gagal simpan: ${errText(e)}');
          } finally {
            if (ctx.mounted) setLocal(() => saving = false);
          }
        }

        return ShadDialog(
          title: const Text('Catat iuran'),
          description: const Text('Iuran untuk turnamen ini'),
          actions: [
            ShadButton.outline(onPressed: saving ? null : () => Navigator.pop(ctx, false), child: const Text('Batal')),
            SaveButton(saving: saving, onPressed: save),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ShadSelect<int>(
                placeholder: const Text('Anggota'),
                initialValue: selected,
                options: candidates.map((m) => ShadOption(value: m.id, child: Text(m.name))).toList(),
                selectedOptionBuilder: (c, v) =>
                    Text(candidates.firstWhere((m) => m.id == v).name),
                onChanged: (v) => setLocal(() => selected = v ?? selected),
              ),
              const SizedBox(height: 10),
              MoneyField(
                controller: amount,
                autofocus: true,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 10),
              ShadInput(controller: note, placeholder: const Text('Catatan (opsional)'), textInputAction: TextInputAction.done),
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
          // `saving` diset lebih dulu supaya dua ketukan cepat tidak
          // menyimpan dua baris kas.
          setLocal(() => saving = true);
          final amt = parseFormattedMoney(amount.text);
          if (amt <= 0) {
            setLocal(() => saving = false);
            toast(ctx, 'Nominal harus diisi angka lebih dari 0');
            return;
          }
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
            SaveButton(saving: saving, onPressed: save),
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
              MoneyField(
                controller: amount,
                autofocus: true,
                textInputAction: TextInputAction.done,
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
          // Biaya sewa: kosong = 0 (boleh, sewa bisa gratis), tapi angka yang
          // tidak terbaca atau negatif harus ditolak. Sebelumnya nilai negatif
          // tersimpan apa adanya dan input tak terbaca jadi 0 diam-diam.
          final raw = cost.text.trim();
          final parsed = parseFormattedMoney(raw);
          if (parsed < 0) {
            setLocal(() => saving = false);
            toast(ctx, 'Biaya harus angka 0 atau lebih');
            return;
          }
          final start = DateTime(date.year, date.month, date.day, time.hour, time.minute);

          // Form ini menjanjikan "biar nggak bentrok", jadi bentroknya harus
          // diperiksa. Tanpa ini dua sewa di jam yang sama tetap tersimpan —
          // justru masalah yang ingin dicegah.
          try {
            final clashes = await Booking.overlapping(
              startsAt: start,
              durationMin: duration,
            );
            if (clashes.isNotEmpty) {
              if (!ctx.mounted) return;
              final first = clashes.first;
              final firstEnd = first.startsAt.add(Duration(minutes: first.durationMin));
              final ok = await confirm(
                ctx,
                'Jadwal bertabrakan',
                'Sudah ada "${first.title}" pada ${fmtTime(first.startsAt)}–'
                    '${fmtTime(firstEnd)}. Tetap simpan?',
                confirmLabel: 'Tetap simpan',
              );
              if (!ok) {
                if (ctx.mounted) setLocal(() => saving = false);
                return;
              }
            }
          } catch (_) {
            // Gagal memeriksa (mis. offline) tidak boleh memblokir pencatatan:
            // jadwal yang tidak tercatat lebih berbahaya daripada jadwal yang
            // mungkin bertabrakan.
          }

          try {
            await Booking.insert(
              title: title.text.trim().isEmpty ? 'Sewa lapangan' : title.text.trim(),
              startsAt: start,
              durationMin: duration,
              cost: parsed,
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
          title: const Text('Sewa lapangan'),
          description: const Text('Catat jadwal sewa biar nggak bentrok.'),
          actions: [
            ShadButton.outline(onPressed: saving ? null : () => Navigator.pop(ctx, false), child: const Text('Batal')),
            SaveButton(saving: saving, onPressed: save),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ShadInput(controller: title, placeholder: const Text('Judul, misal Sewa lapangan A'), autofocus: true, textInputAction: TextInputAction.next),
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
              MoneyField(
                controller: cost,
                placeholder: const Text('Biaya (opsional)'),
              ),
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
            // Label seragam "Simpan": "Kirim" menyiratkan data dikirim ke
            // orang lain, padahal hanya disimpan di klub.
            SaveButton(saving: saving, onPressed: save),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ShadInput(controller: title, placeholder: const Text('Judul'), autofocus: true, textCapitalization: TextCapitalization.sentences, textInputAction: TextInputAction.next),
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
