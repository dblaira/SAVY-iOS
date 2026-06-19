import type { VercelRequest, VercelResponse } from "@vercel/node";
import { gatewayPhase } from "../../lib/content-store.js";
import { cognitoEnabled } from "../../lib/cognito-bridge.js";

export default function handler(_req: VercelRequest, res: VercelResponse) {
  res.status(200).json({
    ok: true,
    service: "savy-gateway",
    phase: gatewayPhase(),
    auth: cognitoEnabled(),
    routes: [
      "v1/entries",
      "v1/captures",
      "v1/correlations/latest",
      "v1/auth/sign-in",
      "v1/auth/sign-up",
      "v1/auth/sign-out",
    ],
  });
}
