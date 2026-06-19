import type { VercelRequest, VercelResponse } from "@vercel/node";
import { cors, requireApiKey } from "../../../gateway/lib/http.js";
import { cognitoEnabled, signIn } from "../../../gateway/lib/cognito-bridge.js";

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (cors(req, res)) return;
  if (req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }
  if (!requireApiKey(req, res)) return;

  if (!cognitoEnabled()) {
    res.status(503).json({
      message: "Sign-in is not configured on the gateway yet.",
      error_code: "auth_unavailable",
    });
    return;
  }

  const body = (req.body ?? {}) as { email?: string; password?: string };
  const email = body.email?.trim();
  const password = body.password;

  if (!email || !password) {
    res.status(400).json({
      message: "Email and password are required.",
      error_code: "invalid_credentials",
    });
    return;
  }

  try {
    const session = await signIn(email, password);
    res.status(200).json(session);
  } catch (error) {
    console.error("v1/auth/sign-in", error);
    res.status(401).json({
      message: "Email or password did not match.",
      error_code: "invalid_credentials",
      error: error instanceof Error ? error.message : "Authentication failed",
    });
  }
}
