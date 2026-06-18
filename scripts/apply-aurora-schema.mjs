#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(join(dirname(fileURLToPath(import.meta.url)), "../gateway/package.json"));
const pg = require("pg");
const { Signer } = require("@aws-sdk/rds-signer");

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = join(__dirname, "..");
const envPath = join(root, "gateway/.env.local");

function loadEnv(path) {
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

loadEnv(envPath);

const host = process.env.AURORA_HOST;
const user = process.env.AURORA_USER ?? "postgres";
const database = process.env.AURORA_DB ?? "savy";
const region = process.env.AWS_REGION ?? "us-west-2";

if (!host) {
  console.error("AURORA_HOST missing from gateway/.env.local");
  process.exit(1);
}

const signer = new Signer({ hostname: host, port: 5432, username: user, region });
const token = await signer.getAuthToken();

const client = new pg.Client({
  host,
  port: 5432,
  user,
  password: token,
  database,
  ssl: { rejectUnauthorized: true },
});

const sql = readFileSync(join(root, "docs/schema/aurora.sql"), "utf8");

await client.connect();
try {
  await client.query(sql);
  console.log("Aurora schema applied.");
} finally {
  await client.end();
}
