-- SAVY Aurora RDF triple store (Re_Call-compatible projection layer)
-- Meaning authority: OWL/Turtle at understood.app/ontology#
-- Data authority: Understood exportSuiteBundle() → suite-triples.json
-- Engine authority: Re_Call n3 + graphTrace pattern

CREATE SCHEMA IF NOT EXISTS savy;

-- ---------------------------------------------------------------------------
-- RDF prefixes (optional convenience for SPARQL / import tooling)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS savy.rdf_prefixes (
  prefix        TEXT PRIMARY KEY,
  namespace_iri TEXT NOT NULL,
  source_app    TEXT NOT NULL DEFAULT 'understood'
    CHECK (source_app IN ('understood', 'recall', 'savy')),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO savy.rdf_prefixes (prefix, namespace_iri, source_app) VALUES
  ('understood', 'https://understood.app/ontology#', 'understood'),
  ('recall',     'https://understood.app/ontology/project-recall#', 'recall'),
  ('skos',       'http://www.w3.org/2004/02/skos/core#', 'understood'),
  ('owl',        'http://www.w3.org/2002/07/owl#', 'understood'),
  ('rdf',        'http://www.w3.org/1999/02/22-rdf-syntax-ns#', 'understood'),
  ('rdfs',       'http://www.w3.org/2000/01/rdf-schema#', 'understood'),
  ('xsd',        'http://www.w3.org/2001/XMLSchema#', 'understood')
ON CONFLICT (prefix) DO NOTHING;

-- ---------------------------------------------------------------------------
-- RDF terms (named graph entities — mirrors recall.rdf_terms)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS savy.rdf_terms (
  iri           TEXT PRIMARY KEY,
  term_kind     TEXT NOT NULL DEFAULT 'resource'
    CHECK (term_kind IN ('resource', 'literal', 'blank')),
  label         TEXT,
  source_app    TEXT NOT NULL DEFAULT 'understood'
    CHECK (source_app IN ('understood', 'recall', 'savy')),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------------------------------------
-- RDF triples (full IRI rows — mirrors recall.rdf_triples)
-- Only confirmed + personal axioms and suite vocabulary belong in graph/personal.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS savy.rdf_triples (
  id            BIGSERIAL PRIMARY KEY,
  graph_iri     TEXT NOT NULL DEFAULT 'https://understood.app/graph/personal',
  subject       TEXT NOT NULL,
  predicate     TEXT NOT NULL,
  object        TEXT NOT NULL,
  object_is_iri BOOLEAN NOT NULL DEFAULT TRUE,
  source_app    TEXT NOT NULL DEFAULT 'understood'
    CHECK (source_app IN ('understood', 'recall', 'savy')),
  imported_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (graph_iri, subject, predicate, object)
);

CREATE INDEX IF NOT EXISTS idx_savy_rdf_triples_graph
  ON savy.rdf_triples (graph_iri);

CREATE INDEX IF NOT EXISTS idx_savy_rdf_triples_subject
  ON savy.rdf_triples (subject);

CREATE INDEX IF NOT EXISTS idx_savy_rdf_triples_predicate
  ON savy.rdf_triples (predicate);

CREATE INDEX IF NOT EXISTS idx_savy_rdf_triples_source_app
  ON savy.rdf_triples (source_app, imported_at DESC);

-- ---------------------------------------------------------------------------
-- Import helper: upsert triple rows from Understood suite export JSON
-- Expected payload shape matches lib/ontology/suite-export.ts RdfTripleRow[]
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION savy.import_suite_triples(rows JSONB)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
  inserted_count INTEGER := 0;
BEGIN
  INSERT INTO savy.rdf_triples (graph_iri, subject, predicate, object, object_is_iri, source_app)
  SELECT
    COALESCE(row->>'graphIri', 'https://understood.app/graph/personal'),
    row->>'subject',
    row->>'predicate',
    row->>'object',
    COALESCE((row->>'objectIsIri')::boolean, TRUE),
    COALESCE(row->>'sourceApp', 'understood')
  FROM jsonb_array_elements(rows) AS row
  ON CONFLICT (graph_iri, subject, predicate, object) DO NOTHING;

  GET DIAGNOSTICS inserted_count = ROW_COUNT;
  RETURN inserted_count;
END;
$$;

-- ---------------------------------------------------------------------------
-- Neo4j projection view (optional traversal layer over RDF edges)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW savy.neo4j_rdf_edges AS
SELECT
  subject AS start_node_id,
  regexp_replace(predicate, '^.*/([^/#]+)$', '\1') AS relationship_type,
  CASE WHEN object_is_iri THEN object ELSE NULL END AS end_node_id,
  jsonb_build_object(
    'graph_iri', graph_iri,
    'predicate', predicate,
    'literal', CASE WHEN object_is_iri THEN NULL ELSE object END,
    'source_app', source_app
  ) AS properties
FROM savy.rdf_triples
WHERE object_is_iri = TRUE
  AND predicate NOT IN (
    'http://www.w3.org/1999/02/22-rdf-syntax-ns#type',
    'http://www.w3.org/2000/01/rdf-schema#label'
  );
