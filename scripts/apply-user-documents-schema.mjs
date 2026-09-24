#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const require = createRequire(join(root, "gateway/package.json"));
const { Client } = require("pg");
const { Signer } = require("@aws-sdk/rds-signer");
try {
  for (const line of readFileSync(join(root, "gateway/.env.local"), "utf8").split("\n")) {
    if (!line.trim() || line.trim().startsWith("#")) continue;
    const separator = line.indexOf("=");
    if (separator < 1) continue;
    const key = line.slice(0, separator).trim();
    let value = line.slice(separator + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    if (!process.env[key]) process.env[key] = value;
  }
} catch (error) {
  if (error.code !== "ENOENT") throw error;
}

const host = process.env.AURORA_HOST ?? process.env.DATABASE_URL;
if (!host) throw new Error("AURORA_HOST or DATABASE_URL is required.");
const isURL = host.startsWith("postgresql://") || host.startsWith("postgres://");
const user = process.env.AURORA_USER ?? "postgres";
const region = process.env.AWS_REGION ?? "us-west-2";
const client = isURL
  ? new Client({ connectionString: host, ssl: { rejectUnauthorized: true } })
  : new Client({
      host, port: 5432, user, database: process.env.AURORA_DB ?? "savy",
      password: await new Signer({ hostname: host, port: 5432, username: user, region }).getAuthToken(),
      ssl: { rejectUnauthorized: true },
    });
await client.connect();
try {
  if (!process.argv.includes("--check")) {
    await client.query(readFileSync(join(root, "docs/schema/user-documents.sql"), "utf8"));
  }
  const { rows: columns } = await client.query(
    "SELECT column_name, data_type FROM information_schema.columns WHERE table_schema = 'savy' AND table_name = 'user_documents' ORDER BY ordinal_position"
  );
  const { rows: primaryKey } = await client.query(
    "SELECT pg_get_constraintdef(oid) AS definition FROM pg_constraint WHERE conrelid = 'savy.user_documents'::regclass AND contype = 'p'"
  );
  const expected = ["user_id", "doc_key", "entries", "revision", "created_at", "updated_at"];
  const names = columns.map((column) => column.column_name);
  if (expected.some((name) => !names.includes(name)) || !primaryKey.some((row) => row.definition.includes("user_id, doc_key"))) {
    throw new Error("User documents schema verification failed.");
  }
  console.log(JSON.stringify({ userDocumentsSchema: "verified", columns, primaryKey }));
} finally {
  await client.end();
}
