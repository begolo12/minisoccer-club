import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/db.dart';
import 'fmt.dart';
import 'theme.dart';
import 'widgets.dart';

/// Jejak audit: siapa mengubah apa, kapan.
///
/// Sampai sebelumnya tidak ada satu pun cara menjawab "siapa yang mengubah
/// catatan kas ini?" — `transactions` hanya punya `created_at`, tanpa pelaku,
/// dan penghapusan tidak meninggalkan apa pun. Halaman ini membaca tabel
/// `audit_log` yang diisi `api/sql.js` pada setiap tulisan yang berhasil.
///
/// Hanya admin: isinya menyebut nama orang dan pergerakan uang. Server juga
/// menolak role lain (`api/_guard.js`), jadi menyembunyikan tautannya bukan
/// satu-satunya lapis.
class AuditPage extends StatefulWidget {
  const AuditPage({super.key});

  @override
  State<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends State<AuditPage> {
  late Future<List<AuditRow>> _future = _load();

  static Future<List<AuditRow>> _load() async {
    // ponytail: 200 baris terakhir, tanpa halaman berikutnya. Cukup untuk
    // pertanyaan "apa yang terjadi belakangan ini"; kalau suatu saat butuh
    // riwayat penuh, tambahkan pemilih rentang tanggal, bukan "muat lagi"
    // tanpa batas.
    final rows = await Db.query(
      'SELECT * FROM audit_log ORDER BY at DESC LIMIT 200',
    );
    return rows.map(AuditRow.fromMap).toList();
  }

  Future<void> _reload() async {
    final f = _load();
    setState(() => _future = f);
    await f;
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return PageScaffold(
      title: 'Jejak audit',
      subtitle: '200 perubahan terakhir',
      child: AsyncView<List<AuditRow>>(
        future: _future,
        onRefresh: _reload,
        builder: (rows) {
          if (rows.isEmpty) {
            return const EmptyState(
              icon: Icons.history,
              title: 'Belum ada perubahan tercatat',
              message: 'Setiap tambah, ubah, dan hapus data akan muncul di sini '
                  'beserta siapa yang melakukannya.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            itemCount: rows.length + 1,
            separatorBuilder: (_, _) => Divider(
              height: 1,
              color: t.colorScheme.border.withValues(alpha: 0.5),
            ),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Catatan ini dibuat server saat data berhasil disimpan. '
                    'Isi barisnya tidak disalin — hanya siapa, tabel apa, dan '
                    'operasi apa.',
                    style: t.textTheme.small,
                  ),
                );
              }
              return _AuditTile(row: rows[i - 1]);
            },
          );
        },
      ),
    );
  }
}

/// Satu baris `audit_log`.
class AuditRow {
  const AuditRow({
    required this.at,
    required this.actor,
    required this.role,
    required this.table,
    required this.op,
    this.rowId,
    this.detail,
  });

  final DateTime at;
  final String actor;
  final String role;
  final String table;
  final String op;
  final int? rowId;
  final String? detail;

  factory AuditRow.fromMap(Map<String, dynamic> m) => AuditRow(
        at: DateTime.tryParse('${m['at']}')?.toLocal() ?? DateTime.now(),
        actor: (m['actor'] as String?) ?? '—',
        role: (m['role'] as String?) ?? '—',
        table: (m['tbl'] as String?) ?? '—',
        op: (m['op'] as String?) ?? '—',
        rowId: m['row_id'] == null ? null : int.tryParse('${m['row_id']}'),
        detail: m['detail'] as String?,
      );

  /// Nama tabel dalam bahasa manusia — `booking_attendance` tidak berarti apa
  /// pun bagi bendahara yang membuka halaman ini.
  String get tableLabel => switch (table) {
        'transactions' => 'Kas',
        'payments' => 'Iuran',
        'bookings' => 'Sewa lapangan',
        'booking_attendance' => 'Patungan lapangan',
        'members' => 'Anggota',
        'teams' => 'Tim',
        'team_players' => 'Pemain tim',
        'matches' => 'Tanding',
        'match_sessions' => 'Sesi tanding',
        'match_events' => 'Kejadian tanding',
        'tournaments' => 'Turnamen',
        'tournament_teams' => 'Tim turnamen',
        'tournament_matches' => 'Laga turnamen',
        'announcements' => 'Pengumuman',
        'settings' => 'Pengaturan',
        _ => table,
      };

  String get opLabel => switch (op) {
        'insert' => 'menambah',
        'update' => 'mengubah',
        'delete' => 'menghapus',
        _ => op,
      };

  bool get isDelete => op == 'delete';
}

class _AuditTile extends StatelessWidget {
  const _AuditTile({required this.row});

  final AuditRow row;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ikon sebagai penanda cepat: hapus paling perlu terlihat.
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 10),
            child: Icon(
              row.isDelete ? Icons.delete_outline : Icons.edit_outlined,
              size: 15,
              color: row.isDelete
                  ? AppThemes.bad(context)
                  : t.colorScheme.mutedForeground,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: row.actor,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextSpan(text: ' ${row.opLabel} '),
                      TextSpan(
                        text: row.tableLabel,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (row.rowId != null)
                        TextSpan(
                          text: ' #${row.rowId}',
                          style: TextStyle(color: t.colorScheme.mutedForeground),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${fmtDateTime(row.at)} · ${row.role}'
                  '${row.detail == null ? '' : ' · ${row.detail}'}',
                  style: t.textTheme.small,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
