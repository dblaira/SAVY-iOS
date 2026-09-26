#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import pg from "pg";
import { Signer } from "@aws-sdk/rds-signer";

const gateway = join(dirname(fileURLToPath(import.meta.url)), "..");
try {
  for (const line of readFileSync(join(gateway, ".env.local"), "utf8").split("\n")) {
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
  ? new pg.Client({ connectionString: host, ssl: host.includes("localhost") ? false : { rejectUnauthorized: true } })
  : new pg.Client({
      host, port: 5432, user, database: process.env.AURORA_DB ?? "savy",
      password: await new Signer({ hostname: host, port: 5432, username: user, region }).getAuthToken(),
      ssl: { rejectUnauthorized: true },
    });
await client.connect();
try {
  if (!process.argv.includes("--check")) {
    await client.query(readFileSync(join(gateway, "schema/reminder-schedule.sql"), "utf8"));
  }
  const { rows: columns } = await client.query(
    "SELECT column_name, data_type, is_nullable, column_default FROM information_schema.columns WHERE table_schema = 'savy' AND table_name = 'reminders' AND column_name IN ('schedule', 'schedule_version') ORDER BY column_name"
  );
  const { rows: constraints } = await client.query(
    "SELECT pg_get_constraintdef(oid) AS definition FROM pg_constraint WHERE conrelid = 'savy.reminders'::regclass AND conname = 'reminders_schedule_check'"
  );
  if (columns.length !== 2 || !columns.some((column) => column.column_name === "schedule" && column.data_type === "jsonb")
    || !columns.some((column) => column.column_name === "schedule_version" && column.data_type === "smallint")
    || columns.some((column) => column.is_nullable !== "YES" || column.column_default !== null)
    || constraints.length !== 1) throw new Error("Reminder Schedule schema verification failed.");
  console.log(JSON.stringify({ reminderScheduleSchema: "verified", columns, constraints }));
} finally {
  await client.end();
}
