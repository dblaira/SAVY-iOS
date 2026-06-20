import type { VercelRequest, VercelResponse } from "@vercel/node";
import { cors, parseLimit, requireApiKey } from "../../../lib/http.js";
import { fetchValidatedOntologyFromRdf } from "../../../lib/aurora-bridge.js";
import { rdfStoreAvailable } from "../../../lib/rdf-store.js";

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (cors(req, res)) return;
  if (req.method !== "GET") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }
  if (!requireApiKey(req, res)) return;

  if (!rdfStoreAvailable()) {
    res.status(503).json({
      error: "Ontology RDF requires Aurora. Import validated suite triples first.",
    });
    return;
  }

  try {
    const limit = parseLimit(req.query.limit, 16);
    const rows = await fetchValidatedOntologyFromRdf(limit);
    res.setHeader("Cache-Control", "s-maxage=60, stale-while-revalidate=300");
    res.status(200).json(rows);
  } catch (error) {
    console.error("v1/rdf/ontology", error);
    res.status(500).json({ error: "Failed to load ontology from RDF" });
  }
}
