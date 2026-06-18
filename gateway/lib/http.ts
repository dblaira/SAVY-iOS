import type { VercelRequest, VercelResponse } from "@vercel/node";

export function cors(req: VercelRequest, res: VercelResponse): boolean {
  if (req.method === "OPTIONS") {
    res.status(204).end();
    return true;
  }
  return false;
}

export function requireApiKey(req: VercelRequest, res: VercelResponse): boolean {
  const expected = process.env.SAVY_API_KEY;
  if (!expected) {
    res.status(500).json({ error: "SAVY_API_KEY not configured on gateway" });
    return false;
  }

  const provided = req.headers["x-api-key"];
  if (provided !== expected) {
    res.status(401).json({ error: "Invalid or missing x-api-key" });
    return false;
  }

  return true;
}

export function parseLimit(value: string | string[] | undefined, fallback = 24): number {
  const raw = Array.isArray(value) ? value[0] : value;
  const n = Number.parseInt(raw ?? "", 10);
  if (!Number.isFinite(n) || n < 1) return fallback;
  return Math.min(n, 100);
}
