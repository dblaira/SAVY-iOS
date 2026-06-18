import type { VercelRequest, VercelResponse } from "@vercel/node";
import { cors, parseLimit, requireApiKey } from "../../lib/http.js";
import { fetchCaptures } from "../../lib/content-store.js";

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (cors(req, res)) return;
  if (req.method !== "GET") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }
  if (!requireApiKey(req, res)) return;

  try {
    const limit = parseLimit(req.query.limit, 20);
    const rows = await fetchCaptures(limit);
    res.status(200).json(rows);
  } catch (error) {
    console.error("v1/captures", error);
    res.status(500).json({ error: "Failed to load captures" });
  }
}
