import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { parseSuiteTripleRows } from "../lib/rdf-import.js";

const require = createRequire(join(dirname(fileURLToPath(import.meta.url)), "../package.json"));
const pg = require("pg") as typeof import("pg");
const { Signer } = require("@aws-sdk/rds-signer");

const __dirname = dirname(fileURLToPath(import.meta.url));

const fixtureCandidates = [
  join(__dirname, "../../../understood-app/fixtures/ontology/suite-triples.json"),
  join(__dirname, "../fixtures/suite-triples.json"),
];

function loadEnv(path: string) {
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
    // optional
  }
}

function resolveFixturePath(): string {
  for (const candidate of fixtureCandidates) {
    try {
      readFileSync(candidate, "utf8");
      return candidate;
    } catch {
      continue;
    }
  }

  throw new Error(
    "suite-triples.json not found. Run `npm run export:suite-rdf` in understood-app first."
  );
}

async function connectPool(): Promise<InstanceType<typeof pg.Pool>> {
  const connectionString = process.env.DATABASE_URL;
  if (connectionString?.startsWith("postgresql://")) {
    return new pg.Pool({
      connectionString,
      ssl: connectionString.includes("localhost") ? false : { rejectUnauthorized: false },
      max: 1,
    });
  }

  loadEnv(join(__dirname, "../.env.local"));

  const host = process.env.AURORA_HOST ?? process.env.DATABASE_URL;
  if (!host || host.startsWith("postgresql://")) {
    throw new Error("Set DATABASE_URL or AURORA_HOST to import suite triples into Aurora");
  }

  const user = process.env.AURORA_USER ?? "postgres";
  const database = process.env.AURORA_DB ?? "postgres";
  const region = process.env.AWS_REGION ?? "us-west-2";

  const signer = new Signer({ hostname: host, port: 5432, username: user, region });
  const token = await signer.getAuthToken();

  return new pg.Pool({
    host,
    port: 5432,
    user,
    password: token,
    database,
    ssl: { rejectUnauthorized: true },
    max: 1,
  });
}

async function main() {
  const fixturePath = resolveFixturePath();
  const rows = parseSuiteTripleRows(JSON.parse(readFileSync(fixturePath, "utf8")));
  const pool = await connectPool();

  try {
    const client = await pool.connect();
    try {
      const { rows: result } = await client.query<{ import_suite_triples: string }>(
        `SELECT savy.import_suite_triples($1::jsonb)::text AS import_suite_triples`,
        [JSON.stringify(rows)]
      );
      const inserted = Number.parseInt(result[0]?.import_suite_triples ?? "0", 10);
      const { rows: countRows } = await client.query<{ count: string }>(
        `SELECT COUNT(*)::text AS count FROM savy.rdf_triples`
      );
      const total = Number.parseInt(countRows[0]?.count ?? "0", 10);

      console.log(
        `Imported ${inserted} new triple rows from ${fixturePath}. savy.rdf_triples now has ${total} rows.`
      );
    } finally {
      client.release();
    }
  } finally {
    await pool.end();
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
