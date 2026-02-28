-- seed.sql — pathological test fixtures for dadbod-grip.
-- Usage: createdb grip_test && psql grip_test < tests/seed.sql
--
-- Covers: CRUD, composite PKs, JSON, unicode, wide tables,
-- binary data, empty tables, type diversity, and long values.

BEGIN;

-- Clean slate
DROP TABLE IF EXISTS long_values CASCADE;
DROP TABLE IF EXISTS type_zoo CASCADE;
DROP TABLE IF EXISTS empty_table CASCADE;
DROP TABLE IF EXISTS binary_blobs CASCADE;
DROP TABLE IF EXISTS wide_table CASCADE;
DROP TABLE IF EXISTS unicode_fun CASCADE;
DROP TABLE IF EXISTS json_data CASCADE;
DROP TABLE IF EXISTS composite_pk CASCADE;
DROP VIEW  IF EXISTS no_pk_view CASCADE;
DROP TABLE IF EXISTS users CASCADE;
DROP TYPE  IF EXISTS mood CASCADE;

-- ── users ────────────────────────────────────────────────────────────────
-- Normal CRUD: varchar, integer, timestamp, email
CREATE TABLE users (
  id         SERIAL PRIMARY KEY,
  name       VARCHAR(100) NOT NULL,
  email      VARCHAR(255) UNIQUE,
  age        INTEGER,
  created_at TIMESTAMP DEFAULT NOW()
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
  role       VARCHAR(50) DEFAULT 'member',
  active     BOOLEAN DEFAULT TRUE,
  PRIMARY KEY (tenant_id, user_id)
);

INSERT INTO composite_pk (tenant_id, user_id, role, active) VALUES
  (1, 100, 'admin',  TRUE),
  (1, 101, 'member', TRUE),
  (2, 100, 'viewer', FALSE),
  (2, 200, 'admin',  TRUE);

-- ── json_data ────────────────────────────────────────────────────────────
-- json and jsonb columns with nested objects, arrays, nulls
CREATE TABLE json_data (
  id       SERIAL PRIMARY KEY,
  metadata JSON,
  config   JSONB,
  tags     JSONB
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
  id    SERIAL PRIMARY KEY,
  label VARCHAR(200),
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
  id     SERIAL PRIMARY KEY,
  col_a  VARCHAR(30),
  col_b  VARCHAR(30),
  col_c  VARCHAR(30),
  col_d  VARCHAR(30),
  col_e  VARCHAR(30),
  col_f  VARCHAR(30),
  col_g  VARCHAR(30),
  col_h  VARCHAR(30),
  col_i  VARCHAR(30),
  col_j  VARCHAR(30),
  col_k  VARCHAR(30),
  col_l  VARCHAR(30),
  col_m  VARCHAR(30),
  col_n  VARCHAR(30),
  col_o  VARCHAR(30)
);

INSERT INTO wide_table (col_a, col_b, col_c, col_d, col_e, col_f, col_g, col_h,
                        col_i, col_j, col_k, col_l, col_m, col_n, col_o) VALUES
  ('alpha', 'bravo', 'charlie', 'delta', 'echo', 'foxtrot', 'golf', 'hotel',
   'india', 'juliet', 'kilo', 'lima', 'mike', 'november', 'oscar'),
  ('papa', 'quebec', 'romeo', 'sierra', 'tango', 'uniform', 'victor', 'whiskey',
   'xray', 'yankee', 'zulu', NULL, NULL, NULL, NULL);

-- ── binary_blobs ─────────────────────────────────────────────────────────
-- bytea column with binary data
CREATE TABLE binary_blobs (
  id   SERIAL PRIMARY KEY,
  name VARCHAR(50),
  data BYTEA
);

INSERT INTO binary_blobs (name, data) VALUES
  ('tiny',    '\x48656c6c6f'),
  ('zeros',   '\x0000000000'),
  ('png_hdr', '\x89504e470d0a1a0a');

-- ── empty_table ──────────────────────────────────────────────────────────
-- Zero rows (tests empty state rendering)
CREATE TABLE empty_table (
  id    SERIAL PRIMARY KEY,
  value TEXT
);

-- ── type_zoo ─────────────────────────────────────────────────────────────
-- boolean, integer, bigint, numeric, real, date, time, timestamptz,
-- interval, uuid, inet, array, enum
CREATE TYPE mood AS ENUM ('happy', 'sad', 'neutral');

CREATE TABLE type_zoo (
  id           SERIAL PRIMARY KEY,
  flag         BOOLEAN,
  small_num    INTEGER,
  big_num      BIGINT,
  precise_num  NUMERIC(10,4),
  approx_num   REAL,
  day          DATE,
  tod          TIME,
  moment       TIMESTAMPTZ,
  duration     INTERVAL,
  guid         UUID,
  ip_addr      INET,
  int_list     INTEGER[],
  txt_list     TEXT[],
  feeling      mood
);

INSERT INTO type_zoo (flag, small_num, big_num, precise_num, approx_num,
                      day, tod, moment, duration, guid, ip_addr,
                      int_list, txt_list, feeling) VALUES
  (TRUE,  42,     9223372036854775807, 3.1416, 2.718,
   '2025-01-15', '14:30:00', '2025-01-15 14:30:00+00', '2 hours 30 minutes',
   'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', '192.168.1.1',
   '{1, 2, 3}', '{"hello", "world"}', 'happy'),
  (FALSE, -1,     0,                   0.0001, -0.5,
   '1970-01-01', '00:00:00', '1970-01-01 00:00:00+00', '0 seconds',
   '00000000-0000-0000-0000-000000000000', '::1',
   '{}', '{}', 'sad'),
  (NULL,  NULL,   NULL,                NULL,   NULL,
   NULL,         NULL,       NULL,                      NULL,
   NULL,                                                NULL,
   NULL, NULL, NULL);

-- ── long_values ──────────────────────────────────────────────────────────
-- Cells with 500+ char strings, multiline text, SQL injection attempts
CREATE TABLE long_values (
  id    SERIAL PRIMARY KEY,
  label VARCHAR(50),
  body  TEXT
);

INSERT INTO long_values (label, body) VALUES
  ('long_string',
   repeat('abcdefghij', 60)),
  ('multiline',
   E'Line one\nLine two\nLine three\n\nLine five after blank\n\tTabbed line'),
  ('sql_injection',
   E'Robert''); DROP TABLE users;--'),
  ('quotes_mix',
   E'He said "hello" and she said ''goodbye'' and then {json: "value"}'),
  ('html_like',
   '<script>alert("xss")</script><b>bold</b>&amp;'),
  ('newlines_only',
   E'\n\n\n');

COMMIT;
