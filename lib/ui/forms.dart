import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../data/models.dart';
import 'fmt.dart';
import 'money_input.dart';
import 'teams.dart';
import 'theme.dart';
import 'widgets.dart';

/// Kumpulan form (bottom-sheet style dialog) yang dipakai lintas halaman.
/// Return true kalau ada perubahan data.

/// Tanggal dijepit ke rentang picker. Dulu `initialDate` = tanggal data —
/// mengedit catatan lebih tua dari rentang picker membuat picker melewati
/// assert debug (dan di rilis terbuka di bulan yang salah).
DateTime clampPickerDate(DateTime d, DateTime first, DateTime last) =>
    d.isBefore(first) ? first : (d.isAfter(last) ? last : d);

Future<bool> showMemberForm(BuildContext context, {Member? member}) async {
  final name = TextEditingController(text: member?.name ?? '');
  final phone = TextEditingController(text: member?.phone ?? '');
  final address = TextEditingController(text: member?.address ?? '');
  final jersey = TextEditingController(text: member?.jersey?.toString() ?? '');
  var position = member?.position ?? 'Bebas';
  var active = member?.active ?? true;
  var saving = false;
  // Error ditampilkan di bawah kolomnya sendiri, bukan hanya lewat toast:
  // toast hilang sendiri sementara kolom yang salah tetap harus dicari.
  String? nameError;
  String? jerseyError;

  final ok = await showShadDialog<bool>(
    context: context,
    // Dialog tulis tidak bisa ditutup dari luar: ketukan barrier/back di
    // tengah simpan menutup dialog tanpa hasil, toast gagalnya terbuang
    // (guard `ctx.mounted`), dan pengguna mengetik ulang — data bisa ganda.
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        Future<void> save() async {
          final jerseyRaw = jersey.text.trim();
          final jerseyValue = int.tryParse(jerseyRaw);
          final missingName = name.text.trim().isEmpty;
          // Nomor punggung 0–99: nomor di luar itu tidak dipakai di sepak
          // bola, dan lebih sering berasal dari salah ketik.
          final badJersey = jerseyRaw.isNotEmpty &&
              (jerseyValue == null || jerseyValue < 0 || jerseyValue > 99);
          setLocal(() {
            nameError = missingName ? 'Nama tidak boleh kosong' : null;
            jerseyError = badJersey ? 'Nomor punggung harus 0–99' : null;
          });
          if (missingName || badJersey) return;
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
            if (ctx.mounted) toast(ctx, writeFailText(e, fail: 'Gagal simpan'));
          } finally {
            if (ctx.mounted) setLocal(() => saving = false);
          }
        }

        return _WriteDialog(ShadDialog(
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
              FieldLabel('Nama lengkap', required: true),
              Semantics(
                // Error diumumkan dari field-nya: pembaca layar yang fokus ke
                // isian ini langsung mendengar apa yang kurang, tanpa mencari
                // teks error terpisah di bawahnya.
                label: nameError == null ? 'Nama lengkap' : 'Nama lengkap, $nameError',
                child: ShadInput(
                  controller: name,
                  placeholder: const Text('mis. Budi Santoso'),
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setLocal(() => nameError = null),
                ),
              ),
              if (nameError != null) _ErrorText(nameError!),
              const SizedBox(height: 12),
              FieldLabel('Nomor HP'),
              ShadInput(
                controller: phone,
                placeholder: const Text('081234567890'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              FieldLabel('Alamat'),
              ShadInput(
                controller: address,
                placeholder: const Text('Alamat tinggal'),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Placeholder saja tidak cukup untuk pembaca layar:
                        // setelah dipilih, kontrol hanya mengumumkan nilainya
                        // ("Bek") tanpa nama fieldnya.
                        FieldLabel('Posisi'),
                        Semantics(
                          label: 'Posisi bermain',
                          child: ShadSelect<String>(
                            placeholder: const Text('Pilih posisi'),
                            initialValue: position,
                            options: const ['Kiper', 'Bek', 'Gelandang', 'Penyerang', 'Bebas']
                                .map((p) => ShadOption(value: p, child: Text(p)))
                                .toList(),
                            selectedOptionBuilder: (c, v) => Text(v),
                            onChanged: (v) => setLocal(() => position = v ?? 'Bebas'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 96,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FieldLabel('No. punggung'),
                        Semantics(
                          label: jerseyError == null
                              ? 'Nomor punggung'
                              : 'Nomor punggung, $jerseyError',
                          child: ShadInput(
                            controller: jersey,
                            placeholder: const Text('No.'),
                            keyboardType: TextInputType.number,
                            // Hanya angka, dan dibatasi 2 digit: menempel "-5"
                            // atau "9999" tidak boleh tersimpan apa adanya.
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(2),
                            ],
                            onChanged: (_) => setLocal(() => jerseyError = null),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (jerseyError != null) _ErrorText(jerseyError!),
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
        ), [name, phone, address, jersey]);
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
    // Dialog dengan tombol, bukan toast: klub baru berhenti tepat di sini, dan
    // toast hilang sendiri tanpa jalan keluar.
    final go = await showShadDialog<bool>(
      context: context,
      builder: (ctx) => ShadDialog(
        title: const Text('Butuh minimal 2 tim'),
        description: Text(
          'Laga mempertemukan dua tim, jadi butuh minimal dua tim. '
          'Saat ini klub punya ${teams.length} tim.',
        ),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Nanti'),
          ),
          ShadButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Buat tim'),
          ),
        ],
      ),
    );
    if (go == true && context.mounted) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const TeamsPage()));
    }
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
  String? teamError;

  final ok = await showShadDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        Future<void> pickDate() async {
          final first = DateTime.now().subtract(const Duration(days: 365));
          final last = DateTime.now().add(const Duration(days: 730));
          final d = await showDatePicker(
            context: ctx,
            initialDate: clampPickerDate(date, first, last),
            firstDate: first,
            lastDate: last,
          );
          if (d != null) setLocal(() => date = d);
        }

        Future<void> pickTime() async {
          final t = await showTimePicker(context: ctx, initialTime: time);
          if (t != null) setLocal(() => time = t);
        }

        Future<void> save() async {
          if (homeId == awayId) {
            setLocal(() => teamError = 'Pilih dua tim yang berbeda');
            return;
          }
          setLocal(() {
            teamError = null;
            saving = true;
          });
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
            if (ctx.mounted) toast(ctx, writeFailText(e, fail: 'Gagal simpan'));
          } finally {
            if (ctx.mounted) setLocal(() => saving = false);
          }
        }

        return _WriteDialog(ShadDialog(
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
              FieldLabel('Tim yang bertanding', required: true),
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      label: teamError == null ? 'Tim pertama' : 'Tim pertama, $teamError',
                      child: ShadSelect<int>(
                        placeholder: const Text('Tim 1'),
                        initialValue: homeId,
                        options: teams.map((t) => ShadOption(value: t.id, child: Text(t.name))).toList(),
                        selectedOptionBuilder: (c, v) =>
                            Text(teams.firstWhere((t) => t.id == v).name),
                        onChanged: (v) => setLocal(() {
                          homeId = v ?? homeId;
                          teamError = null;
                        }),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('lawan'),
                  ),
                  Expanded(
                    child: Semantics(
                      label: 'Tim kedua',
                      child: ShadSelect<int>(
                        placeholder: const Text('Tim 2'),
                        initialValue: awayId,
                        options: teams.map((t) => ShadOption(value: t.id, child: Text(t.name))).toList(),
                        selectedOptionBuilder: (c, v) =>
                            Text(teams.firstWhere((t) => t.id == v).name),
                        onChanged: (v) => setLocal(() {
                          awayId = v ?? awayId;
                          teamError = null;
                        }),
                      ),
                    ),
                  ),
                ],
              ),
              if (teamError != null) _ErrorText(teamError!),
              const SizedBox(height: 12),
              FieldLabel('Lokasi'),
              ShadInput(
                controller: venue,
                placeholder: const Text('Lokasi (opsional)'),
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 12),
              FieldLabel('Jadwal'),
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
        ), [venue]);
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
    barrierDismissible: false,
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
            if (ctx.mounted) toast(ctx, writeFailText(e, fail: 'Gagal simpan'));
          } finally {
            if (ctx.mounted) setLocal(() => saving = false);
          }
        }

        final t = ShadTheme.of(ctx);
        return _WriteDialog(ShadDialog(
          title: Text('${match.homeName} lawan ${match.awayName}'),
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
        ));
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

  // Peserta = anggota dari tim yang ikut turnamen. Dulu, kalau daftar itu
  // kosong, form diam-diam jatuh ke SEMUA anggota aktif. Akibatnya uang bisa
  // tercatat untuk orang yang tidak ikut: "Terkumpul" bertambah, sedangkan
  // "Belum bayar" tetap kosong — terlihat seperti data hilang.
  final candidates = bill.map((r) => r.member).toList();
  if (!context.mounted) return false;
  if (candidates.isEmpty) {
    toast(
      context,
      failed
          ? 'Daftar peserta belum tersimpan di perangkat. Buka halaman Iuran sekali saat online.'
          : 'Belum ada peserta: tim di turnamen ini belum punya pemain. '
              'Isi pemain tiap tim dulu di halaman turnamen.',
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
  String? amountError;

  final ok = await showShadDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        Future<void> save() async {
          // `saving` diset SEBELUM await apa pun: dua ketukan cepat pada
          // Simpan bisa menjalankan dua alur simpan dan menghasilkan iuran
          // ganda.
          setLocal(() => saving = true);
          final amt = parseFormattedMoney(amount.text);
          if (amt <= 0) {
            setLocal(() {
              saving = false;
              amountError = 'Nominal harus diisi angka lebih dari 0';
            });
            return;
          }
          setLocal(() => amountError = null);
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
            if (ctx.mounted) toast(ctx, writeFailText(e, fail: 'Gagal simpan'));
          } finally {
            if (ctx.mounted) setLocal(() => saving = false);
          }
        }

        return _WriteDialog(ShadDialog(
          title: const Text('Catat iuran'),
          description: const Text('Iuran untuk turnamen ini'),
          actions: [
            ShadButton.outline(onPressed: saving ? null : () => Navigator.pop(ctx, false), child: const Text('Batal')),
            SaveButton(saving: saving, onPressed: save),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FieldLabel('Anggota yang membayar', required: true),
              Semantics(
                label: 'Anggota yang membayar',
                child: ShadSelect<int>(
                  placeholder: const Text('Anggota'),
                  initialValue: selected,
                  options: candidates.map((m) => ShadOption(value: m.id, child: Text(m.name))).toList(),
                  selectedOptionBuilder: (c, v) =>
                      Text(candidates.firstWhere((m) => m.id == v).name),
                  onChanged: (v) => setLocal(() => selected = v ?? selected),
                ),
              ),
              const SizedBox(height: 12),
              FieldLabel('Nominal iuran', required: true),
              Semantics(
                label: amountError == null ? 'Nominal iuran' : 'Nominal iuran, $amountError',
                child: MoneyField(
                  controller: amount,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                ),
              ),
              if (amountError != null) _ErrorText(amountError!),
              const SizedBox(height: 12),
              FieldLabel('Catatan'),
              ShadInput(
                controller: note,
                placeholder: const Text('Catatan (opsional)'),
                textInputAction: TextInputAction.done,
              ),
            ],
          ),
        ), [amount, note]);
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
  String? amountError;

  final ok = await showShadDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final categories = Transaction.categoriesFor(kind);

        Future<void> save() async {
          // `saving` diset lebih dulu supaya dua ketukan cepat tidak
          // menyimpan dua baris kas.
          setLocal(() => saving = true);
          final amt = parseFormattedMoney(amount.text);
          if (amt <= 0) {
            setLocal(() {
              saving = false;
              amountError = 'Nominal harus diisi angka lebih dari 0';
            });
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
            if (ctx.mounted) toast(ctx, writeFailText(e, fail: 'Gagal simpan'));
          } finally {
            if (ctx.mounted) setLocal(() => saving = false);
          }
        }

        return _WriteDialog(ShadDialog(
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
              FieldLabel('Jenis', required: true),
              Semantics(
                label: 'Jenis transaksi',
                child: ShadSelect<String>(
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
              ),
              const SizedBox(height: 12),
              FieldLabel('Kategori', required: true),
              Semantics(
                label: 'Kategori',
                child: ShadSelect<String>(
                  key: ValueKey(kind),
                  placeholder: const Text('Kategori'),
                  initialValue: category,
                  options: categories.entries
                      .map((e) => ShadOption(value: e.key, child: Text(e.value)))
                      .toList(),
                  selectedOptionBuilder: (c, v) => Text(categories[v] ?? v),
                  onChanged: (v) => setLocal(() => category = v ?? category),
                ),
              ),
              const SizedBox(height: 12),
              FieldLabel('Nominal', required: true),
              Semantics(
                label: amountError == null ? 'Nominal transaksi' : 'Nominal transaksi, $amountError',
                child: MoneyField(
                  controller: amount,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                ),
              ),
              if (amountError != null) _ErrorText(amountError!),
              const SizedBox(height: 12),
              FieldLabel('Tanggal'),
              Row(
                children: [
                  Expanded(
                    child: ShadButton.outline(
                      onPressed: () async {
                        final first = DateTime.now().subtract(const Duration(days: 365));
                        final last = DateTime.now().add(const Duration(days: 30));
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: clampPickerDate(date, first, last),
                          firstDate: first,
                          lastDate: last,
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
              const SizedBox(height: 12),
              FieldLabel('Catatan'),
              ShadInput(
                controller: note,
                placeholder: const Text('Catatan (opsional)'),
              ),
            ],
          ),
        ), [amount, note]);
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
  String? costError;

  final ok = await showShadDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        Future<void> save() async {
          setLocal(() => saving = true);
          // Biaya sewa: kosong = 0 (boleh, sewa bisa gratis), tapi angka yang
          // tidak terbaca atau negatif harus ditolak. Sebelumnya nilai negatif
          // tersimpan apa adanya dan input tak terbaca jadi 0 diam-diam —
          // sewa tercatat gratis padahal nominalnya ada.
          final raw = cost.text.trim();
          final parsed = parseFormattedMoney(raw);
          final unreadable = raw.isNotEmpty && !RegExp(r'[0-9]').hasMatch(raw);
          if (unreadable || parsed < 0) {
            setLocal(() {
              saving = false;
              costError = unreadable
                  ? 'Biaya harus angka, misal 150.000'
                  : 'Biaya harus angka 0 atau lebih';
            });
            return;
          }
          setLocal(() => costError = null);
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
            if (!ctx.mounted) return;
            if (e is BookingPartialException) {
              // Parsial: booking SUDAH masuk. Form ditutup supaya Simpan
              // tidak ditekan lagi — pengulangan berarti dua sewa untuk satu
              // lapangan. Sisa pekerjaannya (catatan kas) dijelaskan pesan.
              toast(ctx, e.message);
              Navigator.pop(ctx, true);
              return;
            }
            toast(ctx, writeFailText(e, fail: 'Gagal simpan'));
          } finally {
            if (ctx.mounted) setLocal(() => saving = false);
          }
        }

        return _WriteDialog(ShadDialog(
          title: const Text('Sewa lapangan'),
          description: const Text('Catat jadwal sewa biar nggak bentrok.'),
          actions: [
            ShadButton.outline(onPressed: saving ? null : () => Navigator.pop(ctx, false), child: const Text('Batal')),
            SaveButton(saving: saving, onPressed: save),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FieldLabel('Judul', required: true),
              ShadInput(controller: title, placeholder: const Text('Judul, misal Sewa lapangan A'), autofocus: true, textInputAction: TextInputAction.next),
              const SizedBox(height: 12),
              FieldLabel('Tanggal & jam'),
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
              const SizedBox(height: 12),
              FieldLabel('Durasi'),
              Semantics(
                label: 'Durasi sewa',
                child: ShadSelect<int>(
                  placeholder: const Text('Durasi'),
                  initialValue: duration,
                  options: const [60, 90, 120, 150]
                      .map((d) => ShadOption(value: d, child: Text('$d menit')))
                      .toList(),
                  selectedOptionBuilder: (c, v) => Text('$v menit'),
                  onChanged: (v) => setLocal(() => duration = v ?? duration),
                ),
              ),
              const SizedBox(height: 12),
              FieldLabel('Biaya'),
              Semantics(
                label: costError == null ? 'Biaya sewa' : 'Biaya sewa, $costError',
                child: MoneyField(
                  controller: cost,
                  placeholder: const Text('Biaya (opsional)'),
                ),
              ),
              if (costError != null) _ErrorText(costError!),
              const SizedBox(height: 12),
              ShadCheckbox(
                value: postToCash,
                label: const Text('Catat biaya ini ke kas'),
                onChanged: saving ? null : (v) => setLocal(() => postToCash = v),
              ),
            ],
          ),
        ), [title, cost]);
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
  String? titleError;
  String? bodyError;

  final ok = await showShadDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        Future<void> save() async {
          final missingTitle = title.text.trim().isEmpty;
          final missingBody = body.text.trim().isEmpty;
          setLocal(() {
            titleError = missingTitle ? 'Judul wajib diisi' : null;
            bodyError = missingBody ? 'Isi pengumuman wajib diisi' : null;
          });
          if (missingTitle || missingBody) return;
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
            if (ctx.mounted) toast(ctx, writeFailText(e, fail: 'Gagal simpan'));
          } finally {
            if (ctx.mounted) setLocal(() => saving = false);
          }
        }

        return _WriteDialog(ShadDialog(
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
              FieldLabel('Judul', required: true),
              Semantics(
                label: titleError == null ? 'Judul pengumuman' : 'Judul pengumuman, $titleError',
                child: ShadInput(
                  controller: title,
                  placeholder: const Text('Judul'),
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setLocal(() => titleError = null),
                ),
              ),
              if (titleError != null) _ErrorText(titleError!),
              const SizedBox(height: 12),
              FieldLabel('Isi pengumuman', required: true),
              Semantics(
                label: bodyError == null ? 'Isi pengumuman' : 'Isi pengumuman, $bodyError',
                child: ShadInput(
                  controller: body,
                  placeholder: const Text('Isi pengumuman'),
                  maxLines: 4,
                  minLines: 4,
                  onChanged: (_) => setLocal(() => bodyError = null),
                ),
              ),
              if (bodyError != null) _ErrorText(bodyError!),
            ],
          ),
        ), [title, body]);
      },
    ),
  );
  return ok ?? false;
}

String? _nullIfEmpty(String s) => s.trim().isEmpty ? null : s.trim();

/// Dialog isian yang tidak bisa ditutup lewat Back atau ketukan di luar.
///
/// Barrier yang bisa diketuk membuang isian yang sedang diketik — pada form
/// anggota itu berarti nama, HP, dan alamat diulang dari awal. Tombol Batal di
/// dalam dialog tetap menutup seperti biasa.
///
/// [controllers] dimiliki widget ini: `dispose` baru jalan setelah dialog
/// dilepas dari pohon widget, jadi kolom isian tidak pernah memakai controller
/// yang sudah dibuang selama animasi tutup.
class _WriteDialog extends StatefulWidget {
  const _WriteDialog(this.child, [this.controllers = const []]);

  final Widget child;
  final List<TextEditingController> controllers;

  @override
  State<_WriteDialog> createState() => _WriteDialogState();
}

class _WriteDialogState extends State<_WriteDialog> {
  @override
  void dispose() {
    for (final c in widget.controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(canPop: false, child: widget.child);
}

/// Teks error di bawah kolom yang salah.
///
/// Toast hanya sempat terbaca dua detik dan tidak menunjuk kolom mana yang
/// bermasalah; teks ini menetap sampai kolomnya diperbaiki.
class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Text(
        text,
        style: t.textTheme.small.copyWith(fontSize: 11.5, color: AppThemes.bad(context)),
      ),
    );
  }
}
