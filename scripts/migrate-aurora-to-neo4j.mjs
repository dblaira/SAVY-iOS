#!/usr/bin/env node
/**
 * Hydrate Neo4j from Aurora projection views + latest correlation analysis.
 *
 * Usage:
 *   cd gateway && node ../scripts/migrate-aurora-to-neo4j.mjs
 */

import { createRequire } from "node:module";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const require = createRequire(join(dirname(fileURLToPath(import.meta.url)), "../gateway/package.json"));
const pg = require("pg");
const { Signer } = require("@aws-sdk/rds-signer");
const neo4j = require("neo4j-driver");

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
    console.warn(`No env file at ${path}`);
  }
}

loadEnvFile(envPath);

const {
  AURORA_HOST,
  AURORA_USER = "postgres",
  AURORA_DB = "postgres",
  AWS_REGION = "us-west-2",
  NEO4J_URI,
  NEO4J_USER = "neo4j",
  NEO4J_PASSWORD,
  SAVY_OWNER_USER_ID = "adam",
  SAVY_OWNER_EMAIL = "adam@savy.app",
} = process.env;

if (!AURORA_HOST || !NEO4J_URI || !NEO4J_PASSWORD) {
  console.error("Need AURORA_HOST, NEO4J_URI, NEO4J_PASSWORD in gateway/.env.local");
  process.exit(1);
}

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

function neo4jDatabase() {
  return process.env.NEO4J_DATABASE ?? process.env.NEO4J_USER ?? "neo4j";
}

const driver = neo4j.driver(NEO4J_URI, neo4j.auth.basic(NEO4J_USER, NEO4J_PASSWORD));
const database = neo4jDatabase();

async function migrate() {
  const pgClient = await pool.connect();
  const session = driver.session({ database });

  try {
    await session.run(
      `MERGE (u:User {id: $id})
       ON CREATE SET u.email = $email, u.created_at = datetime()
       ON MATCH SET u.email = coalesce($email, u.email)`,
      { id: SAVY_OWNER_USER_ID, email: SAVY_OWNER_EMAIL }
    );

    const { rows: beliefs } = await pgClient.query(
      `SELECT id::text, headline, connection_type, pinned_at
       FROM savy.entries
       WHERE entry_type = 'connection'`
    );

    for (const belief of beliefs) {
      await session.run(
        `MERGE (b:Belief {id: $id})
         SET b.headline = $headline,
             b.connection_type = $connection_type,
             b.pinned_at = $pinned_at
         WITH b
         MATCH (u:User {id: $user_id})
         MERGE (u)-[:OWNS]->(b)`,
        {
          id: belief.id,
          headline: belief.headline,
          connection_type: belief.connection_type,
          pinned_at: belief.pinned_at ? new Date(belief.pinned_at).toISOString() : null,
          user_id: SAVY_OWNER_USER_ID,
        }
      );
    }

    const { rows: correlationRows } = await pgClient.query(
      `SELECT correlations
       FROM savy.correlation_analyses
       ORDER BY created_at DESC
       LIMIT 1`
    );

    const correlations = correlationRows[0]?.correlations ?? [];
    let edgeCount = 0;

    for (const raw of correlations) {
      const row = typeof raw === "string" ? JSON.parse(raw) : raw;
      const categoryA = row.category_a ?? row.categoryA;
      const categoryB = row.category_b ?? row.categoryB;
      if (!categoryA || !categoryB) continue;

      await session.run(
        `MERGE (a:Category {name: $category_a})
         MERGE (b:Category {name: $category_b})
         MERGE (a)-[c:CORRELATES_WITH]->(b)
         SET c.coefficient = $coefficient,
             c.type = $type,
             c.lag = $lag,
             c.updated_at = datetime()`,
        {
          category_a: categoryA,
          category_b: categoryB,
          coefficient: Number(row.coefficient),
          type: row.type ?? "co-movement",
          lag: Number(row.lag ?? 0),
        }
      );
      edgeCount += 1;
    }

    console.log(`Neo4j hydrated: ${beliefs.length} beliefs, ${edgeCount} correlation edges.`);
  } finally {
    await session.close();
    pgClient.release();
    await pool.end();
    await driver.close();
  }
}

migrate().catch((error) => {
  console.error(error);
  process.exit(1);
});
