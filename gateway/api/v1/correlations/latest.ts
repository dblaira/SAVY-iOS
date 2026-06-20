import type { VercelRequest, VercelResponse } from "@vercel/node";
import { cors, requireApiKey } from "../../../lib/http.js";
import { fetchLatestCorrelations } from "../../../lib/content-store.js";
import { withTimeout } from "../../../lib/timeout.js";

const CORRELATIONS_DEADLINE_MS = 12_000;

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (cors(req, res)) return;
  if (req.method !== "GET") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }
  if (!requireApiKey(req, res)) return;

  try {
    const snapshot = await withTimeout(
      fetchLatestCorrelations(),
      CORRELATIONS_DEADLINE_MS,
      "Correlations request timed out"
    );
    if (!snapshot) {
      res.status(200).json({
        total_weeks: 0,
        total_extractions: 0,
        correlations: [],
        category_stats: [],
      });
      return;
    }
    res.setHeader("Cache-Control", "s-maxage=60, stale-while-revalidate=300");
    res.status(200).json(snapshot);
  } catch (error) {
    console.error("v1/correlations/latest", error);
    res.status(500).json({ error: "Failed to load correlations" });
  }
}
