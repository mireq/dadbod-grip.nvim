-- seed_sqlite.sql — pathological test fixtures for dadbod-grip (SQLite).
-- Usage: sqlite3 ~/tmp/dev.db < tests/seed_sqlite.sql
--
-- Mirrors tests/seed.sql (PostgreSQL) as closely as SQLite allows.
-- Covers: CRUD, composite PKs, JSON, unicode, wide tables,
-- binary data, empty tables, type diversity, and long values.

-- Clean slate
DROP VIEW  IF EXISTS no_pk_view;
DROP TABLE IF EXISTS long_values;
DROP TABLE IF EXISTS type_zoo;
DROP TABLE IF EXISTS empty_table;
DROP TABLE IF EXISTS binary_blobs;
DROP TABLE IF EXISTS wide_table;
DROP TABLE IF EXISTS unicode_fun;
DROP TABLE IF EXISTS json_data;
DROP TABLE IF EXISTS composite_pk;
DROP TABLE IF EXISTS users;

-- ── users ────────────────────────────────────────────────────────────────
-- Normal CRUD: text, integer, timestamp, email
CREATE TABLE users (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  name       TEXT NOT NULL,
  email      TEXT UNIQUE,
  age        INTEGER,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO users (name, email, age) VALUES
  ('Alice',   'alice@example.com',   30),
  ('Bob',     'bob@example.com',     25),
  ('Charlie', 'charlie@example.com', NULL),
  ('Diana',   NULL,                  42),
  ('Eve',     'eve@example.com',     19);

-- ── no_pk_view ───────────────────────────────────────────────────────────
-- Read-only mode (no primary key)
CREATE VIEW no_pk_view AS
  SELECT name, email, age FROM users WHERE age IS NOT NULL;

-- ── composite_pk ─────────────────────────────────────────────────────────
-- Composite primary key (two columns)
CREATE TABLE composite_pk (
  tenant_id  INTEGER NOT NULL,
  user_id    INTEGER NOT NULL,
  role       TEXT DEFAULT 'member',
  active     INTEGER DEFAULT 1,
  PRIMARY KEY (tenant_id, user_id)
);

INSERT INTO composite_pk (tenant_id, user_id, role, active) VALUES
  (1, 100, 'admin',  1),
  (1, 101, 'member', 1),
  (2, 100, 'viewer', 0),
  (2, 200, 'admin',  1);

-- ── json_data ────────────────────────────────────────────────────────────
-- JSON columns with nested objects, arrays, nulls
-- SQLite stores JSON as TEXT but supports json_* functions
CREATE TABLE json_data (
  id       INTEGER PRIMARY KEY AUTOINCREMENT,
  metadata TEXT,
  config   TEXT,
  tags     TEXT
);

INSERT INTO json_data (metadata, config, tags) VALUES
  ('{"key": "value", "nested": {"deep": true}}',
   '{"theme": "dark", "notifications": {"email": true, "sms": false}}',
   '["alpha", "beta", "gamma"]'),
  (NULL,
   '{"theme": "light"}',
   '[]'),
  ('{"empty_obj": {}}',
   '{"list": [1, 2, 3], "null_val": null}',
   '["single"]'),
  ('{"special": "quotes ''and'' stuff"}',
   '{}',
   NULL);

-- ── unicode_fun ──────────────────────────────────────────────────────────
-- Emoji, CJK characters, RTL text, diacritics in cell values
CREATE TABLE unicode_fun (
  id    INTEGER PRIMARY KEY AUTOINCREMENT,
  label TEXT,
  value TEXT
);

INSERT INTO unicode_fun (label, value) VALUES
  ('emoji',      '🎉🚀💾🔥✨ Party time!'),
  ('cjk',        '日本語テスト 中文测试 한국어'),
  ('rtl',        'مرحبا بالعالم'),
  ('diacritics', 'Ñoño café résumé naïve Zürich'),
  ('mixed',      'Hello 世界 🌍 مرحبا'),
  ('math',       '∑∏∫∂∇ε → ∞'),
  ('box_draw',   '┌──┬──┐ │  │  │ └──┴──┘');

-- ── wide_table ───────────────────────────────────────────────────────────
-- 15+ columns to test horizontal scrolling/truncation
CREATE TABLE wide_table (
  id     INTEGER PRIMARY KEY AUTOINCREMENT,
  col_a  TEXT,
  col_b  TEXT,
  col_c  TEXT,
  col_d  TEXT,
  col_e  TEXT,
  col_f  TEXT,
  col_g  TEXT,
  col_h  TEXT,
  col_i  TEXT,
  col_j  TEXT,
  col_k  TEXT,
  col_l  TEXT,
  col_m  TEXT,
  col_n  TEXT,
  col_o  TEXT
);

INSERT INTO wide_table (col_a, col_b, col_c, col_d, col_e, col_f, col_g, col_h,
                        col_i, col_j, col_k, col_l, col_m, col_n, col_o) VALUES
  ('alpha', 'bravo', 'charlie', 'delta', 'echo', 'foxtrot', 'golf', 'hotel',
   'india', 'juliet', 'kilo', 'lima', 'mike', 'november', 'oscar'),
  ('papa', 'quebec', 'romeo', 'sierra', 'tango', 'uniform', 'victor', 'whiskey',
   'xray', 'yankee', 'zulu', NULL, NULL, NULL, NULL);

-- ── binary_blobs ─────────────────────────────────────────────────────────
-- BLOB column with binary data
CREATE TABLE binary_blobs (
  id   INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT,
  data BLOB
);

INSERT INTO binary_blobs (name, data) VALUES
  ('tiny',    X'48656c6c6f'),
  ('zeros',   X'0000000000'),
  ('png_hdr', X'89504e470d0a1a0a');

-- ── empty_table ──────────────────────────────────────────────────────────
-- Zero rows (tests empty state rendering)
CREATE TABLE empty_table (
  id    INTEGER PRIMARY KEY AUTOINCREMENT,
  value TEXT
);

-- ── type_zoo ─────────────────────────────────────────────────────────────
-- SQLite has dynamic typing (INTEGER, TEXT, REAL, BLOB, NULL)
-- but we use column affinities that mirror the PG schema
CREATE TABLE type_zoo (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  flag         INTEGER,
  small_num    INTEGER,
  big_num      INTEGER,
  precise_num  REAL,
  approx_num   REAL,
  day          TEXT,
  tod          TEXT,
  moment       TEXT,
  duration     TEXT,
  guid         TEXT,
  ip_addr      TEXT,
  int_list     TEXT,
  txt_list     TEXT,
  feeling      TEXT
);

INSERT INTO type_zoo (flag, small_num, big_num, precise_num, approx_num,
                      day, tod, moment, duration, guid, ip_addr,
                      int_list, txt_list, feeling) VALUES
  (1,    42,     9223372036854775807, 3.1416, 2.718,
   '2025-01-15', '14:30:00', '2025-01-15T14:30:00+00:00', '2 hours 30 minutes',
   'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', '192.168.1.1',
   '[1, 2, 3]', '["hello", "world"]', 'happy'),
  (0,    -1,     0,                   0.0001, -0.5,
   '1970-01-01', '00:00:00', '1970-01-01T00:00:00+00:00', '0 seconds',
   '00000000-0000-0000-0000-000000000000', '::1',
   '[]', '[]', 'sad'),
  (NULL, NULL,   NULL,                NULL,   NULL,
   NULL,         NULL,       NULL,                         NULL,
   NULL,                                                   NULL,
   NULL, NULL, NULL);

-- ── long_values ──────────────────────────────────────────────────────────
-- Cells with 500+ char strings, multiline text, SQL injection attempts
CREATE TABLE long_values (
  id    INTEGER PRIMARY KEY AUTOINCREMENT,
  label TEXT,
  body  TEXT
);

INSERT INTO long_values (label, body) VALUES
  ('long_string',
   'abcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghij'),
  ('multiline',
   'Line one
Line two
Line three

Line five after blank
	Tabbed line'),
  ('sql_injection',
   'Robert''); DROP TABLE users;--'),
  ('quotes_mix',
   'He said "hello" and she said ''goodbye'' and then {json: "value"}'),
  ('html_like',
   '<script>alert("xss")</script><b>bold</b>&amp;'),
  ('newlines_only',
   '


');
