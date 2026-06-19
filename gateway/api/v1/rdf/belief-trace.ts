import type { VercelRequest, VercelResponse } from "@vercel/node";
import { buildBeliefGraphTrace } from "../../../lib/belief-graph-trace.js";
import { cors, requireApiKey } from "../../../lib/http.js";
import { fetchRdfTriples, rdfStoreAvailable } from "../../../lib/rdf-store.js";

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (cors(req, res)) return;

  if (req.method !== "GET") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }
  if (!requireApiKey(req, res)) return;

  const entryId = typeof req.query.entryId === "string" ? req.query.entryId.trim() : "";
  if (!entryId) {
    res.status(400).json({ error: "entryId query parameter is required" });
    return;
  }

  if (!rdfStoreAvailable()) {
    res.status(503).json({
      error: "graphTrace requires Aurora RDF triples. Import suite export first.",
      entryId,
      decision: "no-graph-path",
      graphTrace: null,
    });
    return;
  }

  try {
    const graphIri =
      typeof req.query.graph === "string"
        ? req.query.graph
        : "https://understood.app/graph/personal";

    const triples = await fetchRdfTriples({ graphIri, limit: 500 });
    const result = buildBeliefGraphTrace(entryId, triples, { graphIri });

    res.status(200).json(result);
  } catch (error) {
    console.error("v1/rdf/belief-trace", error);
    res.status(500).json({ error: "Failed to build belief graphTrace" });
  }
}
