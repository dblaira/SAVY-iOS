import type { VercelRequest, VercelResponse } from "@vercel/node";
import { requireBearerUser } from "../../lib/cognito-auth.js";
import { cors, requireApiKey } from "../../lib/http.js";
import type { ReminderUpsertInput } from "../../lib/reminder-store.js";
import {
  deleteUserReminder,
  fetchUserReminders,
  reminderStoreAvailable,
  upsertUserReminder,
} from "../../lib/reminder-store.js";

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (cors(req, res)) return;
  if (!requireApiKey(req, res)) return;

  const userId = requireBearerUser(req, res);
  if (!userId) return;

  if (!reminderStoreAvailable()) {
    res.status(503).json({ error: "Reminder sync requires Aurora" });
    return;
  }

  if (req.method === "GET") {
    try {
      const rows = await fetchUserReminders(userId);
      res.status(200).json(rows);
    } catch (error) {
      console.error("v1/reminders GET", error);
      res.status(500).json({ error: "Failed to load reminders" });
    }
    return;
  }

  if (req.method === "POST") {
    try {
      const body = (req.body ?? {}) as Partial<ReminderUpsertInput> & {
        email?: string;
      };
      const input = normalizeReminderInput(body);
      if (!input.id) {
        res.status(400).json({ error: "Reminder id is required" });
        return;
      }

      await upsertUserReminder(userId, input, body.email ?? null);
      res.status(200).json({ ok: true, id: input.id });
    } catch (error) {
      console.error("v1/reminders POST", error);
      res.status(500).json({ error: "Failed to save reminder" });
    }
    return;
  }

  res.status(405).json({ error: "Method not allowed" });
}

function normalizeReminderInput(body: Partial<ReminderUpsertInput>): ReminderUpsertInput {
  return {
    id: String(body.id ?? ""),
    title: String(body.title ?? ""),
    notes: String(body.notes ?? ""),
    url: String(body.url ?? ""),
    image_path: body.image_path ?? null,
    due_date: body.due_date ?? null,
    due_time: body.due_time ?? null,
    urgent: Boolean(body.urgent),
    repeat_rule: String(body.repeat_rule ?? "none"),
    early_reminder: String(body.early_reminder ?? "none"),
    list_name: String(body.list_name ?? "Reminders"),
    flag: Boolean(body.flag),
    priority: String(body.priority ?? "none"),
    location_name: String(body.location_name ?? ""),
    when_messaging_person: String(body.when_messaging_person ?? ""),
    kind: String(body.kind ?? "reminder"),
    end_time: body.end_time ?? null,
    outcome: body.outcome ?? null,
    effort: body.effort ?? null,
    energy: body.energy ?? null,
    context: body.context ?? null,
    defer_date: body.defer_date ?? null,
    waiting_on: body.waiting_on ?? null,
    pinned: Boolean(body.pinned),
    up_next_order: body.up_next_order ?? null,
    seeded_from_template_id: body.seeded_from_template_id ?? null,
    status: String(body.status ?? "active"),
    completed_at: body.completed_at ?? null,
    tags: Array.isArray(body.tags) ? body.tags.map(String) : [],
    subtasks: Array.isArray(body.subtasks)
      ? body.subtasks.map((subtask, index) => ({
          id: String(subtask.id ?? ""),
          title: String(subtask.title ?? ""),
          done: Boolean(subtask.done),
          position: Number.isFinite(subtask.position) ? Number(subtask.position) : index,
        }))
      : [],
  };
}
