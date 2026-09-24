-- Per-user sync documents for records that were saved only on one device:
-- authored Connections, older News/Advertising posts, Stories, card order and pins,
-- the post-number ledger, and Personal Authority decisions.
-- These rows are not RDF authority; Belief Library and Pathway never read them.
BEGIN;
SET LOCAL lock_timeout = '5s';
CREATE TABLE IF NOT EXISTS savy.user_documents (
  user_id     TEXT NOT NULL REFERENCES savy.users(id) ON DELETE CASCADE,
  doc_key     TEXT NOT NULL CHECK (doc_key ~ '^[a-z0-9][a-z0-9-]{0,63}$'),
  entries     JSONB NOT NULL DEFAULT '{}'::jsonb,
  revision    BIGINT NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, doc_key)
);
COMMIT;
