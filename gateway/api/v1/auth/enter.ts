import type { VercelRequest, VercelResponse } from "@vercel/node";
import { enterWithEmailPassword } from "../../../lib/auth-enter.js";
import { cors, requireApiKey } from "../../../lib/http.js";

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (cors(req, res)) return;
  if (req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }
  if (!requireApiKey(req, res)) return;

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
    const result = await enterWithEmailPassword(email, password);
    if (!result.ok) {
      res.status(result.status).json({
        message: result.message,
        error_code: result.error_code,
      });
      return;
    }

    res.status(200).json({
      ...result.session,
      created: result.created,
    });
  } catch (error) {
    console.error("v1/auth/enter", error);
    res.status(500).json({
      message: "Could not open your account. Try again.",
      error_code: "auth_failed",
    });
  }
}
