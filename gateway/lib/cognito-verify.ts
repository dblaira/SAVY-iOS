import { createPublicKey, verify, type JsonWebKey, type KeyObject } from "node:crypto";
import type { VercelRequest, VercelResponse } from "@vercel/node";

interface Jwk extends JsonWebKey {
  kid?: string;
}

type JwksFetcher = (url: string) => Promise<{ keys?: Jwk[] }>;

const JWKS_MAX_AGE_MS = 60 * 60 * 1000;

let cache: { issuer: string; keys: Map<string, KeyObject>; fetchedAt: number } | null = null;

export function cognitoIssuer(): string | null {
  const pool = process.env.COGNITO_USER_POOL_ID?.trim();
  if (!pool) return null;
  const region = process.env.COGNITO_REGION?.trim() || pool.split("_")[0] || process.env.AWS_REGION?.trim() || "us-west-2";
  return `https://cognito-idp.${region}.amazonaws.com/${pool}`;
}

async function defaultFetcher(url: string): Promise<{ keys?: Jwk[] }> {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`JWKS request failed with ${response.status}`);
  return (await response.json()) as { keys?: Jwk[] };
}

async function signingKey(issuer: string, kid: string, fetcher: JwksFetcher, now: number): Promise<KeyObject | null> {
  const fresh = cache && cache.issuer === issuer && now - cache.fetchedAt < JWKS_MAX_AGE_MS;
  if (fresh && cache!.keys.has(kid)) return cache!.keys.get(kid)!;

  const { keys = [] } = await fetcher(`${issuer}/.well-known/jwks.json`);
  const loaded = new Map<string, KeyObject>();
  for (const jwk of keys) {
    if (jwk.kid && jwk.kty === "RSA") loaded.set(jwk.kid, createPublicKey({ key: jwk, format: "jwk" }));
  }
  cache = { issuer, keys: loaded, fetchedAt: now };
  return loaded.get(kid) ?? null;
}

function decodeSegment(segment: string): Record<string, unknown> | null {
  try {
    const value = JSON.parse(Buffer.from(segment, "base64url").toString("utf8"));
    return typeof value === "object" && value !== null ? (value as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

/** Returns the Cognito user id only for an unexpired, correctly signed access token from this pool. */
export async function verifyCognitoAccessToken(
  token: string,
  options: { issuer?: string | null; fetchJwks?: JwksFetcher; now?: number } = {}
): Promise<string | null> {
  const issuer = options.issuer === undefined ? cognitoIssuer() : options.issuer;
  if (!issuer) return null;
  const now = options.now ?? Date.now();

  const parts = token.trim().split(".");
  if (parts.length !== 3) return null;
  const [headerSegment, payloadSegment, signatureSegment] = parts;
  const header = decodeSegment(headerSegment);
  const payload = decodeSegment(payloadSegment);
  if (!header || !payload || header.alg !== "RS256" || typeof header.kid !== "string") return null;
  if (payload.iss !== issuer || payload.token_use !== "access") return null;
  if (typeof payload.exp !== "number" || payload.exp * 1000 <= now) return null;
  if (typeof payload.sub !== "string" || payload.sub.length === 0) return null;

  let key: KeyObject | null;
  try {
    key = await signingKey(issuer, header.kid, options.fetchJwks ?? defaultFetcher, now);
  } catch {
    return null;
  }
  if (!key) return null;

  const signed = new Uint8Array(Buffer.from(`${headerSegment}.${payloadSegment}`));
  const signature = new Uint8Array(Buffer.from(signatureSegment, "base64url"));
  return verify("RSA-SHA256", signed, key, signature) ? payload.sub : null;
}

export async function requireVerifiedBearerUser(req: VercelRequest, res: VercelResponse): Promise<string | null> {
  const authorization = req.headers.authorization;
  const token = authorization?.startsWith("Bearer ") ? authorization.slice("Bearer ".length) : "";
  const userId = token ? await verifyCognitoAccessToken(token) : null;
  if (!userId) {
    res.status(401).json({ error: "A valid Cognito access token is required" });
    return null;
  }
  return userId;
}

export function resetCognitoKeyCacheForTests(): void {
  cache = null;
}
