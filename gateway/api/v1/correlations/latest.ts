import type { VercelRequest, VercelResponse } from "@vercel/node";
import { cors, requireApiKey } from "../../../lib/http.js";
import { fetchLatestCorrelations } from "../../../lib/content-store.js";
import * as aurora from "../../../lib/aurora-bridge.js";
import { withTimeout } from "../../../lib/timeout.js";

const CORRELATIONS_DEADLINE_MS = 20_000;

const EMPTY_SNAPSHOT = {
  total_weeks: 0,
  total_extractions: 0,
  correlations: [],
  category_stats: [],
};

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
      res.status(200).json(EMPTY_SNAPSHOT);
      return;
    }
    res.setHeader("Cache-Control", "s-maxage=60, stale-while-revalidate=300");
    res.status(200).json(snapshot);
  } catch (error) {
    console.error("v1/correlations/latest", error);
    try {
      const fallback = await aurora.fetchLatestCorrelations();
      if (fallback) {
        res.setHeader("Cache-Control", "s-maxage=60, stale-while-revalidate=300");
        res.status(200).json(fallback);
        return;
      }
    } catch (fallbackError) {
      console.error("v1/correlations/latest aurora fallback", fallbackError);
    }
    res.status(200).json(EMPTY_SNAPSHOT);
  }
}
