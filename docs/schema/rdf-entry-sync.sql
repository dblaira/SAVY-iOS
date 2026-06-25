-- Aurora auto-sync: belief entries → savy.rdf_triples (connection projection)
-- Apply after docs/schema/rdf-triples.sql

CREATE OR REPLACE FUNCTION savy.first_display_sentence(input TEXT, max_len INTEGER DEFAULT 160)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  normalized TEXT := trim(regexp_replace(coalesce(input, ''), '\s+', ' ', 'g'));
  sentence TEXT;
BEGIN
  IF normalized = '' THEN
    RETURN '';
  END IF;

  sentence := substring(normalized FROM '^[^.!?]+[.!?]');
  IF sentence IS NULL OR trim(sentence) = '' THEN
    sentence := normalized;
  END IF;

  sentence := trim(sentence);
  IF length(sentence) > max_len THEN
    RETURN left(sentence, max_len - 1) || '…';
  END IF;

  RETURN sentence;
END;
$$;

CREATE OR REPLACE FUNCTION savy.entry_display_label(headline TEXT, content TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  h TEXT := trim(coalesce(headline, ''));
  c TEXT := trim(coalesce(content, ''));
  stem TEXT;
BEGIN
  IF h <> '' THEN
    IF h LIKE '%...' OR right(h, 1) = '…' THEN
      RETURN savy.first_display_sentence(c);
    END IF;

    stem := regexp_replace(regexp_replace(h, '\.{3}$', ''), '…$', '');
    IF c <> '' AND stem <> '' AND position(stem IN c) = 1 AND length(c) > length(h) THEN
      RETURN savy.first_display_sentence(c);
    END IF;

    RETURN h;
  END IF;

  IF c <> '' THEN
    RETURN savy.first_display_sentence(c);
  END IF;

  RETURN '';
END;
$$;

CREATE OR REPLACE FUNCTION savy.entry_iri(p_entry_id UUID)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT 'https://understood.app/entry/' || p_entry_id::text;
$$;

CREATE OR REPLACE FUNCTION savy.sync_entry_rdf_triples(p_entry_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
  e RECORD;
  subject_iri TEXT;
  label TEXT;
  conn_type TEXT;
  v_graph_iri TEXT := 'https://understood.app/graph/personal';
  inserted_count INTEGER := 0;
BEGIN
  subject_iri := savy.entry_iri(p_entry_id);

  DELETE FROM savy.rdf_triples
  WHERE source_app = 'savy'
    AND subject = subject_iri;

  SELECT *
  INTO e
  FROM savy.entries
  WHERE id = p_entry_id;

  IF NOT FOUND OR e.entry_type <> 'connection' THEN
    RETURN 0;
  END IF;

  label := savy.entry_display_label(e.headline, e.content);
  IF label = '' THEN
    RETURN 0;
  END IF;

  conn_type := coalesce(nullif(trim(e.connection_type), ''), 'personal_connection');

  INSERT INTO savy.rdf_triples (graph_iri, subject, predicate, object, object_is_iri, source_app)
  VALUES
    (v_graph_iri, subject_iri, 'http://www.w3.org/1999/02/22-rdf-syntax-ns#type', 'https://understood.app/ontology#Connection', TRUE, 'savy'),
    (v_graph_iri, subject_iri, 'https://understood.app/ontology#label', label, FALSE, 'savy'),
    (v_graph_iri, subject_iri, 'https://understood.app/ontology#connectionType', conn_type, FALSE, 'savy'),
    (v_graph_iri, subject_iri, 'https://understood.app/ontology#entryType', 'connection', FALSE, 'savy')
  ON CONFLICT (graph_iri, subject, predicate, object) DO NOTHING;

  GET DIAGNOSTICS inserted_count = ROW_COUNT;
  RETURN inserted_count;
END;
$$;

CREATE OR REPLACE FUNCTION savy.sync_all_belief_entry_rdf()
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
  entry_row RECORD;
  synced_count INTEGER := 0;
BEGIN
  FOR entry_row IN
    SELECT id
    FROM savy.entries
    WHERE entry_type = 'connection'
    ORDER BY pinned_at DESC NULLS LAST, created_at DESC
  LOOP
    PERFORM savy.sync_entry_rdf_triples(entry_row.id);
    synced_count := synced_count + 1;
  END LOOP;

  DELETE FROM savy.rdf_triples rt
  WHERE rt.source_app = 'savy'
    AND rt.subject LIKE 'https://understood.app/entry/%'
    AND NOT EXISTS (
      SELECT 1
      FROM savy.entries e
      WHERE savy.entry_iri(e.id) = rt.subject
        AND e.entry_type = 'connection'
    );

  RETURN synced_count;
END;
$$;

CREATE OR REPLACE FUNCTION savy.entries_rdf_sync_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    DELETE FROM savy.rdf_triples
    WHERE source_app = 'savy'
      AND subject = savy.entry_iri(OLD.id);
    RETURN OLD;
  END IF;

  PERFORM savy.sync_entry_rdf_triples(NEW.id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS entries_rdf_sync ON savy.entries;
CREATE TRIGGER entries_rdf_sync
  AFTER INSERT OR UPDATE OR DELETE ON savy.entries
  FOR EACH ROW
  EXECUTE FUNCTION savy.entries_rdf_sync_trigger();
