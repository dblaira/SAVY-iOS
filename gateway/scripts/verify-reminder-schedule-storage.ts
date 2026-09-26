/** Executes the application's actual SQL against transaction-scoped temporary tables only. */
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { mock } from "node:test";
import pg from "pg";
import { Signer } from "@aws-sdk/rds-signer";
import { normalizeReminderInput } from "../api/v1/reminders.js";
import { fetchRemindersForUser, upsertReminderForUser } from "../lib/aurora-bridge.js";

const gateway = join(dirname(fileURLToPath(import.meta.url)), "..");
try {
  for (const line of readFileSync(join(gateway, ".env.local"), "utf8").split("\n")) {
    if (!line.trim() || line.trim().startsWith("#")) continue;
    const separator = line.indexOf("=");
    if (separator < 1) continue;
    const key = line.slice(0, separator).trim();
    let value = line.slice(separator + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) value = value.slice(1, -1);
    if (!process.env[key]) process.env[key] = value;
  }
} catch (error) {
  if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
}

const host = process.env.AURORA_HOST ?? process.env.DATABASE_URL;
if (!host) throw new Error("AURORA_HOST or DATABASE_URL is required.");
const user = process.env.AURORA_USER ?? "postgres";
const region = process.env.AWS_REGION ?? "us-west-2";
const client = /^postgres(ql)?:\/\//.test(host)
  ? new pg.Client({ connectionString: host, ssl: host.includes("localhost") ? false : { rejectUnauthorized: true } })
  : new pg.Client({ host, port: 5432, user, database: process.env.AURORA_DB ?? "savy",
      password: await new Signer({ hostname: host, port: 5432, username: user, region }).getAuthToken(),
      ssl: { rejectUnauthorized: true } });

await client.connect();
try {
  await client.query("BEGIN");
  for (const table of ["reminders", "reminder_tags", "reminder_subtasks"]) {
    // PostgreSQL LIKE copies columns/defaults/checks/indexes, not foreign keys to live tables.
    await client.query(`CREATE TEMP TABLE ${table} (LIKE savy.${table} INCLUDING ALL) ON COMMIT DROP`);
  }
  const adapter = {
    async query(sql: string, values: unknown[] = []) {
      if (["BEGIN", "COMMIT", "ROLLBACK"].includes(sql)) return { rows: [] };
      const isolated = sql.replace(/savy\.(reminders|reminder_tags|reminder_subtasks)\b/g, "pg_temp.$1");
      if (/\bsavy\./.test(isolated) || !isolated.includes("pg_temp.")) throw new Error("Refusing a query outside the temporary tables.");
      return client.query(isolated, values);
    },
    release() {},
  };
  const connect = mock.method(pg.Pool.prototype, "connect", async () => adapter as never);
  try {
    const id = "7b70d715-5b92-4dd1-aeb9-5be2c51cd51a";
    const userId = "schedule-isolated-test";
    const schedule = { startDate: "2026-10-01T16:00:00Z", endDate: "2026-10-01T19:00:00Z",
      isAllDay: false, timeZoneIdentifier: "America/Los_Angeles", alert: "hourly" as const,
      travelTimeMinutes: 15, invitees: ["guest@example.test"] };
    const base = { id, title: "Schedule SQL fixture", due_date: "2026-10-01", due_time: "09:00:00", end_time: "12:00:00" };
    const read = async () => {
      const rows = await fetchRemindersForUser(userId);
      assert.equal(rows.length, 1);
      return rows[0];
    };
    await upsertReminderForUser(userId, normalizeReminderInput(base));
    assert.equal((await read()).schedule_version, null, "Old row stays unversioned for local migration");
    await upsertReminderForUser(userId, normalizeReminderInput({ ...base, schedule, schedule_version: 1 }));
    assert.deepEqual((await read()).schedule, schedule, "All choices survive PostgreSQL round trip");
    await upsertReminderForUser(userId, normalizeReminderInput({ id, title: "Older client edited the title" }));
    const afterLegacy = await read();
    assert.deepEqual(afterLegacy.schedule, schedule, "Legacy write preserves known Schedule");
    assert.equal(afterLegacy.schedule_version, 1);
    assert.equal(afterLegacy.title, "Older client edited the title");
    assert.equal(afterLegacy.due_date, base.due_date);
    assert.equal(afterLegacy.due_time, base.due_time);
    assert.equal(afterLegacy.end_time, base.end_time);
    await upsertReminderForUser(userId, normalizeReminderInput({ id, schedule: null, schedule_version: 1 }));
    const cleared = await read();
    assert.equal(cleared.schedule, null, "Explicit null clears, unlike omission");
    assert.equal(cleared.schedule_version, 1);
    assert.equal(cleared.due_date, null);
    await upsertReminderForUser(userId, normalizeReminderInput(base));
    const afterOldReappearance = await read();
    assert.equal(afterOldReappearance.schedule, null, "Legacy edit cannot resurrect cleared settings");
    assert.equal(afterOldReappearance.schedule_version, 1);
    assert.equal(afterOldReappearance.due_date, null, "Legacy edit cannot resurrect cleared timeline mirrors");
    console.log(JSON.stringify({ reminderSchedulePostgres: "verified", cases: [
      "legacy row migration", "portable field round trip", "legacy write preserves schedule and mirrors",
      "explicit clear", "old client cannot resurrect cleared schedule or mirrors",
    ], isolation: "temporary tables; outer transaction rolled back" }));
  } finally {
    connect.mock.restore();
  }
} finally {
  await client.query("ROLLBACK");
  await client.end();
}
