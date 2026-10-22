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
  period    TEXT NOT NULL,
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

-- Satu anggota hanya boleh punya satu catatan iuran per periode. Klien
-- mengeceknya lebih dulu (`Payment.existsFor`), tapi dua perangkat bisa
-- menulis bersamaan. Index dibuat hanya kalau data lama sudah bersih;
-- kalau masih ada duplikat, `npm run db:fix` merapikannya lalu jalankan
-- `db:init` lagi.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes WHERE indexname = 'idx_payments_member_period'
  ) THEN
    IF EXISTS (
      SELECT 1 FROM payments GROUP BY member_id, period HAVING count(*) > 1
    ) THEN
      RAISE NOTICE 'index unik iuran dilewati: ada catatan ganda. Jalankan npm run db:fix.';
    ELSE
      CREATE UNIQUE INDEX idx_payments_member_period ON payments (member_id, period);
    END IF;
  END IF;
END
$$;

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

CREATE TABLE IF NOT EXISTS tournaments (
  id            SERIAL PRIMARY KEY,
  name          TEXT NOT NULL,
  venue         TEXT,
  starts_at     TIMESTAMPTZ NOT NULL,
  match_minutes INT NOT NULL DEFAULT 20,  -- durasi 1 laga
  break_minutes INT NOT NULL DEFAULT 0,   -- jeda antar laga
  groups        INT NOT NULL DEFAULT 1,   -- jumlah grup (1 = liga penuh)
  status        TEXT NOT NULL DEFAULT 'draft', -- draft | running | done
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE tournaments ADD COLUMN IF NOT EXISTS groups INT NOT NULL DEFAULT 1;

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

CREATE INDEX IF NOT EXISTS idx_tm_tournament       ON tournament_matches(tournament_id);
CREATE INDEX IF NOT EXISTS idx_team_players_member ON team_players(member_id);
CREATE INDEX IF NOT EXISTS idx_tournament_teams    ON tournament_teams(tournament_id);
CREATE INDEX IF NOT EXISTS idx_matches_teams       ON matches(home_team_id, away_team_id);

-- Klasemen abadi antar tim klub: semua laga internal yang sudah selesai.
CREATE OR REPLACE VIEW v_team_standings AS
SELECT t.id AS team_id,
       t.name,
       COUNT(m.id) FILTER (WHERE m.status = 'finished') AS played,
       COUNT(m.id) FILTER (WHERE m.status = 'finished' AND (
              (m.home_team_id = t.id AND m.goals_for > m.goals_against) OR
              (m.away_team_id = t.id AND m.goals_against > m.goals_for))) AS won,
       COUNT(m.id) FILTER (WHERE m.status = 'finished' AND m.goals_for = m.goals_against) AS drawn,
       COUNT(m.id) FILTER (WHERE m.status = 'finished' AND (
              (m.home_team_id = t.id AND m.goals_for < m.goals_against) OR
              (m.away_team_id = t.id AND m.goals_against < m.goals_for))) AS lost,
       COALESCE(SUM(CASE WHEN m.home_team_id = t.id THEN m.goals_for
                         WHEN m.away_team_id = t.id THEN m.goals_against END)
                FILTER (WHERE m.status = 'finished'), 0) AS goals_for,
       COALESCE(SUM(CASE WHEN m.home_team_id = t.id THEN m.goals_against
                         WHEN m.away_team_id = t.id THEN m.goals_for END)
                FILTER (WHERE m.status = 'finished'), 0) AS goals_against,
       3 * COUNT(m.id) FILTER (WHERE m.status = 'finished' AND (
              (m.home_team_id = t.id AND m.goals_for > m.goals_against) OR
              (m.away_team_id = t.id AND m.goals_against > m.goals_for)))
         + COUNT(m.id) FILTER (WHERE m.status = 'finished' AND m.goals_for = m.goals_against) AS points
FROM teams t
LEFT JOIN matches m
       ON (m.home_team_id = t.id OR m.away_team_id = t.id)
GROUP BY t.id, t.name;
