import type { VercelRequest, VercelResponse } from "@vercel/node";
import { cors, requireApiKey } from "../../lib/http.js";
import { cognitoEnabled, signUp } from "../../lib/cognito-bridge.js";

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (cors(req, res)) return;
  if (req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }
  if (!requireApiKey(req, res)) return;

  if (!cognitoEnabled()) {
    res.status(503).json({
      message: "Sign-up is not configured on the gateway yet.",
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
    const session = await signUp(email, password);
    res.status(200).json(session);
  } catch (error) {
    console.error("v1/auth/sign-up", error);
    const message = error instanceof Error ? error.message : "Sign up failed";
    const alreadyExists = /exists|UsernameExistsException/i.test(message);

    res.status(alreadyExists ? 409 : 400).json({
      message: alreadyExists
        ? "That account already exists. Switch to Sign In and use your password."
        : message,
      error_code: alreadyExists ? "user_already_exists" : "sign_up_failed",
      error: message,
    });
  }
}
