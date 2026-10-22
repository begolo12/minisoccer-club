/// Menambal hasil query yang tersimpan di cache setelah tulis offline.
///
/// Kenapa perlu: app ini mengirim SQL mentah ke server, dan hasil baca disimpan
/// per query. Saat jaringan mati dan pengguna menambah anggota, hasil `SELECT *
/// FROM members` di cache tidak tahu apa-apa soal baris baru itu — halaman akan
/// tampak "tidak tersimpan". Penambal ini menerapkan efek tulis ke baris yang
/// sudah ada di cache, jadi data yang diisi offline langsung terlihat.
///
/// Batasan yang disengaja: hanya bentuk SQL yang dipakai app ini yang dikenali.
/// Kalau sebuah tulis memakai ekspresi yang tidak bisa dihitung di klien
/// (`CASE`, `COALESCE(subquery)`, dsb.), op ditandai tidak bisa ditambal dan
/// cache dibiarkan apa adanya — data akan benar setelah sinkron. Lebih baik
/// menampilkan data lama daripada menampilkan angka karangan.
library;

/// Satu operasi tulis yang sudah diurai.
class WriteOp {
  const WriteOp({
    required this.kind,
    required this.table,
    this.values = const {},
    this.whereEq = const {},
    this.conflictCols = const [],
    this.patchable = true,
    this.returnsId = false,
  });

  /// `insert` | `update` | `delete`.
  final String kind;
  final String table;

  /// INSERT: kolom → nilai. UPDATE: kolom yang di-SET → nilai.
  final Map<String, Object?> values;

  /// WHERE berupa konjungsi kesamaan: kolom → nilai.
  final Map<String, Object?> whereEq;

  /// Kolom kunci `ON CONFLICT (...)` untuk upsert.
  final List<String> conflictCols;

  /// False kalau bentuk SQL-nya di luar yang bisa dihitung di klien.
  final bool patchable;

  /// True kalau statement punya `RETURNING id`.
  final bool returnsId;

  bool get isInsert => kind == 'insert';
  bool get isUpdate => kind == 'update';
  bool get isDelete => kind == 'delete';
}

/// Nilai yang tidak bisa dihitung di klien.
class _Unresolved {
  const _Unresolved();
}

const _unresolved = _Unresolved();

/// Pecah teks pada pemisah level atas (di luar tanda kutip dan tanda kurung).
List<String> _splitTopLevel(String s, String sep) {
  final out = <String>[];
  var buf = StringBuffer();
  var depth = 0;
  var i = 0;
  while (i < s.length) {
    final c = s[i];
    if (c == "'") {
      buf.write(c);
      i++;
      while (i < s.length) {
        buf.write(s[i]);
        if (s[i] == "'") {
          if (i + 1 < s.length && s[i + 1] == "'") {
            buf.write(s[i + 1]);
            i += 2;
            continue;
          }
          i++;
          break;
        }
        i++;
      }
      continue;
    }
    if (c == '(') depth++;
    if (c == ')') depth--;
    if (depth == 0 && s.startsWith(sep, i)) {
      out.add(buf.toString());
      buf = StringBuffer();
      i += sep.length;
      continue;
    }
    buf.write(c);
    i++;
  }
  out.add(buf.toString());
  return out;
}

/// Cari kata kunci utuh (bukan bagian dari identifier) di luar kutip/kurung.
int _indexOfKeyword(String upper, String kw) {
  var depth = 0;
  var inQuote = false;
  for (var i = 0; i < upper.length; i++) {
    final c = upper[i];
    if (c == "'") {
      inQuote = !inQuote;
      continue;
    }
    if (inQuote) continue;
    if (c == '(') depth++;
    if (c == ')') depth--;
    if (depth != 0) continue;
    if (upper.startsWith(kw, i)) {
      final before = i == 0 ? ' ' : upper[i - 1];
      final afterIdx = i + kw.length;
      final after = afterIdx >= upper.length ? ' ' : upper[afterIdx];
      final okBefore = !RegExp(r'[A-Z0-9_]').hasMatch(before);
      final okAfter = !RegExp(r'[A-Z0-9_]').hasMatch(after);
      if (okBefore && okAfter) return i;
    }
  }
  return -1;
}

/// Hitung satu ekspresi nilai jadi nilai Dart, atau [_unresolved].
Object? _eval(String expr, Map<String, Object?> params) {
  var e = expr.trim();
  if (e.isEmpty) return _unresolved;

  // @nama
  if (e.startsWith('@')) {
    final name = e.substring(1).trim();
    if (!RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(name)) return _unresolved;
    if (!params.containsKey(name)) return _unresolved;
    return params[name];
  }

  // 'teks'
  if (e.startsWith("'") && e.endsWith("'") && e.length >= 2) {
    return e.substring(1, e.length - 1).replaceAll("''", "'");
  }

  final upper = e.toUpperCase();
  if (upper == 'NULL') return null;
  if (upper == 'TRUE') return true;
  if (upper == 'FALSE') return false;
  // Nilai waktu: untuk cache cukup representasi ISO, sama seperti yang
  // dikirim driver ke Neon.
  if (upper == 'NOW()' || upper == 'CURRENT_TIMESTAMP') {
    return DateTime.now().toUtc().toIso8601String();
  }
  if (upper == 'CURRENT_DATE') {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-'
        '${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  // Angka
  final n = num.tryParse(e);
  if (n != null) return n;

  return _unresolved;
}

/// Urai WHERE menjadi konjungsi kesamaan. Null kalau tidak bisa dievaluasi.
///
/// Kolom boleh berkualifikasi (`p.tournament_id`): query baca memakai alias
/// tabel, dan tanpa menerima bentuk itu syarat WHERE-nya tidak terbaca —
/// akibatnya baris hasil INSERT disisipkan ke SEMUA cache query, sehingga satu
/// pembayaran muncul di daftar semua turnamen.
Map<String, Object?>? _parseWhereEq(String where, Map<String, Object?> params) {
  final text = where.trim();
  if (text.isEmpty) return const {};
  final out = <String, Object?>{};
  for (final term in _splitTopLevel(text, ' AND ')) {
    final t = term.trim();
    if (t.isEmpty) continue;
    final parts = _splitTopLevel(t, '=');
    if (parts.length != 2) return null; // OR, IN, IS NULL, perbandingan lain
    final raw = parts[0].trim();
    // Terima `kolom` maupun `alias.kolom`; yang dipakai nama kolomnya.
    final m = RegExp(r'^(?:[a-zA-Z_][a-zA-Z0-9_]*\.)?([a-zA-Z_][a-zA-Z0-9_]*)$')
        .firstMatch(raw);
    if (m == null) return null;
    final col = m.group(1)!.toLowerCase();
    final v = _eval(parts[1], params);
    if (v is _Unresolved) return null;
    out[col] = v;
  }
  return out;
}

/// Urai satu statement tulis. Return null kalau bukan tulis yang dikenal.
WriteOp? parseWrite(String sql, Map<String, Object?> params) {
  final text = sql.trim().replaceFirst(RegExp(r';+\s*$'), '');

  final returnsId = RegExp(r'RETURNING\s+.*\bid\b', caseSensitive: false).hasMatch(text);

  // ---------- INSERT ----------
  final ins = RegExp(r'^INSERT\s+INTO\s+([a-zA-Z_][a-zA-Z0-9_]*)', caseSensitive: false)
      .firstMatch(text);
  if (ins != null) {
    final table = ins.group(1)!.toLowerCase();
    final afterTable = text.substring(ins.end);
    final colsMatch = RegExp(r'^\s*\(([^)]*)\)').firstMatch(afterTable);
    final valuesMatch =
        RegExp(r'VALUES\s*(\([\s\S]*?\))\s*(?:ON\s+CONFLICT|RETURNING|$)', caseSensitive: false)
            .firstMatch(afterTable);
    if (colsMatch == null || valuesMatch == null) {
      return WriteOp(kind: 'insert', table: table, patchable: false, returnsId: returnsId);
    }
    final cols = colsMatch
        .group(1)!
        .split(',')
        .map((c) => c.trim().toLowerCase())
        .where((c) => c.isNotEmpty)
        .toList();
    final tuple = valuesMatch.group(1)!;
    // Lebih dari satu tuple (jadwal turnamen): bukan urusan penambal.
    if (_splitTopLevel(tuple, '),(').length > 1) {
      return WriteOp(kind: 'insert', table: table, patchable: false, returnsId: returnsId);
    }
    final inner = tuple.substring(1, tuple.length - 1);
    final exprs = _splitTopLevel(inner, ',');
    if (exprs.length != cols.length) {
      return WriteOp(kind: 'insert', table: table, patchable: false, returnsId: returnsId);
    }
    final values = <String, Object?>{};
    var patchable = true;
    for (var i = 0; i < cols.length; i++) {
      final v = _eval(exprs[i], params);
      if (v is _Unresolved) {
        patchable = false;
        break;
      }
      values[cols[i]] = v;
    }
    final conflict = RegExp(r'ON\s+CONFLICT\s*\(([^)]*)\)', caseSensitive: false)
        .firstMatch(afterTable);
    final conflictCols = conflict == null
        ? const <String>[]
        : conflict
            .group(1)!
            .split(',')
            .map((c) => c.trim().toLowerCase())
            .where((c) => c.isNotEmpty)
            .toList();
    return WriteOp(
      kind: 'insert',
      table: table,
      values: patchable ? values : const {},
      conflictCols: conflictCols,
      patchable: patchable,
      returnsId: returnsId,
    );
  }

  // ---------- UPDATE ----------
  final upd = RegExp(r'^UPDATE\s+([a-zA-Z_][a-zA-Z0-9_]*)', caseSensitive: false)
      .firstMatch(text);
  if (upd != null) {
    final table = upd.group(1)!.toLowerCase();
    final afterTable = text.substring(upd.end);
    final setIdx = _indexOfKeyword(afterTable.toUpperCase(), 'SET');
    if (setIdx < 0) return WriteOp(kind: 'update', table: table, patchable: false);
    final afterSet = afterTable.substring(setIdx + 3);
    final whereIdx = _indexOfKeyword(afterSet.toUpperCase(), 'WHERE');
    final setText = whereIdx < 0 ? afterSet : afterSet.substring(0, whereIdx);
    final whereText = whereIdx < 0 ? '' : afterSet.substring(whereIdx + 5);

    final values = <String, Object?>{};
    var patchable = true;
    for (final assignment in _splitTopLevel(setText, ',')) {
      final parts = _splitTopLevel(assignment, '=');
      if (parts.length != 2) {
        patchable = false;
        break;
      }
      final col = parts[0].trim().toLowerCase();
      if (!RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(col)) {
        patchable = false;
        break;
      }
      final v = _eval(parts[1], params);
      if (v is _Unresolved) {
        patchable = false;
        break;
      }
      values[col] = v;
    }
    final whereEq = _parseWhereEq(whereText, params);
    return WriteOp(
      kind: 'update',
      table: table,
      values: patchable ? values : const {},
      whereEq: whereEq ?? const {},
      patchable: patchable && whereEq != null,
      returnsId: returnsId,
    );
  }

  // ---------- DELETE ----------
  final del = RegExp(r'^DELETE\s+FROM\s+([a-zA-Z_][a-zA-Z0-9_]*)', caseSensitive: false)
      .firstMatch(text);
  if (del != null) {
    final table = del.group(1)!.toLowerCase();
    final afterTable = text.substring(del.end);
    final whereIdx = _indexOfKeyword(afterTable.toUpperCase(), 'WHERE');
    final whereText = whereIdx < 0 ? '' : afterTable.substring(whereIdx + 5);
    final whereEq = _parseWhereEq(whereText, params);
    return WriteOp(
      kind: 'delete',
      table: table,
      whereEq: whereEq ?? const {},
      // DELETE tanpa WHERE yang bisa diurai tidak boleh menghapus semua baris
      // di cache: itu akan mengosongkan tampilan tanpa alasan.
      patchable: whereEq != null && whereEq.isNotEmpty,
      returnsId: returnsId,
    );
  }

  return null;
}

/// Bandingkan nilai longgar: JSON mengembalikan angka besar sebagai String,
/// sementara parameter bisa `int`. `1` dan `'1'` harus dianggap sama.
bool _looseEquals(Object? a, Object? b) {
  if (a == null && b == null) return true;
  if (a == null || b == null) return false;
  if (a == b) return true;
  final na = a is num ? a : num.tryParse('$a');
  final nb = b is num ? b : num.tryParse('$b');
  if (na != null && nb != null) return na == nb;
  return '$a' == '$b';
}

bool _matchesWhere(Map<String, dynamic> row, Map<String, Object?> where) {
  for (final e in where.entries) {
    if (!_looseEquals(row[e.key], e.value)) return false;
  }
  return true;
}

/// Apakah query membaca tabel ini?
bool _queryTouches(String sql, String table) {
  final re = RegExp(
    r'\b(?:from|join|into)\s+' + RegExp.escape(table) + r'\b',
    caseSensitive: false,
  );
  return re.hasMatch(sql);
}

/// Syarat WHERE sebuah query BACA, kalau bentuknya konjungsi kesamaan.
///
/// Dipakai sebelum menyisipkan baris hasil INSERT ke hasil cache: query
/// `... WHERE p.tournament_id = @t` dengan `@t = 9` tidak boleh ketambahan
/// baris milik turnamen 7. Tanpa pemeriksaan ini, satu pembayaran muncul di
/// semua turnamen.
///
/// Return null kalau syaratnya tidak bisa diurai (mis. `WHERE active`), supaya
/// pemanggil bisa memilih melonggarkan alih-alih membuang baris yang sah.
Map<String, Object?>? _queryWhereEq(String sql, Map<String, Object?> params) {
  final upper = sql.toUpperCase();
  final idx = _indexOfKeyword(upper, 'WHERE');
  if (idx < 0) return const {};
  var tail = sql.substring(idx + 5);
  // Potong klausa berikutnya.
  for (final kw in ['ORDER BY', 'GROUP BY', 'LIMIT', 'OFFSET', 'HAVING']) {
    final at = _indexOfKeyword(tail.toUpperCase(), kw);
    if (at >= 0) tail = tail.substring(0, at);
  }
  return _parseWhereEq(tail, params);
}

/// Apakah [row] memenuhi syarat WHERE sebuah query baca?
///
/// Kalau syaratnya tidak bisa diurai, baris dianggap cocok: lebih baik
/// menampilkan baris yang mungkin berlebih daripada menyembunyikan data yang
/// baru saja diisi pengguna.
bool _rowFitsQuery(Map<String, dynamic> row, String sql, Map<String, Object?> params) {
  final where = _queryWhereEq(sql, params);
  if (where == null || where.isEmpty) return true;
  for (final e in where.entries) {
    if (!row.containsKey(e.key)) return true; // tidak bisa dinilai
    if (!_looseEquals(row[e.key], e.value)) return false;
  }
  return true;
}

/// Query yang hasilnya BUKAN daftar baris tabel, melainkan ringkasan
/// (count/sum/avg, atau satu baris per grup).
///
/// Baris tabel tidak boleh ditambahkan ke hasil seperti ini: `count(*)` akan
/// tetap 1 baris, tapi baris anggota baru yang ikut disisipkan bisa muncul
/// sebagai "pencetak gol" palsu di `ScorerRow.top` atau mengacaukan
/// `Match.stats`. Untuk query begini cache dibiarkan apa adanya — angkanya
/// baru benar setelah sinkron, dan itu lebih baik daripada angka karangan.
bool _queryIsAggregate(String sql) {
  if (RegExp(r'\bGROUP\s+BY\b', caseSensitive: false).hasMatch(sql)) return true;
  return RegExp(r'\b(?:count|sum|avg|min|max|array_agg|string_agg)\s*\(',
          caseSensitive: false)
      .hasMatch(sql);
}

/// Nilai default kolom yang diisi database saat INSERT tidak menyebutkannya.
///
/// Baris hasil tambalan harus berbentuk sama dengan baris dari server: kalau
/// `active` atau `status` kosong, pembacaan model gagal atau menampilkan nilai
/// yang salah. Peta ini **menyalin** `db/schema.sql`, dan
/// `test/row_patch_schema_test.dart` membacanya langsung dari berkas skema —
/// jadi kalau skema berubah, tes gagal, bukan diam-diam melenceng.
const _columnDefaults = <String, Map<String, Object?>>{
  'members': {'position': 'Bebas', 'active': true},
  'users': {'role': 'member', 'active': true},
  'matches': {
    'is_home': true,
    'status': 'scheduled',
    'goals_for': 0,
    'goals_against': 0,
  },
  'match_sessions': {
    'session_no': 1,
    'score_home': 0,
    'score_away': 0,
    'winner': 'draw',
  },
  'transactions': {'category': 'lain', 'occurred_at': _SqlToday()},
  'bookings': {'duration_min': 90, 'cost': 0, 'status': 'booked'},
  'booking_attendance': {'share_amount': 0},
  'tournaments': {
    'match_minutes': 20,
    'break_minutes': 0,
    'groups': 1,
    'entry_fee': 0,
    'status': 'draft',
  },
  'tournament_teams': {'group_no': 1},
  'tournament_matches': {'group_no': 1, 'round': 1, 'status': 'scheduled'},
};

/// Kolom `DEFAULT now()` di `db/schema.sql`.
const _autoTimestamps = <String, List<String>>{
  'members': ['joined_at'],
  'users': ['created_at'],
  'transactions': ['created_at'],
  'payments': ['paid_at'],
  'bookings': ['created_at'],
  'booking_attendance': ['created_at'],
  'announcements': ['created_at'],
  'teams': ['created_at'],
  'tournaments': ['created_at'],
};

/// Penanda `CURRENT_DATE` — dihitung saat baris ditambal, bukan saat compile.
class _SqlToday {
  const _SqlToday();
}

/// Untuk tes: default kolom yang dipakai penambal.
Map<String, Map<String, Object?>> debugColumnDefaults() => _columnDefaults;
List<String> debugAutoTimestampCols(String table) =>
    _autoTimestamps[table] ?? const [];

String _todayIso() {
  final n = DateTime.now();
  return '${n.year.toString().padLeft(4, '0')}-'
      '${n.month.toString().padLeft(2, '0')}-'
      '${n.day.toString().padLeft(2, '0')}';
}

/// Terapkan satu operasi tulis ke baris hasil sebuah query cache.
///
/// [tempId] dipakai untuk INSERT: baris baru diberi id sementara (negatif)
/// supaya UI punya pegangan dan baris itu bisa dikenali. Saat sinkron, id
/// sementara dipetakan ke id asli lewat `Outbox`.
List<Map<String, dynamic>> applyOp(
  List<Map<String, dynamic>> rows,
  WriteOp op, {
  String querySql = '',
  Map<String, Object?> queryParams = const {},
  int? tempId,
}) {
  if (!op.patchable) return rows;
  if (querySql.isNotEmpty && !_queryTouches(querySql, op.table)) return rows;
  // Hasil ringkasan (count/sum/GROUP BY) tidak bisa ditambal per baris.
  if (querySql.isNotEmpty && _queryIsAggregate(querySql)) return rows;

  if (op.isInsert) {
    // Upsert: kalau kunci konflik sudah ada, perbarui baris itu.
    if (op.conflictCols.isNotEmpty) {
      final idx = rows.indexWhere((r) =>
          op.conflictCols.every((c) => _looseEquals(r[c], op.values[c])));
      if (idx >= 0) {
        final copy = Map<String, dynamic>.from(rows[idx])..addAll(op.values);
        final out = [...rows];
        out[idx] = copy;
        return out;
      }
    }
    final row = <String, dynamic>{...op.values};
    if (tempId != null && !row.containsKey('id')) row['id'] = tempId;

    // Tiru DEFAULT skema: kolom yang tidak disebut INSERT tetap punya nilai.
    for (final e in (_columnDefaults[op.table] ?? const {}).entries) {
      if (row.containsKey(e.key)) continue;
      final v = e.value;
      row[e.key] = v is _SqlToday ? _todayIso() : v;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    for (final col in _autoTimestamps[op.table] ?? const <String>[]) {
      row.putIfAbsent(col, () => now);
    }
    // Hormati WHERE query baca: query yang difilter ke turnamen 9 tidak boleh
    // ketambahan baris milik turnamen 7. Tanpa ini satu pembayaran muncul di
    // daftar semua turnamen.
    if (querySql.isNotEmpty && !_rowFitsQuery(row, querySql, queryParams)) return rows;
    return [...rows, row];
  }

  if (op.isUpdate) {
    return [
      for (final r in rows)
        if (_matchesWhere(r, op.whereEq))
          (Map<String, dynamic>.from(r)..addAll(op.values))
        else
          r,
    ];
  }

  if (op.isDelete) {
    return [
      for (final r in rows)
        if (!_matchesWhere(r, op.whereEq)) r,
    ];
  }

  return rows;
}

/// Urutkan baris mengikuti `ORDER BY` query, kalau bentuknya sederhana
/// (kolom, boleh berkualifikasi tabel, dengan ASC/DESC).
List<Map<String, dynamic>> sortLikeQuery(List<Map<String, dynamic>> rows, String sql) {
  final m = RegExp(r'ORDER\s+BY\s+([\s\S]+?)(?:\bLIMIT\b|$)', caseSensitive: false)
      .firstMatch(sql);
  if (m == null) return rows;
  final specs = <(String, bool)>[];
  for (final part in _splitTopLevel(m.group(1)!.trim(), ',')) {
    final t = part.trim();
    if (t.isEmpty) continue;
    final bits = t.split(RegExp(r'\s+'));
    var col = bits.first;
    if (col.contains('(') || col.contains('-') || col.contains('+')) return rows;
    col = col.split('.').last;
    if (!RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(col)) return rows;
    final desc = bits.length > 1 && bits[1].toUpperCase() == 'DESC';
    specs.add((col, desc));
  }
  if (specs.isEmpty) return rows;

  final out = [...rows];
  out.sort((a, b) {
    for (final (col, desc) in specs) {
      final c = _compareValues(a[col], b[col]);
      if (c != 0) return desc ? -c : c;
    }
    return 0;
  });
  return out;
}

int _compareValues(Object? a, Object? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1; // null terakhir
  if (b == null) return -1;
  final na = a is num ? a : num.tryParse('$a');
  final nb = b is num ? b : num.tryParse('$b');
  if (na != null && nb != null) return na.compareTo(nb);
  return '$a'.compareTo('$b');
}

/// Terapkan `LIMIT` query supaya baris hasil tambalan tidak melebihi bentuk
/// aslinya (mis. riwayat dibatasi 20 baris).
List<Map<String, dynamic>> trimLikeQuery(
  List<Map<String, dynamic>> rows,
  String sql,
  Map<String, Object?> params,
) {
  final m = RegExp(r'\bLIMIT\s+(@?[a-zA-Z0-9_]+)', caseSensitive: false).firstMatch(sql);
  if (m == null) return rows;
  final raw = m.group(1)!;
  final int? limit;
  if (raw.startsWith('@')) {
    final v = params[raw.substring(1)];
    limit = v is num ? v.toInt() : int.tryParse('$v');
  } else {
    limit = int.tryParse(raw);
  }
  if (limit == null || limit <= 0 || rows.length <= limit) return rows;
  return rows.sublist(0, limit);
}
