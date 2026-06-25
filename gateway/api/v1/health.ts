import type { VercelRequest, VercelResponse } from "@vercel/node";
import { gatewayPhase } from "../../lib/content-store.js";
import { cognitoEnabled } from "../../lib/cognito-bridge.js";

export default function handler(_req: VercelRequest, res: VercelResponse) {
  res.status(200).json({
    ok: true,
    service: "savy-gateway",
    phase: gatewayPhase(),
    auth: cognitoEnabled(),
    auth_config: {
      pool: Boolean(process.env.COGNITO_USER_POOL_ID?.trim()),
      client: Boolean(process.env.COGNITO_CLIENT_ID?.trim()),
      region:
        process.env.COGNITO_REGION?.trim() ||
        process.env.AWS_REGION?.trim() ||
        "us-west-2",
    },
    routes: [
      "v1/entries",
      "v1/captures",
      "v1/correlations/latest",
      "v1/rdf/triples",
      "v1/rdf/belief-trace",
      "v1/rdf/sync-entries",
      "v1/auth/sign-in",
      "v1/auth/sign-up",
      "v1/auth/sign-out",
      "v1/auth/enter",
    ],
  });
}
