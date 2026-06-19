import type { VercelRequest, VercelResponse } from "@vercel/node";
import { cors, requireApiKey } from "../../../lib/http.js";
import { signOut } from "../../../lib/cognito-bridge.js";

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (cors(req, res)) return;
  if (req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }
  if (!requireApiKey(req, res)) return;

  const authHeader = req.headers.authorization;
  const token = authHeader?.startsWith("Bearer ")
    ? authHeader.slice("Bearer ".length)
    : null;

  if (!token) {
    res.status(401).json({ message: "Missing bearer token." });
    return;
  }

  try {
    await signOut(token);
    res.status(200).json({ ok: true });
  } catch (error) {
    console.error("v1/auth/sign-out", error);
    res.status(200).json({ ok: true });
  }
}
