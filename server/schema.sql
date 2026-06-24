-- RUNG backend schema (Cloudflare D1 / SQLite). See server/arch notes.
PRAGMA foreign_keys = ON;

-- ===== reference data (bulk-loaded; the Worker never holds these in memory) =====

-- The full ENABLE dictionary (152,240 words, len 3..12, UPPERCASE) for server-side
-- membership checks at /run (batched WHERE word IN (...)).
CREATE TABLE IF NOT EXISTS words (
  word TEXT PRIMARY KEY
);

-- Precomputed daily boards (board generation runs the 152k-word solver offline; the
-- Worker just reads the tiles for a day).
CREATE TABLE IF NOT EXISTS boards (
  day_index      INTEGER PRIMARY KEY,
  tiles          TEXT    NOT NULL,        -- 12 letters, sorted A..Z
  playable_count INTEGER NOT NULL,
  max_word_score INTEGER NOT NULL
);

-- ===== players / identity =====
CREATE TABLE IF NOT EXISTS players (
  id              TEXT    PRIMARY KEY,            -- 'p_' + random
  apple_sub       TEXT    UNIQUE,                 -- HMAC(sub) lookup key; nullable until SIWA
  username        TEXT    UNIQUE COLLATE NOCASE,  -- nullable until chosen
  display         TEXT    NOT NULL,
  friend_code     TEXT    NOT NULL UNIQUE,
  is_anonymous    INTEGER NOT NULL DEFAULT 1,
  current_streak  INTEGER NOT NULL DEFAULT 0,
  best_score      INTEGER NOT NULL DEFAULT 0,
  last_day        INTEGER,
  created_at      INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_players_best ON players(best_score DESC) WHERE best_score > 0;

CREATE TABLE IF NOT EXISTS device_links (
  device_id   TEXT PRIMARY KEY,
  player_id   TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  created_at  INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS sessions (
  token       TEXT PRIMARY KEY,                   -- sha256(token)
  player_id   TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  created_at  INTEGER NOT NULL,
  expires_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_sessions_player ON sessions(player_id);

-- ===== runs (ONE per player per day — the composite PK IS the lock) =====
CREATE TABLE IF NOT EXISTS runs (
  day_index    INTEGER NOT NULL,
  player_id    TEXT    NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  final_score  INTEGER NOT NULL,
  base_sum     INTEGER NOT NULL,
  peak_mult    REAL    NOT NULL,
  word_count   INTEGER NOT NULL,
  banked       INTEGER NOT NULL,
  verified     INTEGER NOT NULL DEFAULT 1,
  created_at   INTEGER NOT NULL,
  PRIMARY KEY (day_index, player_id)
);
CREATE INDEX IF NOT EXISTS idx_runs_daily_score ON runs(day_index, final_score DESC);
CREATE INDEX IF NOT EXISTS idx_runs_player ON runs(player_id, day_index DESC);

CREATE TABLE IF NOT EXISTS day_stats (
  day_index    INTEGER PRIMARY KEY,
  player_count INTEGER NOT NULL DEFAULT 0,
  max_score    INTEGER NOT NULL DEFAULT 0,
  updated_at   INTEGER NOT NULL
);

-- ===== friendships (one directional row per edge; mirror on accept) =====
CREATE TABLE IF NOT EXISTS friendships (
  player_id   TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  friend_id   TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  status      TEXT NOT NULL DEFAULT 'pending',
  created_at  INTEGER NOT NULL,
  PRIMARY KEY (player_id, friend_id),
  CHECK (player_id <> friend_id)
);
CREATE INDEX IF NOT EXISTS idx_friend_owner ON friendships(player_id, status);
CREATE INDEX IF NOT EXISTS idx_friend_other ON friendships(friend_id, status);
