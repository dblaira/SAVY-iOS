import type { VercelRequest, VercelResponse } from "@vercel/node";
import { cors, requireApiKey } from "../../../lib/http.js";

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (cors(req, res)) return;
  if (req.method !== "GET") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }
  if (!requireApiKey(req, res)) return;

  res.status(403).json({
    error:
      "Statistical correlations are not RDF-authoritative. Import validated ontology triples via POST /api/v1/rdf/import.",
  });
}
