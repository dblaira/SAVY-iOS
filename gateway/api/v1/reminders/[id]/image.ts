import type { VercelRequest, VercelResponse } from "@vercel/node";
import { requireBearerUser } from "../../../lib/cognito-auth.js";
import { cors, requireApiKey } from "../../../lib/http.js";
import { uploadReminderImage } from "../../../lib/reminder-images.js";
import { attachReminderImagePath, reminderStoreAvailable } from "../../../lib/reminder-store.js";

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (cors(req, res)) return;
  if (!requireApiKey(req, res)) return;

  const userId = requireBearerUser(req, res);
  if (!userId) return;

  if (!reminderStoreAvailable()) {
    res.status(503).json({ error: "Reminder sync requires Aurora" });
    return;
  }

  if (req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }

  const reminderId = typeof req.query.id === "string" ? req.query.id.trim() : "";
  if (!reminderId) {
    res.status(400).json({ error: "Reminder id is required" });
    return;
  }

  const body = (req.body ?? {}) as { image_base64?: string; content_type?: string };
  const encoded = body.image_base64?.trim();
  if (!encoded) {
    res.status(400).json({ error: "image_base64 is required" });
    return;
  }

  try {
    const bytes = Buffer.from(encoded, "base64");
    if (bytes.length === 0) {
      res.status(400).json({ error: "image_base64 decoded to empty payload" });
      return;
    }

    const imagePath = await uploadReminderImage(
      userId,
      reminderId,
      bytes,
      body.content_type?.trim() || "image/jpeg"
    );
    await attachReminderImagePath(userId, reminderId, imagePath);
    res.status(200).json({ ok: true, id: reminderId, image_path: imagePath });
  } catch (error) {
    console.error("v1/reminders/[id]/image POST", error);
    const message = error instanceof Error ? error.message : "Failed to upload reminder image";
    const status = message.includes("SAVY_CAPTURES_BUCKET") ? 503 : 500;
    res.status(status).json({ error: message });
  }
}
