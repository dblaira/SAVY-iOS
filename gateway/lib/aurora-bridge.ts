import pg from "pg";
import { Signer } from "@aws-sdk/rds-signer";
import type { CaptureRow, CorrelationSnapshot, EntryRow } from "./types.js";
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
