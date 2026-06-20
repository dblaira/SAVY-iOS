import type { VercelRequest, VercelResponse } from "@vercel/node";
import { requireBearerUser } from "../../lib/cognito-auth.js";
import { cors, requireApiKey } from "../../lib/http.js";
import { attachReminderImagePath, deleteUserReminder, reminderStoreAvailable } from "../../lib/reminder-store.js";

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (cors(req, res)) return;
  if (!requireApiKey(req, res)) return;

  const userId = requireBearerUser(req, res);
  if (!userId) return;

  if (!reminderStoreAvailable()) {
    res.status(503).json({ error: "Reminder sync requires Aurora" });
    return;
  }

  const reminderId = typeof req.query.id === "string" ? req.query.id.trim() : "";
  if (!reminderId) {
    res.status(400).json({ error: "Reminder id is required" });
    return;
  }

  if (req.method === "DELETE") {
    try {
      await deleteUserReminder(userId, reminderId);
      res.status(200).json({ ok: true, id: reminderId });
    } catch (error) {
      console.error("v1/reminders/[id] DELETE", error);
      res.status(500).json({ error: "Failed to delete reminder" });
    }
    return;
  }

  if (req.method === "PATCH") {
    try {
      const body = (req.body ?? {}) as { image_path?: string };
      if (!body.image_path?.trim()) {
        res.status(400).json({ error: "image_path is required" });
        return;
      }
      await attachReminderImagePath(userId, reminderId, body.image_path.trim());
      res.status(200).json({ ok: true, id: reminderId, image_path: body.image_path.trim() });
    } catch (error) {
      console.error("v1/reminders/[id] PATCH", error);
      res.status(500).json({ error: "Failed to attach reminder image" });
    }
    return;
  }

  res.status(405).json({ error: "Method not allowed" });
}
