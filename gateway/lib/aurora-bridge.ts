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

const BELIEF_TRACE_SUPPORTED_BY = "https://understood.app/ontology#supportedBy";
const BELIEF_TRACE_ANTECEDENT = "https://understood.app/ontology#antecedent";
const BELIEF_TRACE_CONSEQUENT = "https://understood.app/ontology#consequent";

export async function fetchRdfTriplesForBeliefTrace(
  entryId: string,
  graphIri = DEFAULT_GRAPH_IRI
): Promise<RdfTripleRow[]> {
  const entryIri = `https://understood.app/entry/${encodeURIComponent(entryId)}`;

  return withClient(async (client) => {
    const { rows } = await client.query<{
      graph_iri: string;
      subject: string;
      predicate: string;
      object: string;
      object_is_iri: boolean;
      source_app: RdfTripleRow["sourceApp"];
    }>(
      `WITH entry_links AS (
         SELECT DISTINCT subject AS axiom_iri
         FROM savy.rdf_triples
         WHERE graph_iri = $1
           AND predicate = $2
           AND object = $3
       ),
       concept_iris AS (
         SELECT t.object AS iri
         FROM savy.rdf_triples t
         INNER JOIN entry_links e ON t.subject = e.axiom_iri
         WHERE t.graph_iri = $1
           AND t.predicate IN ($4, $5)
           AND t.object_is_iri = TRUE
       ),
       relevant AS (
         SELECT $3::text AS iri
         UNION
         SELECT axiom_iri FROM entry_links
         UNION
         SELECT iri FROM concept_iris
       )
       SELECT graph_iri, subject, predicate, object, object_is_iri, source_app
       FROM savy.rdf_triples
       WHERE graph_iri = $1
         AND (
           subject IN (SELECT iri FROM relevant)
           OR object IN (SELECT iri FROM relevant)
         )
       ORDER BY imported_at DESC, id DESC
       LIMIT 500`,
      [
        graphIri,
        BELIEF_TRACE_SUPPORTED_BY,
        entryIri,
        BELIEF_TRACE_ANTECEDENT,
        BELIEF_TRACE_CONSEQUENT,
      ]
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

export type ReminderSubtaskRow = {
  id: string;
  title: string;
  done: boolean;
  position: number;
};

export type ReminderRow = {
  id: string;
  user_id: string;
  title: string;
  notes: string;
  url: string;
  image_path: string | null;
  due_date: string | null;
  due_time: string | null;
  urgent: boolean;
  repeat_rule: string;
  early_reminder: string;
  list_name: string;
  flag: boolean;
  priority: string;
  location_name: string;
  when_messaging_person: string;
  kind: string;
  end_time: string | null;
  outcome: string | null;
  effort: string | null;
  energy: string | null;
  context: string | null;
  defer_date: string | null;
  waiting_on: string | null;
  pinned: boolean;
  up_next_order: number | null;
  seeded_from_template_id: string | null;
  status: string;
  completed_at: string | null;
  created_at: string;
  updated_at: string;
  tags: string[];
  subtasks: ReminderSubtaskRow[];
};

export async function ensureSavyUser(userId: string, email?: string | null): Promise<void> {
  await withClient(async (client) => {
    await client.query(
      `INSERT INTO savy.users (id, email)
       VALUES ($1, $2)
       ON CONFLICT (id) DO UPDATE
       SET email = COALESCE(EXCLUDED.email, savy.users.email),
           updated_at = NOW()`,
      [userId, email ?? null]
    );
  });
}

export async function fetchRemindersForUser(userId: string): Promise<ReminderRow[]> {
  return withClient(async (client) => {
    const { rows } = await client.query<ReminderRow & { tags: string[] | null }>(
      `SELECT
         r.id::text,
         r.user_id,
         r.title,
         r.notes,
         r.url,
         r.image_path,
         r.due_date::text,
         r.due_time::text,
         r.urgent,
         r.repeat_rule,
         r.early_reminder,
         r.list_name,
         r.flag,
         r.priority,
         r.location_name,
         r.when_messaging_person,
         r.kind,
         r.end_time::text,
         r.outcome,
         r.effort,
         r.energy,
         r.context,
         r.defer_date::text,
         r.waiting_on,
         r.pinned,
         r.up_next_order,
         r.seeded_from_template_id,
         r.status,
         r.completed_at::text,
         r.created_at::text,
         r.updated_at::text,
         COALESCE(
           ARRAY(
             SELECT tag FROM savy.reminder_tags t
             WHERE t.reminder_id = r.id
             ORDER BY tag
           ),
           ARRAY[]::text[]
         ) AS tags
       FROM savy.reminders r
       WHERE r.user_id = $1
         AND r.status <> 'deleted'
       ORDER BY r.pinned DESC, r.up_next_order NULLS LAST, r.created_at DESC`,
      [userId]
    );

    const reminders = rows.map((row) => ({
      ...row,
      tags: row.tags ?? [],
      subtasks: [] as ReminderSubtaskRow[],
    }));

    if (reminders.length === 0) return reminders;

    const ids = reminders.map((row) => row.id);
    const { rows: subtasks } = await client.query<{
      reminder_id: string;
      id: string;
      title: string;
      done: boolean;
      position: number;
    }>(
      `SELECT reminder_id::text, id::text, title, done, position
       FROM savy.reminder_subtasks
       WHERE reminder_id = ANY($1::uuid[])
       ORDER BY position ASC`,
      [ids]
    );

    const subtasksByReminder = new Map<string, ReminderSubtaskRow[]>();
    for (const subtask of subtasks) {
      const bucket = subtasksByReminder.get(subtask.reminder_id) ?? [];
      bucket.push({
        id: subtask.id,
        title: subtask.title,
        done: subtask.done,
        position: subtask.position,
      });
      subtasksByReminder.set(subtask.reminder_id, bucket);
    }

    return reminders.map((reminder) => ({
      ...reminder,
      subtasks: subtasksByReminder.get(reminder.id) ?? [],
    }));
  });
}

export type ReminderUpsertInput = Omit<
  ReminderRow,
  "user_id" | "created_at" | "updated_at" | "tags" | "subtasks"
> & {
  tags?: string[];
  subtasks?: ReminderSubtaskRow[];
};

export async function upsertReminderForUser(
  userId: string,
  input: ReminderUpsertInput
): Promise<void> {
  await withClient(async (client) => {
    await client.query("BEGIN");
    try {
      await client.query(
        `INSERT INTO savy.reminders (
           id, user_id, title, notes, url, image_path,
           due_date, due_time, urgent, repeat_rule, early_reminder,
           list_name, flag, priority, location_name, when_messaging_person,
           kind, end_time, outcome, effort, energy, context, defer_date, waiting_on,
           pinned, up_next_order, seeded_from_template_id, status, completed_at
         ) VALUES (
           $1::uuid, $2, $3, $4, $5, $6,
           $7::date, $8::time, $9, $10, $11,
           $12, $13, $14, $15, $16,
           $17, $18::time, $19, $20, $21, $22, $23::date, $24,
           $25, $26, $27, $28, $29::timestamptz
         )
         ON CONFLICT (id) DO UPDATE SET
           title = EXCLUDED.title,
           notes = EXCLUDED.notes,
           url = EXCLUDED.url,
           image_path = COALESCE(EXCLUDED.image_path, savy.reminders.image_path),
           due_date = EXCLUDED.due_date,
           due_time = EXCLUDED.due_time,
           urgent = EXCLUDED.urgent,
           repeat_rule = EXCLUDED.repeat_rule,
           early_reminder = EXCLUDED.early_reminder,
           list_name = EXCLUDED.list_name,
           flag = EXCLUDED.flag,
           priority = EXCLUDED.priority,
           location_name = EXCLUDED.location_name,
           when_messaging_person = EXCLUDED.when_messaging_person,
           kind = EXCLUDED.kind,
           end_time = EXCLUDED.end_time,
           outcome = EXCLUDED.outcome,
           effort = EXCLUDED.effort,
           energy = EXCLUDED.energy,
           context = EXCLUDED.context,
           defer_date = EXCLUDED.defer_date,
           waiting_on = EXCLUDED.waiting_on,
           pinned = EXCLUDED.pinned,
           up_next_order = EXCLUDED.up_next_order,
           seeded_from_template_id = EXCLUDED.seeded_from_template_id,
           status = EXCLUDED.status,
           completed_at = EXCLUDED.completed_at,
           updated_at = NOW()
         WHERE savy.reminders.user_id = EXCLUDED.user_id`,
        [
          input.id,
          userId,
          input.title,
          input.notes,
          input.url,
          input.image_path,
          input.due_date,
          input.due_time,
          input.urgent,
          input.repeat_rule,
          input.early_reminder,
          input.list_name,
          input.flag,
          input.priority,
          input.location_name,
          input.when_messaging_person,
          input.kind,
          input.end_time,
          input.outcome,
          input.effort,
          input.energy,
          input.context,
          input.defer_date,
          input.waiting_on,
          input.pinned,
          input.up_next_order,
          input.seeded_from_template_id,
          input.status,
          input.completed_at,
        ]
      );

      await client.query(`DELETE FROM savy.reminder_tags WHERE reminder_id = $1::uuid`, [input.id]);
      for (const tag of input.tags ?? []) {
        const trimmed = tag.trim();
        if (!trimmed) continue;
        await client.query(
          `INSERT INTO savy.reminder_tags (reminder_id, tag) VALUES ($1::uuid, $2)`,
          [input.id, trimmed]
        );
      }

      await client.query(`DELETE FROM savy.reminder_subtasks WHERE reminder_id = $1::uuid`, [
        input.id,
      ]);
      for (const subtask of input.subtasks ?? []) {
        await client.query(
          `INSERT INTO savy.reminder_subtasks (id, reminder_id, title, done, position)
           VALUES ($1::uuid, $2::uuid, $3, $4, $5)`,
          [subtask.id, input.id, subtask.title, subtask.done, subtask.position]
        );
      }

      await client.query("COMMIT");
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    }
  });
}

export async function deleteReminderForUser(userId: string, reminderId: string): Promise<void> {
  await withClient(async (client) => {
    await client.query(
      `UPDATE savy.reminders
       SET status = 'deleted', updated_at = NOW()
       WHERE id = $1::uuid AND user_id = $2`,
      [reminderId, userId]
    );
  });
}

export async function setReminderImagePath(
  userId: string,
  reminderId: string,
  imagePath: string
): Promise<void> {
  await withClient(async (client) => {
    await client.query(
      `UPDATE savy.reminders
       SET image_path = $3, updated_at = NOW()
       WHERE id = $1::uuid AND user_id = $2`,
      [reminderId, userId, imagePath]
    );
  });
}
