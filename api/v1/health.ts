import type { VercelRequest, VercelResponse } from "@vercel/node";
import { gatewayPhase } from "../../gateway/lib/content-store.js";
import { cognitoEnabled } from "../../gateway/lib/cognito-bridge.js";

export default function handler(_req: VercelRequest, res: VercelResponse) {
  res.status(200).json({
    ok: true,
    service: "savy-gateway",
    phase: gatewayPhase(),
    auth: cognitoEnabled(),
    auth_config: {
      pool: Boolean(process.env.COGNITO_USER_POOL_ID),
      client: Boolean(process.env.COGNITO_CLIENT_ID),
      region: process.env.COGNITO_REGION ?? process.env.AWS_REGION ?? null,
    },
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
