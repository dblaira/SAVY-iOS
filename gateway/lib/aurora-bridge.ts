import pg from "pg";
import { Signer } from "@aws-sdk/rds-signer";
import type { CaptureRow, CorrelationSnapshot, EntryRow, RdfTripleRow } from "./types.js";
import { normalizeCategoryStats, normalizeCorrelations } from "./normalize.js";

const { Pool } = pg;

let pool: pg.Pool | null = null;
let poolExpiresAt = 0;

function auroraConfig() {
  const host = process.env.AURORA_HOST ?? process.env.DATABASE_URL;
  if (!host) {
    throw new Error("AURORA_HOST required for Aurora phase");
  }

  if (host.startsWith("postgresql://")) {
    return { connectionString: host, iam: false as const };
  }

  return {
    iam: true as const,
    host,
    user: process.env.AURORA_USER ?? "postgres",
    database: process.env.AURORA_DB ?? "savy",
    region: process.env.AWS_REGION ?? "us-west-2",
  };
}

async function getPool(): Promise<pg.Pool> {
  const now = Date.now();
  if (pool && now < poolExpiresAt) return pool;

  if (pool) {
    await pool.end().catch(() => undefined);
    pool = null;
  }

  const config = auroraConfig();

  if (!config.iam) {
    pool = new Pool({
      connectionString: config.connectionString,
      max: 1,
      ssl: config.connectionString.includes("localhost")
        ? false
        : { rejectUnauthorized: false },
    });
    poolExpiresAt = now + 14 * 60 * 1000;
    return pool;
  }

  const signer = new Signer({
    hostname: config.host,
    port: 5432,
    username: config.user,
    region: config.region,
  });
  const token = await signer.getAuthToken();

  pool = new Pool({
    host: config.host,
    port: 5432,
    user: config.user,
    password: token,
    database: config.database,
    max: 1,
    ssl: { rejectUnauthorized: true },
  });
  poolExpiresAt = now + 14 * 60 * 1000;
  return pool;
}

async function withClient<T>(fn: (client: pg.PoolClient) => Promise<T>): Promise<T> {
  const client = await (await getPool()).connect();
  try {
    return await fn(client);
  } finally {
    client.release();
  }
}

export async function fetchBeliefEntries(limit: number): Promise<EntryRow[]> {
  return withClient(async (client) => {
    const { rows } = await client.query<EntryRow>(
      `SELECT id::text, headline, content, connection_type, entry_type
       FROM savy.entries
       WHERE entry_type = 'connection'
       ORDER BY pinned_at DESC NULLS LAST, created_at DESC
       LIMIT $1`,
      [limit]
    );
    return rows;
  });
}

export async function fetchCaptures(limit: number): Promise<CaptureRow[]> {
  return withClient(async (client) => {
    const { rows } = await client.query<{
      id: string;
      title: string;
      notes: string;
      created_at: string | null;
    }>(
      `SELECT id::text, title, notes, created_at::text
       FROM savy.metadata_entries
       ORDER BY created_at DESC
       LIMIT $1`,
      [limit]
    );

    return rows.map((row) => ({
      id: row.id,
      title: row.title,
      meaning: row.notes,
      created_at: row.created_at,
    }));
  });
}

export async function fetchLatestCorrelations(): Promise<CorrelationSnapshot | null> {
  return withClient(async (client) => {
    const { rows } = await client.query<{
      total_weeks: number;
      total_extractions: number;
      correlations: unknown;
      category_stats: unknown;
    }>(
      `SELECT total_weeks, total_extractions, correlations, category_stats
       FROM savy.correlation_analyses
       ORDER BY created_at DESC
       LIMIT 1`
    );

    const row = rows[0];
    if (!row) return null;

    return {
      total_weeks: row.total_weeks,
      total_extractions: row.total_extractions,
      correlations: normalizeCorrelations(row.correlations),
      category_stats: normalizeCategoryStats(row.category_stats),
    };
  });
}

const DEFAULT_GRAPH_IRI = "https://understood.app/graph/personal";

export async function importSuiteTriples(rows: RdfTripleRow[]): Promise<number> {
  return withClient(async (client) => {
    const { rows: result } = await client.query<{ import_suite_triples: string }>(
      `SELECT savy.import_suite_triples($1::jsonb)::text AS import_suite_triples`,
      [JSON.stringify(rows)]
    );
    return Number.parseInt(result[0]?.import_suite_triples ?? "0", 10);
  });
}

export async function countRdfTriples(graphIri = DEFAULT_GRAPH_IRI): Promise<number> {
  return withClient(async (client) => {
    const { rows } = await client.query<{ count: string }>(
      `SELECT COUNT(*)::text AS count FROM savy.rdf_triples WHERE graph_iri = $1`,
      [graphIri]
    );
    return Number.parseInt(rows[0]?.count ?? "0", 10);
  });
}

export async function fetchRdfTriples(options: {
  graphIri?: string;
  subject?: string;
  predicate?: string;
  limit?: number;
}): Promise<RdfTripleRow[]> {
  const graphIri = options.graphIri ?? DEFAULT_GRAPH_IRI;
  const limit = Math.min(Math.max(options.limit ?? 100, 1), 500);
  const clauses = ["graph_iri = $1"];
  const params: unknown[] = [graphIri];

  if (options.subject) {
    params.push(options.subject);
    clauses.push(`subject = $${params.length}`);
  }
  if (options.predicate) {
    params.push(options.predicate);
    clauses.push(`predicate = $${params.length}`);
  }

  params.push(limit);

  return withClient(async (client) => {
    const { rows } = await client.query<{
      graph_iri: string;
      subject: string;
      predicate: string;
      object: string;
      object_is_iri: boolean;
      source_app: RdfTripleRow["sourceApp"];
    }>(
      `SELECT graph_iri, subject, predicate, object, object_is_iri, source_app
       FROM savy.rdf_triples
       WHERE ${clauses.join(" AND ")}
       ORDER BY imported_at DESC, id DESC
       LIMIT $${params.length}`,
      params
    );

    return rows.map((row) => ({
      graphIri: row.graph_iri,
      subject: row.subject,
      predicate: row.predicate,
      object: row.object,
      objectIsIri: row.object_is_iri,
      sourceApp: row.source_app,
    }));
  });
}

type BeliefEntryRow = {
  id: string;
  headline: string;
  content: string;
  connection_type: string | null;
  entry_type: string | null;
};

export async function fetchBeliefEntryById(entryId: string): Promise<BeliefEntryRow | null> {
  return withClient(async (client) => {
    const { rows } = await client.query<BeliefEntryRow>(
      `SELECT id::text, headline, content, connection_type, entry_type
       FROM savy.entries
       WHERE id = $1::uuid
       LIMIT 1`,
      [entryId]
    );
    return rows[0] ?? null;
  });
}

export async function fetchAllBeliefEntries(): Promise<BeliefEntryRow[]> {
  return withClient(async (client) => {
    const { rows } = await client.query<BeliefEntryRow>(
      `SELECT id::text, headline, content, connection_type, entry_type
       FROM savy.entries
       WHERE entry_type = 'connection'
       ORDER BY pinned_at DESC NULLS LAST, created_at DESC`
    );
    return rows;
  });
}

export async function rdfEntrySyncAvailable(): Promise<boolean> {
  return withClient(async (client) => {
    const { rows } = await client.query<{ available: boolean }>(
      `SELECT EXISTS (
         SELECT 1
         FROM pg_proc p
         JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'savy'
           AND p.proname = 'sync_entry_rdf_triples'
       ) AS available`
    );
    return Boolean(rows[0]?.available);
  });
}

export async function syncEntryRdfTriples(entryId: string): Promise<number> {
  return withClient(async (client) => {
    const { rows } = await client.query<{ sync_entry_rdf_triples: string }>(
      `SELECT savy.sync_entry_rdf_triples($1::uuid)::text AS sync_entry_rdf_triples`,
      [entryId]
    );
    return Number.parseInt(rows[0]?.sync_entry_rdf_triples ?? "0", 10);
  });
}

export async function syncAllBeliefEntryRdf(): Promise<number> {
  return withClient(async (client) => {
    const { rows } = await client.query<{ sync_all_belief_entry_rdf: string }>(
      `SELECT savy.sync_all_belief_entry_rdf()::text AS sync_all_belief_entry_rdf`
    );
    return Number.parseInt(rows[0]?.sync_all_belief_entry_rdf ?? "0", 10);
  });
}

export async function deleteEntryRdfTriples(subjectIri: string): Promise<void> {
  await withClient(async (client) => {
    await client.query(
      `DELETE FROM savy.rdf_triples
       WHERE source_app = 'savy'
         AND subject = $1`,
      [subjectIri]
    );
  });
}

export async function deleteBeliefEntryRdfTriples(): Promise<void> {
  await withClient(async (client) => {
    await client.query(
      `DELETE FROM savy.rdf_triples
       WHERE source_app = 'savy'
         AND subject LIKE 'https://understood.app/entry/%'`
    );
  });
}

export async function replaceEntryRdfTriples(
  subjectIri: string,
  rows: RdfTripleRow[]
): Promise<number> {
  return withClient(async (client) => {
    await client.query(
      `DELETE FROM savy.rdf_triples
       WHERE source_app = 'savy'
         AND subject = $1`,
      [subjectIri]
    );

    if (rows.length === 0) {
      return 0;
    }

    const { rows: result } = await client.query<{ import_suite_triples: string }>(
      `SELECT savy.import_suite_triples($1::jsonb)::text AS import_suite_triples`,
      [JSON.stringify(rows)]
    );
    return Number.parseInt(result[0]?.import_suite_triples ?? "0", 10);
  });
}

export async function deleteAxiomProjectionTriples(): Promise<void> {
  await withClient(async (client) => {
    await client.query(
      `DELETE FROM savy.rdf_triples
       WHERE source_app = 'understood'
         AND (
           subject LIKE 'https://understood.app/ontology/axiom/%'
           OR (
             subject LIKE 'https://understood.app/ontology/axiom/%'
             AND predicate = 'https://understood.app/ontology#supportedBy'
           )
         )`
    );
  });
}
