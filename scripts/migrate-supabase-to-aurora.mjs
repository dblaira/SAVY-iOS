#!/usr/bin/env node
/**
 * One-time Supabase → Aurora migration for SAVY bridge data.
 *
 * Prerequisites:
 *   1. Aurora cluster running with docs/schema/aurora.sql applied
 *   2. gateway/.env.local with SUPABASE_*, DATABASE_URL, SAVY_OWNER_USER_ID
 *
 * Usage:
 *   cd gateway && node ../scripts/migrate-supabase-to-aurora.mjs
 */

import { createRequire } from "node:module";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const require = createRequire(join(dirname(fileURLToPath(import.meta.url)), "../gateway/package.json"));
const { createClient } = require("@supabase/supabase-js");
const pg = require("pg");
const { Signer } = require("@aws-sdk/rds-signer");

const __dirname = dirname(fileURLToPath(import.meta.url));
const envPath = join(__dirname, "../gateway/.env.local");

function loadEnvFile(path) {
  try {
    const raw = readFileSync(path, "utf8");
    for (const line of raw.split("\n")) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith("#")) continue;
      const idx = trimmed.indexOf("=");
      if (idx === -1) continue;
      const key = trimmed.slice(0, idx).trim();
      const value = trimmed.slice(idx + 1).trim();
      if (!process.env[key]) process.env[key] = value;
    }
  } catch {
    console.warn(`No env file at ${path}; using process environment only.`);
  }
}

loadEnvFile(envPath);

const {
  SUPABASE_URL,
  SUPABASE_SERVICE_ROLE_KEY,
  AURORA_HOST,
  AURORA_USER = "postgres",
  AURORA_DB = "savy",
  AWS_REGION = "us-west-2",
  SAVY_OWNER_USER_ID = "adam",
  SAVY_OWNER_EMAIL = "adam@savy.app",
} = process.env;

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  process.exit(1);
}

if (!AURORA_HOST) {
  console.error("Missing AURORA_HOST in gateway/.env.local");
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const signer = new Signer({
  hostname: AURORA_HOST,
  port: 5432,
  username: AURORA_USER,
  region: AWS_REGION,
});
const token = await signer.getAuthToken();

const pool = new pg.Pool({
  host: AURORA_HOST,
  port: 5432,
  user: AURORA_USER,
  password: token,
  database: AURORA_DB,
  ssl: { rejectUnauthorized: true },
});

async function ensureOwnerUser(client) {
  await client.query(
    `INSERT INTO savy.users (id, email)
     VALUES ($1, $2)
     ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email`,
    [SAVY_OWNER_USER_ID, SAVY_OWNER_EMAIL]
  );
}

async function migrateEntries(client) {
  const { data, error } = await supabase
    .from("entries")
    .select("*")
    .eq("entry_type", "connection");

  if (error) throw error;
  const rows = data ?? [];

  for (const row of rows) {
    await client.query(
      `INSERT INTO savy.entries (
         id, user_id, headline, subheading, content, category, mood,
         entry_type, connection_type, pinned_at, surface_conditions,
         landed_count, snooze_count, snoozed_until, created_at, updated_at
       ) VALUES (
         $1, $2, $3, $4, $5, $6, $7,
         $8, $9, $10, $11,
         $12, $13, $14, $15, $16
       )
       ON CONFLICT (id) DO UPDATE SET
         headline = EXCLUDED.headline,
         content = EXCLUDED.content,
         connection_type = EXCLUDED.connection_type,
         pinned_at = EXCLUDED.pinned_at,
         updated_at = EXCLUDED.updated_at`,
      [
        row.id,
        SAVY_OWNER_USER_ID,
        row.headline ?? "",
        row.subheading ?? null,
        row.content ?? "",
        row.category ?? "belief",
        row.mood ?? null,
        row.entry_type ?? "connection",
        row.connection_type ?? null,
        row.pinned_at ?? null,
        row.surface_conditions ?? null,
        row.landed_count ?? 0,
        row.snooze_count ?? 0,
        row.snoozed_until ?? null,
        row.created_at ?? new Date().toISOString(),
        row.updated_at ?? new Date().toISOString(),
      ]
    );
  }

  return rows.length;
}

async function migrateCorrelations(client) {
  const { data, error } = await supabase
    .from("correlation_analyses")
    .select("*")
    .order("created_at", { ascending: false });

  if (error) throw error;
  const rows = data ?? [];

  for (const row of rows) {
    await client.query(
      `INSERT INTO savy.correlation_analyses (
         id, user_id, created_at, date_range_start, date_range_end,
         total_weeks, total_extractions, correlations, anomaly_weeks,
         category_stats, interpretation
       ) VALUES (
         $1, $2, $3, $4, $5,
         $6, $7, $8::jsonb, $9::jsonb,
         $10::jsonb, $11::jsonb
       )
       ON CONFLICT (id) DO NOTHING`,
      [
        row.id,
        SAVY_OWNER_USER_ID,
        row.created_at ?? new Date().toISOString(),
        row.date_range_start ?? "",
        row.date_range_end ?? "",
        row.total_weeks ?? 0,
        row.total_extractions ?? 0,
        JSON.stringify(row.correlations ?? []),
        JSON.stringify(row.anomaly_weeks ?? []),
        JSON.stringify(row.category_stats ?? []),
        row.interpretation ? JSON.stringify(row.interpretation) : null,
      ]
    );
  }

  return rows.length;
}

async function main() {
  const client = await pool.connect();
  try {
    console.log("Ensuring owner user…");
    await ensureOwnerUser(client);

    console.log("Migrating belief entries…");
    const entryCount = await migrateEntries(client);
    console.log(`  ${entryCount} entries`);

    console.log("Migrating correlation analyses…");
    const correlationCount = await migrateCorrelations(client);
    console.log(`  ${correlationCount} analyses`);

    console.log("Done. Set DATABASE_URL on Vercel to switch gateway phase to aurora.");
  } finally {
    client.release();
    await pool.end();
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
