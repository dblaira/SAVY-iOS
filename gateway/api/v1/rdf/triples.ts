import type { VercelRequest, VercelResponse } from "@vercel/node";
import { cors, parseLimit, requireApiKey } from "../../../lib/http.js";
import { fetchRdfTripleCount, fetchRdfTriples, rdfStoreAvailable } from "../../../lib/rdf-store.js";

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (cors(req, res)) return;

  if (req.method !== "GET") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }
  if (!requireApiKey(req, res)) return;

  if (!rdfStoreAvailable()) {
    res.status(503).json({
      error: "RDF reads require Aurora. Set AURORA_HOST or DATABASE_URL.",
      count: 0,
      triples: [],
    });
    return;
  }

  try {
    const graphIri =
      typeof req.query.graph === "string"
        ? req.query.graph
        : "https://understood.app/graph/personal";
    const subject = typeof req.query.subject === "string" ? req.query.subject : undefined;
    const predicate = typeof req.query.predicate === "string" ? req.query.predicate : undefined;
    const limit = parseLimit(req.query.limit, 100);

    const [triples, count] = await Promise.all([
      fetchRdfTriples({ graphIri, subject, predicate, limit }),
      fetchRdfTripleCount(graphIri),
    ]);

    res.status(200).json({ graphIri, count, triples });
  } catch (error) {
    console.error("v1/rdf/triples", error);
    res.status(500).json({ error: "Failed to load RDF triples" });
  }
}
