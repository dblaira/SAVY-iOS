import type { VercelRequest, VercelResponse } from "@vercel/node";
import { decodeJwtPayload } from "./cognito-bridge.js";

export function userIdFromAccessToken(accessToken: string): string | null {
  const token = accessToken.trim();
  if (!token) return null;

  const payload = decodeJwtPayload(token);
  const sub = payload.sub;
  return typeof sub === "string" && sub.length > 0 ? sub : null;
}

export function userIdFromRequest(req: VercelRequest): string | null {
  const authorization = req.headers.authorization;
  if (!authorization?.startsWith("Bearer ")) return null;
  return userIdFromAccessToken(authorization.slice("Bearer ".length));
}

export function requireBearerUser(req: VercelRequest, res: VercelResponse): string | null {
  const userId = userIdFromRequest(req);
  if (!userId) {
    res.status(401).json({ error: "Bearer access token required" });
    return null;
  }
  return userId;
}
