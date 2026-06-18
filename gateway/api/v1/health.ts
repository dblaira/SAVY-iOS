import type { VercelRequest, VercelResponse } from "@vercel/node";

export default function handler(_req: VercelRequest, res: VercelResponse) {
  res.status(200).json({
    ok: true,
    service: "savy-gateway",
    phase: "supabase-bridge",
    routes: ["v1/entries", "v1/captures", "v1/correlations/latest"],
  });
}
