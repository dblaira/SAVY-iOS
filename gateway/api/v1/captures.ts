import type { VercelRequest, VercelResponse } from "@vercel/node";
import { cors, parseLimit, requireApiKey } from "../../lib/http";

// Maps to savy.metadata_entries once Aurora is live.
// Bridge phase returns an empty list — iOS falls back to CaptureSeed.
export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (cors(req, res)) return;
  if (req.method !== "GET") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }
  if (!requireApiKey(req, res)) return;

  parseLimit(req.query.limit, 20);
  res.status(200).json([]);
}
