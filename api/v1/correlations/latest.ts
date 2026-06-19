import type { VercelRequest, VercelResponse } from "@vercel/node";
import { cors, requireApiKey } from "../../../gateway/lib/http.js";
import { fetchLatestCorrelations } from "../../../gateway/lib/content-store.js";

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (cors(req, res)) return;
  if (req.method !== "GET") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }
  if (!requireApiKey(req, res)) return;

  try {
    const snapshot = await fetchLatestCorrelations();
    if (!snapshot) {
      res.status(200).json({
        total_weeks: 0,
        total_extractions: 0,
        correlations: [],
        category_stats: [],
      });
      return;
    }
    res.status(200).json(snapshot);
  } catch (error) {
    console.error("v1/correlations/latest", error);
    res.status(500).json({ error: "Failed to load correlations" });
  }
}
