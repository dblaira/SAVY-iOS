import assert from "node:assert/strict";
import { describe, it, mock } from "node:test";
import pg from "pg";
import { normalizeReminderInput } from "../api/v1/reminders.js";
import { fetchRemindersForUser, upsertReminderForUser } from "../lib/aurora-bridge.js";

const savedFields = [
  "What question did the poll ask?\n\nWhich path should we take?",
  "Who answered, and how many?\n\nAdam and three other people.\nEvery word remains.",
  "",
];

function postInput() {
  return normalizeReminderInput({
    id: "11111111-1111-4111-8111-111111111111", kind: "post",
    post_theme_id: "audience-poll-survey-results", post_theme_name: "Audience Poll or Survey Results",
    post_answers: savedFields, post_answers_contain_questions: true,
  });
}

describe("saved Post context", () => {
  it("preserves complete editable rows, blank rows, and the format marker", () => {
    const input = postInput();
    assert.deepEqual(input.post_answers, savedFields);
    assert.equal(input.post_answers_contain_questions, true);
    assert.equal(input.post_theme_name, "Audience Poll or Survey Results");
  });

  it("leaves legacy missing fields unset and preserves explicit legacy markers", () => {
    const legacy = normalizeReminderInput({ id: "old-post", kind: "post" });
    assert.equal(legacy.post_answers, null);
    assert.equal(legacy.post_answers_contain_questions, null);
    assert.equal(legacy.post_theme_id, null);
    assert.equal(normalizeReminderInput({ post_answers: ["An old answer"], post_answers_contain_questions: false }).post_answers_contain_questions, false);
  });

  it("does not silently stringify malformed saved rows", () => {
    assert.equal(normalizeReminderInput({ post_answers: ["Question", 17] as never }).post_answers, null);
  });

  it("passes exact Post data into the database and returns it through record retrieval", async () => {
    const previousHost = process.env.AURORA_HOST;
    process.env.AURORA_HOST = "postgresql://localhost/savy-post-contract-test";
    const input = postInput();
    let persisted: Record<string, unknown> | undefined;
    let checkedRead = false;
    const connection = {
      async query(sql: string, values: unknown[] = []) {
        if (sql.includes("INSERT INTO savy.reminders")) {
          const columns = sql.match(/INSERT INTO savy\.reminders \(([\s\S]*?)\) VALUES/)![1].split(",").map((column) => column.trim());
          persisted = Object.fromEntries(columns.map((column, index) => [column, values[index]]));
          assert.deepEqual(persisted.post_answers, savedFields);
          assert.equal(persisted.post_answers_contain_questions, true);
          assert.equal(persisted.post_theme_id, input.post_theme_id);
          assert.equal(persisted.post_theme_name, input.post_theme_name);
          // Old app writes omit context, and must not erase fields the new app saved.
          assert.match(sql, /COALESCE\(EXCLUDED\.post_answers, savy\.reminders\.post_answers\)/);
          assert.match(sql, /WHEN EXCLUDED\.post_answers IS NULL THEN savy\.reminders\.post_answers_contain_questions/);
        }
        if (sql.includes("FROM savy.reminders r")) {
          for (const column of ["post_theme_id", "post_theme_name", "post_answers", "post_answers_contain_questions"]) {
            assert.ok(sql.includes(`r.${column}`), `Retrieval must select ${column}`);
          }
          checkedRead = true;
          return { rows: [{ ...persisted, tags: [] }] };
        }
        return { rows: [] };
      },
      release() {},
    };
    const connect = mock.method(pg.Pool.prototype, "connect", async () => connection);
    try {
      await upsertReminderForUser("test-user", input);
      const [loaded] = await fetchRemindersForUser("test-user");
      assert.ok(checkedRead);
      assert.deepEqual(loaded.post_answers, savedFields);
      assert.equal(loaded.post_answers_contain_questions, true);
      assert.equal(loaded.post_theme_name, input.post_theme_name);
    } finally {
      connect.mock.restore();
      if (previousHost === undefined) delete process.env.AURORA_HOST;
      else process.env.AURORA_HOST = previousHost;
    }
  });
});
