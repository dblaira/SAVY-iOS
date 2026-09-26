import assert from "node:assert/strict";
import { describe, it, mock } from "node:test";
import pg from "pg";
import handler, { normalizeReminderInput } from "../api/v1/reminders.js";
import { fetchRemindersForUser, upsertReminderForUser } from "../lib/aurora-bridge.js";
import { DocumentValidationError, mergeEntries, type SyncEntry } from "../lib/document-merge.js";
import { normalizeScheduleFields, ScheduleValidationError, type ReminderSchedule } from "../lib/reminder-schedule.js";

const schedule: ReminderSchedule = {
  startDate: "2026-09-26T16:00:00Z", endDate: "2026-09-26T19:00:00Z",
  isAllDay: false, timeZoneIdentifier: "America/Los_Angeles", alert: "hourly",
  travelTimeMinutes: 15, invitees: ["guest@example.test"], organizerEmail: "owner@example.test",
};
const fields = { schedule, schedule_version: 1 as const };

describe("portable Reminder Schedule", () => {
  it("keeps all portable choices and strips identifiers that only work on the source device", () => {
    assert.deepEqual(normalizeScheduleFields({
      schedule_version: 1,
      schedule: { ...schedule, calendarIdentifier: "phone-calendar", calendarEventIdentifier: "phone-event" },
    }), fields);
    assert.deepEqual(normalizeReminderInput({ id: "entry", ...fields }).schedule, schedule);
  });

  it("distinguishes legacy omission from explicit removal, including JSON serialization", () => {
    const legacy = normalizeReminderInput({ id: "legacy" });
    const cleared = normalizeReminderInput({ id: "entry", schedule: null, schedule_version: 1 });
    assert.equal(Object.hasOwn(legacy, "schedule"), false);
    assert.equal(Object.hasOwn(legacy, "schedule_version"), false);
    assert.deepEqual(normalizeScheduleFields({ schedule_version: null }), {});
    assert.equal(JSON.parse(JSON.stringify(cleared)).schedule, null);
    assert.equal(cleared.schedule_version, 1);
  });

  it("requires a known contract version and explicit Schedule opinion", () => {
    for (const input of [
      { schedule }, { schedule: null }, { schedule_version: 1 },
      { schedule, schedule_version: 0 }, { schedule, schedule_version: 2 },
      { schedule: "bad", schedule_version: 1 }, { schedule: [], schedule_version: 1 },
    ]) assert.throws(() => normalizeScheduleFields(input), ScheduleValidationError);
  });

  it("rejects invalid periods and malformed choices instead of replacing a working schedule", () => {
    for (const changes of [
      { startDate: "September 26" }, { endDate: schedule.startDate },
      { endDate: "2026-09-26T15:00:00Z" }, { endDate: "2026-02-30T20:00:00Z" },
      { startDate: "2026-09-26T16:00:00" }, { timeZoneIdentifier: "not-a-zone" },
      { isAllDay: "false" }, { alert: "every-minute" }, { travelTimeMinutes: -1 },
      { travelTimeMinutes: 2.5 }, { invitees: [17] }, { organizerEmail: 17 },
    ]) assert.throws(() => normalizeScheduleFields({ ...fields, schedule: { ...schedule, ...changes } }), ScheduleValidationError);
  });

  it("allows a bounded 24-hour Hourly window and rejects longer or all-day Hourly windows", () => {
    const exactly24 = { ...schedule, endDate: "2026-09-27T16:00:00Z" };
    assert.deepEqual(normalizeScheduleFields({ ...fields, schedule: exactly24 }).schedule, exactly24);
    for (const changes of [{ endDate: "2026-09-27T16:00:01Z" }, { isAllDay: true }]) {
      assert.throws(() => normalizeScheduleFields({ ...fields, schedule: { ...exactly24, ...changes } }), ScheduleValidationError);
    }
    assert.doesNotThrow(() => normalizeScheduleFields({
      ...fields, schedule: { ...schedule, alert: "none", isAllDay: true, endDate: "2026-09-30T16:00:00Z" },
    }));
  });

  it("preserves fractional and offset dates without changing elapsed time across DST", () => {
    const dst = { ...schedule, startDate: "2026-11-01T01:00:00.000-07:00", endDate: "2026-11-01T01:00:00.000-08:00" };
    assert.deepEqual(normalizeScheduleFields({ ...fields, schedule: dst }).schedule, dst);
  });

  it("returns a client error for invalid Schedule requests before accessing the database", async () => {
    const previous = { SAVY_API_KEY: process.env.SAVY_API_KEY, AURORA_HOST: process.env.AURORA_HOST };
    process.env.SAVY_API_KEY = "test-key";
    process.env.AURORA_HOST = "postgresql://localhost/schedule-validation-test";
    const connect = mock.method(pg.Pool.prototype, "connect", async () => { throw new Error("Database must not be called"); });
    const response = {
      statusCode: 0, body: undefined as unknown,
      status(code: number) { this.statusCode = code; return this; },
      json(body: unknown) { this.body = body; return this; },
    };
    try {
      // This route's existing auth helper reads a Cognito sub; authentication is outside this contract test.
      const token = `e30.${Buffer.from(JSON.stringify({ sub: "test-user" })).toString("base64url")}.test`;
      await handler({ method: "POST", headers: { "x-api-key": "test-key", authorization: `Bearer ${token}` },
        body: { id: "entry", ...fields, schedule: { ...schedule, isAllDay: true } } } as never, response as never);
      assert.equal(response.statusCode, 400);
      assert.match((response.body as { error: string }).error, /Hourly/);
      assert.equal(connect.mock.callCount(), 0);
    } finally {
      connect.mock.restore();
      for (const [key, value] of Object.entries(previous)) {
        if (value === undefined) delete process.env[key]; else process.env[key] = value;
      }
    }
  });

  it("writes, fetches, clears, and preserves Schedule authority at the SQL boundary", async () => {
    const previousHost = process.env.AURORA_HOST;
    process.env.AURORA_HOST = "postgresql://localhost/schedule-storage-test";
    const writes: Record<string, unknown>[] = [];
    let sqlStatement = "";
    const connection = {
      async query(sql: string, values: unknown[] = []) {
        if (sql.includes("INSERT INTO savy.reminders")) {
          sqlStatement = sql;
          const columns = sql.match(/INSERT INTO savy\.reminders \(([\s\S]*?)\) VALUES/)![1].split(",").map((column) => column.trim());
          writes.push(Object.fromEntries(columns.map((column, index) => [column, values[index]])));
        }
        if (sql.includes("FROM savy.reminders r")) {
          assert.match(sql, /r\.schedule,/);
          assert.match(sql, /r\.schedule_version,/);
          return { rows: [{ id: "entry", schedule, schedule_version: 1, tags: [] }] };
        }
        return { rows: [] };
      },
      release() {},
    };
    const connect = mock.method(pg.Pool.prototype, "connect", async () => connection);
    try {
      await upsertReminderForUser("test-user", normalizeReminderInput({ id: "entry", ...fields }));
      const [fetched] = await fetchRemindersForUser("test-user");
      assert.deepEqual(fetched.schedule, schedule);
      assert.equal(fetched.schedule_version, 1);
      await upsertReminderForUser("test-user", normalizeReminderInput({ id: "entry", schedule: null, schedule_version: 1 }));
      await upsertReminderForUser("test-user", normalizeReminderInput({ id: "entry", title: "Old phone title edit" }));
      assert.deepEqual(writes.map(({ schedule_version }) => schedule_version), [1, 1, null]);
      assert.deepEqual(JSON.parse(writes[0].schedule as string), schedule);
      assert.equal(writes[1].schedule, null);
      assert.equal(writes[2].schedule, null);
      assert.match(sqlStatement, /schedule = CASE WHEN EXCLUDED\.schedule_version = 1 THEN EXCLUDED\.schedule ELSE savy\.reminders\.schedule END/);
      assert.match(sqlStatement, /schedule_version = COALESCE\(EXCLUDED\.schedule_version, savy\.reminders\.schedule_version\)/);
      for (const column of ["due_date", "due_time", "end_time"]) {
        assert.match(sqlStatement, new RegExp(`${column} = CASE WHEN EXCLUDED\\.schedule_version IS NULL AND savy\\.reminders\\.schedule_version = 1\\s+THEN savy\\.reminders\\.${column} ELSE EXCLUDED\\.${column} END`));
      }
    } finally {
      connect.mock.restore();
      if (previousHost === undefined) delete process.env.AURORA_HOST; else process.env.AURORA_HOST = previousHost;
    }
  });
});

function connection(metadata: Record<string, unknown>, modifiedAt = 10): SyncEntry {
  return { value: { id: "connection", title: "Writing", metadata }, modifiedAt, deleted: false };
}

describe("Connection Schedule compatibility", () => {
  const storedMetadata = { title: "Phone title", schedule, scheduleSyncVersion: 1,
    dueDate: "2026-09-26T07:00:00Z", dueTime: schedule.startDate, endTime: schedule.endDate };
  const stored = { "entry:connection": connection(storedMetadata) };

  function mergedMetadata(incoming: SyncEntry): Record<string, unknown> {
    const { merged } = mergeEntries(stored, { "entry:connection": incoming }, "connections");
    return (merged["entry:connection"].value as { metadata: Record<string, unknown> }).metadata;
  }

  it("keeps the server Schedule and mirrors when an old client edits the writing", () => {
    const metadata = mergedMetadata(connection({ title: "Mac title", dueDate: "stale date" }, 11));
    assert.deepEqual(metadata, { ...storedMetadata, title: "Mac title" });
  });

  it("accepts a new Schedule and strips local EventKit identifiers", () => {
    const updated = { ...schedule, alert: "fiveMinutesBefore" };
    const metadata = mergedMetadata(connection({ scheduleSyncVersion: 1,
      schedule: { ...updated, calendarIdentifier: "mac-calendar", calendarEventIdentifier: "mac-event" } }, 11));
    assert.deepEqual(metadata.schedule, updated);
  });

  it("propagates an explicit clear encoded either as null or a nil optional", () => {
    for (const change of [{ scheduleSyncVersion: 1 }, { scheduleSyncVersion: 1, schedule: null }]) {
      const metadata = mergedMetadata(connection(change, 11));
      assert.equal(metadata.scheduleSyncVersion, 1);
      assert.equal(Object.hasOwn(metadata, "schedule"), false);
    }
  });

  it("does not resurrect a cleared Schedule or stale mirrors during an old-client edit", () => {
    const { merged } = mergeEntries({ "entry:connection": connection({ scheduleSyncVersion: 1 }) },
      { "entry:connection": connection({ title: "New writing", dueDate: "stale date" }, 11) }, "connections");
    assert.deepEqual((merged["entry:connection"].value as { metadata: unknown }).metadata,
      { title: "New writing", scheduleSyncVersion: 1 });
  });

  it("keeps first-run legacy absence distinct from a clear", () => {
    const { merged } = mergeEntries({}, { "entry:connection": connection({ title: "Legacy" }) }, "connections");
    assert.deepEqual((merged["entry:connection"].value as { metadata: unknown }).metadata, { title: "Legacy" });
  });

  it("preserves deletes, modifiedAt ordering, and other document merge behavior", () => {
    assert.deepEqual(mergedMetadata(connection({ scheduleSyncVersion: 1 }, 9)), storedMetadata);
    const deleted = { value: null, deleted: true, modifiedAt: 11 };
    assert.deepEqual(mergeEntries(stored, { "entry:connection": deleted }, "connections").merged["entry:connection"], deleted);
    const changed = connection({ title: "Unrelated document" }, 11);
    assert.deepEqual(mergeEntries(stored, { "entry:connection": changed }, "stories").merged["entry:connection"], changed);
  });

  it("rejects invalid new Schedule data on Connection documents too", () => {
    assert.throws(() => mergedMetadata(connection({ scheduleSyncVersion: 1, schedule: { ...schedule, isAllDay: true } }, 11)), DocumentValidationError);
  });
});
