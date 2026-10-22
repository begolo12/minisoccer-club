-- Minisoccer Club — Neon Postgres schema (v2)
-- Cara pakai: Neon Console -> SQL Editor -> paste semua -> Run.
-- Aman dijalankan ulang (idempotent).

CREATE TABLE IF NOT EXISTS members (
  id          SERIAL PRIMARY KEY,
  name        TEXT NOT NULL,
  phone       TEXT,
  position    TEXT NOT NULL DEFAULT 'Bebas', -- Kiper, Bek, Gelandang, Penyerang, Bebas
  jersey      INT,
  active      BOOLEAN NOT NULL DEFAULT TRUE,
  joined_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- User aplikasi + role. Password di-hash bcrypt oleh Postgres (crypt + gen_salt).
CREATE TABLE IF NOT EXISTS users (
  id            SERIAL PRIMARY KEY,
  username      TEXT NOT NULL UNIQUE,
  password_hash TEXT,
  pin_hash      TEXT,
  role          TEXT NOT NULL DEFAULT 'member', -- admin | treasurer | member
  member_id     INT REFERENCES members(id) ON DELETE SET NULL,
  active        BOOLEAN NOT NULL DEFAULT TRUE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- Untuk DB lama.
ALTER TABLE users ALTER COLUMN pin_hash DROP NOT NULL;
ALTER TABLE users ADD COLUMN IF NOT EXISTS password_hash TEXT;

-- Anti brute force: kunci sementara setelah beberapa kali gagal login.
ALTER TABLE users ADD COLUMN IF NOT EXISTS failed_attempts INT NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS locked_until TIMESTAMPTZ;

-- Sesi pertandingan (1 match bisa beberapa sesi / babak; tiap sesi punya pemenang).
--
-- Tanding klub ini INTERNAL: dua tim anggota klub saling bertemu, jadi
-- pertandingan menunjuk ke `teams` (Tim A, Tim B, ...), bukan nama lawan luar.
-- Kolom `opponent`/`is_home` lama dibiarkan (nullable) hanya untuk membaca
-- data lama; UI baru tidak memakainya.
CREATE TABLE IF NOT EXISTS matches (
  id            SERIAL PRIMARY KEY,
  opponent      TEXT,
  played_at     TIMESTAMPTZ NOT NULL,
  venue         TEXT,
  is_home       BOOLEAN NOT NULL DEFAULT TRUE,
  status        TEXT NOT NULL DEFAULT 'scheduled', -- scheduled | ongoing | finished
  goals_for     INT NOT NULL DEFAULT 0,   -- skor tim home (internal)
  goals_against INT NOT NULL DEFAULT 0,   -- skor tim away (internal)
  notes         TEXT
);

CREATE TABLE IF NOT EXISTS match_sessions (
  id          SERIAL PRIMARY KEY,
  match_id    INT NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
  session_no  INT NOT NULL DEFAULT 1,
  score_home  INT NOT NULL DEFAULT 0,
  score_away  INT NOT NULL DEFAULT 0,
  winner      TEXT NOT NULL DEFAULT 'draw', -- home | away | draw
  started_at  TIMESTAMPTZ,
  ended_at    TIMESTAMPTZ,
  UNIQUE (match_id, session_no)
);

CREATE TABLE IF NOT EXISTS match_events (
  id        SERIAL PRIMARY KEY,
  match_id  INT NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
  session_id INT REFERENCES match_sessions(id) ON DELETE CASCADE,
  member_id INT REFERENCES members(id) ON DELETE SET NULL,
  minute    INT,
  type      TEXT NOT NULL -- goal | assist | yellow | red | own_goal
);

-- Keuangan: satu tabel untuk semua arus kas (iuran, sewa lapangan, konsumsi, dsb).
CREATE TABLE IF NOT EXISTS transactions (
  id          SERIAL PRIMARY KEY,
  kind        TEXT NOT NULL,           -- income | expense
  category    TEXT NOT NULL DEFAULT 'lain', -- iuran | sewa | konsumsi | wasit | perlengkapan | lain
  amount      NUMERIC(12,2) NOT NULL CHECK (amount >= 0),
  occurred_at DATE NOT NULL DEFAULT CURRENT_DATE,
  member_id   INT REFERENCES members(id) ON DELETE SET NULL,
  period      TEXT,                    -- contoh: 2026-10 (khusus iuran)
  note        TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS payments (
  id        SERIAL PRIMARY KEY,
  member_id INT NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  amount    NUMERIC(12,2) NOT NULL,
  paid_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  note      TEXT
);

CREATE TABLE IF NOT EXISTS bookings (
  id           SERIAL PRIMARY KEY,
  title        TEXT NOT NULL,
  starts_at    TIMESTAMPTZ NOT NULL,
  duration_min INT NOT NULL DEFAULT 90,
  cost         NUMERIC(12,2) NOT NULL DEFAULT 0,
  status       TEXT NOT NULL DEFAULT 'booked' -- booked | done | canceled
);

-- Biaya sewa lapangan hidup di `bookings`, tapi uangnya keluar dari kas.
-- Kolom ini menghubungkan keduanya supaya satu pengeluaran tidak tercatat
-- dua kali (manual di Kas + otomatis dari booking). ON DELETE CASCADE:
-- hapus booking = hapus catatan kasnya.
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS booking_id INT
  REFERENCES bookings(id) ON DELETE CASCADE;

CREATE UNIQUE INDEX IF NOT EXISTS idx_tx_booking ON transactions(booking_id)
  WHERE booking_id IS NOT NULL;

-- ---------------------------------------------------------------------
-- Kehadiran per sesi + patungan biaya lapangan.
--
-- Satu baris = satu anggota yang ikut main di satu booking. Dari sini dua hal
-- dijawab sekaligus:
--
--   * SIAPA YANG DATANG  — pertanyaan tiap minggu, dan bahan evaluasi
--     ("si A jarang hadir") tanpa perlu catatan terpisah.
--   * SIAPA SUDAH SETOR  — biaya sewa dibagi rata ke yang hadir. Tanpa ini
--     kas selalu terlihat minus sebesar total sewa, padahal uangnya sudah
--     dikumpulkan dari pemain.
--
-- `share_amount` disimpan (bukan dihitung saat baca) karena pembagiannya
-- dibulatkan ke rupiah: 300.000 dibagi 7 tidak habis. Nilainya dihitung ulang
-- setiap kali daftar hadir berubah, dengan sisa pembulatan dibagikan satu per
-- satu ke baris teratas — supaya JUMLAH semua share selalu tepat sama dengan
-- `bookings.cost`. Kalau dihitung saat baca, angka "terkumpul" dan "target"
-- bisa berbeda satu-dua rupiah dan terlihat seperti bug.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS booking_attendance (
  id           SERIAL PRIMARY KEY,
  booking_id   INT NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  member_id    INT NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  share_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  paid_at      TIMESTAMPTZ,          -- NULL = belum setor
  note         TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (booking_id, member_id)
);

CREATE INDEX IF NOT EXISTS idx_attendance_booking ON booking_attendance(booking_id);
CREATE INDEX IF NOT EXISTS idx_attendance_member  ON booking_attendance(member_id);

-- Setoran patungan masuk kas sebagai PEMASUKAN. Dihubungkan ke baris
-- kehadirannya supaya satu setoran = satu catatan kas, dan tidak bisa dicatat
-- dua kali. Berbeda dari `booking_id` yang menandai PENGELUARAN sewa.
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS attendance_id INT
  REFERENCES booking_attendance(id) ON DELETE CASCADE;

-- Satu setoran = satu catatan kas. Index unik (bukan parsial) supaya
-- `INSERT ... ON CONFLICT (attendance_id) DO NOTHING` bisa memakainya sebagai
-- penjaga; Postgres mengizinkan banyak NULL pada kolom unik, jadi baris kas
-- lain yang tidak berasal dari patungan tetap aman.
CREATE UNIQUE INDEX IF NOT EXISTS idx_tx_attendance ON transactions(attendance_id);

CREATE TABLE IF NOT EXISTS announcements (
  id         SERIAL PRIMARY KEY,
  title      TEXT NOT NULL,
  body       TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS settings (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_matches_played_at  ON matches(played_at DESC);
CREATE INDEX IF NOT EXISTS idx_sessions_match     ON match_sessions(match_id);
CREATE INDEX IF NOT EXISTS idx_events_match       ON match_events(match_id);
CREATE INDEX IF NOT EXISTS idx_events_session     ON match_events(session_id);
CREATE INDEX IF NOT EXISTS idx_tx_occurred        ON transactions(occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_tx_period          ON transactions(period);
CREATE INDEX IF NOT EXISTS idx_payments_member    ON payments(member_id);

-- Index unik iuran: SATU catatan per anggota per TURNAMEN.
--
-- Dulu blok di sini membuat `idx_payments_member_period ON payments(member_id,
-- period)`. Kolom `period` sudah dihapus (iuran kini per turnamen), tetapi blok
-- itu tertinggal dan menyebut kolom yang tidak ada lagi — akibatnya
-- `npm run db:init` GAGAL dengan "column period does not exist", sehingga
-- database baru tidak bisa disiapkan sama sekali. Index penggantinya dibuat di
-- bawah, setelah kolom `tournament_id` dipastikan ada.
--
-- Index lama dibuang kalau masih tersisa di database yang belum dimigrasi.
DROP INDEX IF EXISTS idx_payments_member_period;

-- Tiga view lama dihapus: app menghitung rekap kas, pencetak gol, dan
-- klasemen turnamen di Dart (`mergeCashLedger`, `ScorerRow.top`,
-- `Standing.compute`). Membiarkannya berarti dua sumber kebenaran yang bisa
-- berbeda hasilnya. `DROP` dibuat IF EXISTS supaya `db:init` aman diulang.
DROP VIEW IF EXISTS v_monthly_finance;
DROP VIEW IF EXISTS v_player_stats;
DROP VIEW IF EXISTS v_standings;

-- =====================================================================
-- Tim tetap klub + tanding internal.
-- Satu klub punya beberapa tim (7-8 pemain per tim). Tanding internal
-- mempertemukan dua tim klub; klasemen dihitung dari semua laga selesai.
-- Turnamen internal memakai tim yang sama, dibagi ke beberapa grup.
-- =====================================================================

CREATE TABLE IF NOT EXISTS teams (
  id         SERIAL PRIMARY KEY,
  name       TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS team_players (
  team_id   INT NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  member_id INT NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  PRIMARY KEY (team_id, member_id)
);

ALTER TABLE matches ADD COLUMN IF NOT EXISTS home_team_id INT REFERENCES teams(id) ON DELETE SET NULL;
ALTER TABLE matches ADD COLUMN IF NOT EXISTS away_team_id INT REFERENCES teams(id) ON DELETE SET NULL;

-- ---------------------------------------------------------------------
-- Migrasi dari schema v1 (DB yang dibuat sebelum tanding internal ada).
--
-- `CREATE TABLE IF NOT EXISTS` di atas TIDAK menyentuh tabel yang sudah ada,
-- jadi kolom NOT NULL warisan v1 tetap memblokir tulis dari app baru:
--   * `matches.opponent NOT NULL` — app baru menulis home/away_team_id, bukan
--     nama lawan luar. Tanpa DROP NOT NULL, setiap "Buat jadwal" gagal
--     `null value in column "opponent"` dan halaman Tanding tampak rusak.
--   * `teams.tournament_id NOT NULL` — dulu satu tim milik satu turnamen.
--     Sekarang tim berdiri sendiri dan dihubungkan lewat `tournament_teams`.
--   * `teams.created_at` belum ada di v1, padahal dipakai `SELECT *`.
--
-- Semua di bawah idempoten: aman dijalankan berkali-kali, dan tidak
-- menghapus data lama (kolom v1 hanya dilonggarkan, bukan dibuang).
-- ---------------------------------------------------------------------
ALTER TABLE matches ALTER COLUMN opponent DROP NOT NULL;
ALTER TABLE teams ALTER COLUMN tournament_id DROP NOT NULL;
ALTER TABLE teams ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- Nama tim harus unik: satu klub tidak boleh punya dua "Tim A". v1 mengizinkan
-- duplikat karena tiap turnamen punya timnya sendiri, jadi index unik baru
-- dipasang kalau datanya sudah bersih (kalau tidak, `db:init` berhenti dengan
-- pesan jelas alih-alih gagal di tengah jalan).
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'teams_name_key') THEN
    IF EXISTS (SELECT 1 FROM teams GROUP BY name HAVING count(*) > 1) THEN
      RAISE NOTICE 'index unik nama tim dilewati: ada nama tim ganda. Rapikan dulu.';
    ELSE
      CREATE UNIQUE INDEX teams_name_key ON teams (name);
    END IF;
  END IF;
END
$$;

CREATE TABLE IF NOT EXISTS tournaments (
  id            SERIAL PRIMARY KEY,
  name          TEXT NOT NULL,
  venue         TEXT,
  starts_at     TIMESTAMPTZ NOT NULL,
  match_minutes INT NOT NULL DEFAULT 20,  -- durasi 1 laga
  break_minutes INT NOT NULL DEFAULT 0,   -- jeda antar laga
  groups        INT NOT NULL DEFAULT 1,   -- jumlah grup (1 = liga penuh)
  entry_fee     NUMERIC(12,2) NOT NULL DEFAULT 0, -- iuran per anggota untuk turnamen ini
  status        TEXT NOT NULL DEFAULT 'draft', -- draft | running | done
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE tournaments ADD COLUMN IF NOT EXISTS groups INT NOT NULL DEFAULT 1;
ALTER TABLE tournaments ADD COLUMN IF NOT EXISTS entry_fee NUMERIC(12,2) NOT NULL DEFAULT 0;

-- Pembagian tim ke grup pada satu turnamen.
CREATE TABLE IF NOT EXISTS tournament_teams (
  tournament_id INT NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
  team_id       INT NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  group_no      INT NOT NULL DEFAULT 1,
  PRIMARY KEY (tournament_id, team_id)
);

CREATE TABLE IF NOT EXISTS tournament_matches (
  id            SERIAL PRIMARY KEY,
  tournament_id INT NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
  group_no      INT NOT NULL DEFAULT 1,
  round         INT NOT NULL DEFAULT 1,
  slot          INT NOT NULL,             -- urutan main (1..n)
  home_team_id  INT NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  away_team_id  INT NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  kickoff       TIMESTAMPTZ NOT NULL,
  score_home    INT,                      -- NULL = belum dimainkan
  score_away    INT,
  status        TEXT NOT NULL DEFAULT 'scheduled', -- scheduled | done
  UNIQUE (tournament_id, slot)
);

ALTER TABLE tournament_matches ADD COLUMN IF NOT EXISTS group_no INT NOT NULL DEFAULT 1;

-- ---------------------------------------------------------------------
-- Migrasi: iuran BULANAN → iuran PER TURNAMEN.
--
-- Dulu `payments` punya kolom `period` ('2026-10') dan halaman Iuran memilih
-- bulan. Kenyataannya iuran klub ini ditarik per turnamen, dan tim yang ikut
-- tiap turnamen berbeda-beda — jadi tagihan yang benar adalah "anggota X untuk
-- turnamen Y", bukan "anggota X untuk bulan Z".
--
-- Urutannya penting:
--   1. tambah kolom `tournament_id`;
--   2. hapus pembayaran bulanan lama (tidak punya padanan turnamen; pemilik
--      klub memilih menghapusnya daripada menyisakan tagihan menggantung);
--   3. baru buang kolom `period`.
--
-- Semua dibungkus pengecekan kolom supaya idempoten: `db:init` aman dijalankan
-- berkali-kali dan di database yang sudah lama maupun yang baru.
-- ---------------------------------------------------------------------
ALTER TABLE payments ADD COLUMN IF NOT EXISTS tournament_id INT
  REFERENCES tournaments(id) ON DELETE CASCADE;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'payments' AND column_name = 'period'
  ) THEN
    DELETE FROM payments WHERE tournament_id IS NULL;
    ALTER TABLE payments DROP COLUMN period;
  END IF;
END
$$;

-- Satu anggota hanya membayar sekali per turnamen. Tanpa ini, dua entri bisa
-- tercatat untuk orang dan turnamen yang sama dan totalnya jadi dobel.
CREATE UNIQUE INDEX IF NOT EXISTS payments_member_tournament_uniq
  ON payments(member_id, tournament_id);

CREATE INDEX IF NOT EXISTS idx_payments_tournament ON payments(tournament_id);

CREATE INDEX IF NOT EXISTS idx_tm_tournament       ON tournament_matches(tournament_id);
CREATE INDEX IF NOT EXISTS idx_team_players_member ON team_players(member_id);
CREATE INDEX IF NOT EXISTS idx_tournament_teams    ON tournament_teams(tournament_id);
CREATE INDEX IF NOT EXISTS idx_matches_teams       ON matches(home_team_id, away_team_id);

-- Klasemen abadi antar tim klub: semua laga internal yang sudah selesai.
--
-- Semua kolom angka di-cast ke INT. `COUNT`/`SUM` menghasilkan BIGINT, dan
-- driver Neon mengirim BIGINT sebagai **String** ke klien (supaya angka besar
-- tidak kehilangan presisi). Tanpa cast, app menerima `"played": "1"` lalu
-- melempar "type 'String' is not a subtype of type 'int'" begitu ada satu
-- laga selesai — klasemen tim mati total. Cast di sini memperbaiki sumbernya
-- untuk semua klien, bukan hanya yang sudah diberi pengaman.
--
-- DROP dulu, bukan CREATE OR REPLACE: Postgres menolak REPLACE yang mengubah
-- tipe kolom ("cannot change data type of view column ... from bigint to
-- integer"), jadi view lama harus dibuang. Aman karena view ini tidak
-- menyimpan data dan tidak dirujuk view lain.
DROP VIEW IF EXISTS v_team_standings;
CREATE VIEW v_team_standings AS
SELECT t.id AS team_id,
       t.name,
       (COUNT(m.id) FILTER (WHERE m.status = 'finished'))::int AS played,
       (COUNT(m.id) FILTER (WHERE m.status = 'finished' AND (
              (m.home_team_id = t.id AND m.goals_for > m.goals_against) OR
              (m.away_team_id = t.id AND m.goals_against > m.goals_for))))::int AS won,
       (COUNT(m.id) FILTER (WHERE m.status = 'finished' AND m.goals_for = m.goals_against))::int AS drawn,
       (COUNT(m.id) FILTER (WHERE m.status = 'finished' AND (
              (m.home_team_id = t.id AND m.goals_for < m.goals_against) OR
              (m.away_team_id = t.id AND m.goals_against < m.goals_for))))::int AS lost,
       COALESCE(SUM(CASE WHEN m.home_team_id = t.id THEN m.goals_for
                         WHEN m.away_team_id = t.id THEN m.goals_against END)
                FILTER (WHERE m.status = 'finished'), 0)::int AS goals_for,
       COALESCE(SUM(CASE WHEN m.home_team_id = t.id THEN m.goals_against
                         WHEN m.away_team_id = t.id THEN m.goals_for END)
                FILTER (WHERE m.status = 'finished'), 0)::int AS goals_against,
       (3 * COUNT(m.id) FILTER (WHERE m.status = 'finished' AND (
              (m.home_team_id = t.id AND m.goals_for > m.goals_against) OR
              (m.away_team_id = t.id AND m.goals_against > m.goals_for)))
         + COUNT(m.id) FILTER (WHERE m.status = 'finished' AND m.goals_for = m.goals_against))::int AS points
FROM teams t
LEFT JOIN matches m
       ON (m.home_team_id = t.id OR m.away_team_id = t.id)
GROUP BY t.id, t.name;

-- ---------------------------------------------------------------------
-- Izin ulang untuk `app_web` setelah view dibuat ulang.
--
-- `DROP VIEW` + `CREATE VIEW` menghapus semua GRANT pada view itu, sehingga
-- `/api/sql` tiba-tiba menjawab "Query gagal dijalankan" sampai `db:harden`
-- dijalankan lagi. Itu jebakan: migrasi schema yang rutin malah mematikan
-- klasemen. Grant diulang di sini supaya `db:init` tetap mandiri.
--
-- Hanya dijalankan kalau role `app_web` sudah ada — di database baru,
-- `db:harden` yang membuat role dan memberikan izin lengkap.
-- ---------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_web') THEN
    GRANT USAGE ON SCHEMA public TO app_web;
    GRANT SELECT ON v_team_standings TO app_web;
  END IF;
END
$$;
