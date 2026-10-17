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

-- User aplikasi + role. pin_hash disiapkan untuk login PIN (belum dipakai).
CREATE TABLE IF NOT EXISTS users (
  id         SERIAL PRIMARY KEY,
  username   TEXT NOT NULL UNIQUE,
  pin_hash   TEXT,
  role       TEXT NOT NULL DEFAULT 'member', -- admin | treasurer | member
  member_id  INT REFERENCES members(id) ON DELETE SET NULL,
  active     BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- Untuk DB lama yang kolomnya sudah terlanjur NOT NULL.
ALTER TABLE users ALTER COLUMN pin_hash DROP NOT NULL;

-- Sesi pertandingan (1 match bisa beberapa sesi / babak; tiap sesi punya pemenang).
CREATE TABLE IF NOT EXISTS matches (
  id            SERIAL PRIMARY KEY,
  opponent      TEXT NOT NULL,
  played_at     TIMESTAMPTZ NOT NULL,
  venue         TEXT,
  is_home       BOOLEAN NOT NULL DEFAULT TRUE,
  status        TEXT NOT NULL DEFAULT 'scheduled', -- scheduled | ongoing | finished
  goals_for     INT NOT NULL DEFAULT 0,
  goals_against INT NOT NULL DEFAULT 0,
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

-- View rekap keuangan per bulan.
CREATE OR REPLACE VIEW v_monthly_finance AS
SELECT to_char(occurred_at, 'YYYY-MM') AS period,
       COALESCE(SUM(amount) FILTER (WHERE kind = 'income'), 0)  AS income,
       COALESCE(SUM(amount) FILTER (WHERE kind = 'expense'), 0) AS expense
FROM transactions
GROUP BY 1
ORDER BY 1 DESC;

-- View papan skor / klasemen pemain.
CREATE OR REPLACE VIEW v_player_stats AS
SELECT m.id, m.name, m.position,
       COUNT(e.id) FILTER (WHERE e.type = 'goal')   AS goals,
       COUNT(e.id) FILTER (WHERE e.type = 'assist') AS assists,
       COUNT(e.id) FILTER (WHERE e.type = 'yellow') AS yellows,
       COUNT(e.id) FILTER (WHERE e.type = 'red')    AS reds
FROM members m
LEFT JOIN match_events e ON e.member_id = m.id
GROUP BY m.id, m.name, m.position;
