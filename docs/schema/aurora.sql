-- SAVY Aurora PostgreSQL schema (Aurora Serverless v2 / PostgreSQL 15+)
-- System of record for leverage content, reminders, and ontology snapshots.
-- iOS reads through the Vercel/AWS API gateway — never connects to Aurora directly.

CREATE SCHEMA IF NOT EXISTS savy;

-- ---------------------------------------------------------------------------
-- Users (Cognito sub stored as text; no Supabase auth.users dependency)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS savy.users (
  id            TEXT PRIMARY KEY,              -- Cognito sub
  email         TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------------------------------------
-- Belief library (migrated from Supabase public.entries where entry_type=connection)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS savy.entries (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          TEXT NOT NULL REFERENCES savy.users(id) ON DELETE CASCADE,
  headline         TEXT NOT NULL DEFAULT '',
  subheading       TEXT,
  content          TEXT NOT NULL DEFAULT '',
  category         TEXT NOT NULL DEFAULT 'belief',
  mood             TEXT,
  entry_type       TEXT NOT NULL DEFAULT 'connection'
    CHECK (entry_type IN ('story', 'action', 'note', 'connection')),
  connection_type  TEXT,
  pinned_at        TIMESTAMPTZ,
  surface_conditions JSONB,
  landed_count     INTEGER NOT NULL DEFAULT 0,
  snooze_count     INTEGER NOT NULL DEFAULT 0,
  snoozed_until    TIMESTAMPTZ,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_savy_entries_beliefs
  ON savy.entries (user_id, entry_type, pinned_at DESC NULLS LAST, created_at DESC)
  WHERE entry_type = 'connection';

-- ---------------------------------------------------------------------------
-- Ontology correlation snapshots (migrated from public.correlation_analyses)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS savy.correlation_analyses (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             TEXT NOT NULL REFERENCES savy.users(id) ON DELETE CASCADE,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  date_range_start    TEXT NOT NULL,
  date_range_end      TEXT NOT NULL,
  total_weeks         INTEGER NOT NULL,
  total_extractions   INTEGER NOT NULL,
  correlations        JSONB NOT NULL DEFAULT '[]',
  anomaly_weeks       JSONB NOT NULL DEFAULT '[]',
  category_stats      JSONB NOT NULL DEFAULT '[]',
  interpretation      JSONB
);

CREATE INDEX IF NOT EXISTS idx_savy_correlation_analyses_user
  ON savy.correlation_analyses (user_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- Native metadata captures (editorial shell radial menu)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS savy.metadata_entries (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       TEXT NOT NULL REFERENCES savy.users(id) ON DELETE CASCADE,
  kind          TEXT NOT NULL CHECK (kind IN ('reminder', 'action', 'calendar')),
  title         TEXT NOT NULL,
  notes         TEXT NOT NULL DEFAULT '',
  scheduled_at  TIMESTAMPTZ,
  tags          JSONB NOT NULL DEFAULT '[]',
  context       TEXT,
  priority      TEXT NOT NULL DEFAULT 'none'
    CHECK (priority IN ('none', 'low', 'medium', 'high')),
  cadence       TEXT,
  sync_state    TEXT NOT NULL DEFAULT 'pending_sync'
    CHECK (sync_state IN ('pending_sync', 'synced', 'failed')),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_savy_metadata_entries_user
  ON savy.metadata_entries (user_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- Reminders (Re_Call recall.reminders shape, SAVY-native capture)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS savy.reminders (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                 TEXT NOT NULL REFERENCES savy.users(id) ON DELETE CASCADE,
  title                   TEXT NOT NULL DEFAULT '',
  notes                   TEXT NOT NULL DEFAULT '',
  url                     TEXT NOT NULL DEFAULT '',
  image_path              TEXT,
  due_date                DATE,
  due_time                TIME,
  urgent                  BOOLEAN NOT NULL DEFAULT FALSE,
  repeat_rule             TEXT NOT NULL DEFAULT 'none'
    CHECK (repeat_rule IN ('none', 'daily', 'weekdays', 'weekly', 'monthly', 'yearly')),
  early_reminder          TEXT NOT NULL DEFAULT 'none'
    CHECK (early_reminder IN ('none', '5m', '10m', '30m', '1h', '1d')),
  list_name               TEXT NOT NULL DEFAULT 'Reminders',
  flag                    BOOLEAN NOT NULL DEFAULT FALSE,
  priority                TEXT NOT NULL DEFAULT 'none'
    CHECK (priority IN ('none', 'low', 'medium', 'high')),
  location_name           TEXT NOT NULL DEFAULT '',
  when_messaging_person   TEXT NOT NULL DEFAULT '',
  kind                    TEXT NOT NULL DEFAULT 'reminder'
    CHECK (kind IN ('reminder', 'action', 'event')),
  end_time                TIME,
  outcome                 TEXT,
  effort                  TEXT,
  energy                  TEXT,
  context                 TEXT,
  defer_date              DATE,
  waiting_on              TEXT,
  pinned                  BOOLEAN NOT NULL DEFAULT FALSE,
  up_next_order           INTEGER,
  seeded_from_template_id TEXT,
  status                  TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'completed', 'deleted')),
  completed_at            TIMESTAMPTZ,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_savy_reminders_user_status
  ON savy.reminders (user_id, status, created_at DESC);

CREATE TABLE IF NOT EXISTS savy.reminder_tags (
  reminder_id UUID NOT NULL REFERENCES savy.reminders(id) ON DELETE CASCADE,
  tag         TEXT NOT NULL,
  PRIMARY KEY (reminder_id, tag)
);

CREATE INDEX IF NOT EXISTS idx_savy_reminder_tags_tag
  ON savy.reminder_tags (tag);

CREATE TABLE IF NOT EXISTS savy.reminder_subtasks (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reminder_id UUID NOT NULL REFERENCES savy.reminders(id) ON DELETE CASCADE,
  title       TEXT NOT NULL DEFAULT '',
  done        BOOLEAN NOT NULL DEFAULT FALSE,
  position    INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_savy_reminder_subtasks_reminder
  ON savy.reminder_subtasks (reminder_id, position);

-- ---------------------------------------------------------------------------
-- Neo4j projection views (Aurora → batch export / CDC → Neo4j)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW savy.neo4j_node_properties AS
SELECT
  'User:' || u.id           AS node_id,
  'User'                    AS label,
  jsonb_build_object('id', u.id, 'email', u.email) AS properties
FROM savy.users u
UNION ALL
SELECT
  'Belief:' || e.id::text,
  'Belief',
  jsonb_build_object(
    'id', e.id::text,
    'headline', e.headline,
    'connection_type', e.connection_type,
    'pinned_at', e.pinned_at
  )
FROM savy.entries e
WHERE e.entry_type = 'connection'
UNION ALL
SELECT
  'Reminder:' || r.id::text,
  'Reminder',
  jsonb_build_object('id', r.id::text, 'title', r.title, 'status', r.status)
FROM savy.reminders r
WHERE r.status <> 'deleted';

CREATE OR REPLACE VIEW savy.neo4j_edges AS
SELECT
  'User:' || e.user_id              AS start_node_id,
  'OWNS'                            AS relationship_type,
  'Belief:' || e.id::text           AS end_node_id,
  jsonb_build_object('entry_type', e.entry_type) AS properties
FROM savy.entries e
WHERE e.entry_type = 'connection'
UNION ALL
SELECT
  'User:' || r.user_id,
  'OWNS',
  'Reminder:' || r.id::text,
  jsonb_build_object('status', r.status)
FROM savy.reminders r
WHERE r.status <> 'deleted'
UNION ALL
SELECT
  'Reminder:' || rt.reminder_id::text,
  'TAGGED',
  'Tag:' || rt.tag,
  '{}'::jsonb
FROM savy.reminder_tags rt
UNION ALL
SELECT
  'Category:' || (c->>'category_a'),
  'CORRELATES_WITH',
  'Category:' || (c->>'category_b'),
  jsonb_build_object(
    'coefficient', (c->>'coefficient')::numeric,
    'type', c->>'type',
    'lag', (c->>'lag')::integer
  )
FROM savy.correlation_analyses ca,
     LATERAL jsonb_array_elements(ca.correlations) AS c
WHERE ca.id = (
  SELECT id FROM savy.correlation_analyses
  ORDER BY created_at DESC
  LIMIT 1
);

-- ---------------------------------------------------------------------------
-- updated_at trigger
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION savy.set_updated_at() RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS entries_set_updated_at ON savy.entries;
CREATE TRIGGER entries_set_updated_at
  BEFORE UPDATE ON savy.entries
  FOR EACH ROW EXECUTE FUNCTION savy.set_updated_at();

DROP TRIGGER IF EXISTS reminders_set_updated_at ON savy.reminders;
CREATE TRIGGER reminders_set_updated_at
  BEFORE UPDATE ON savy.reminders
  FOR EACH ROW EXECUTE FUNCTION savy.set_updated_at();

DROP TRIGGER IF EXISTS metadata_entries_set_updated_at ON savy.metadata_entries;
CREATE TRIGGER metadata_entries_set_updated_at
  BEFORE UPDATE ON savy.metadata_entries
  FOR EACH ROW EXECUTE FUNCTION savy.set_updated_at();
