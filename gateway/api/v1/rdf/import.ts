import type { VercelRequest, VercelResponse } from "@vercel/node";
import { cors, requireApiKey } from "../../../lib/http.js";
import { parseSuiteTripleRows } from "../../../lib/rdf-import.js";
import { importSuiteTriples, rdfStoreAvailable } from "../../../lib/rdf-store.js";

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (cors(req, res)) return;

  if (req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }
  if (!requireApiKey(req, res)) return;

  if (!rdfStoreAvailable()) {
    res.status(503).json({
      error: "RDF import requires Aurora. Set AURORA_HOST or DATABASE_URL and apply docs/schema/rdf-triples.sql first.",
    });
    return;
  }

  try {
    const rows = parseSuiteTripleRows(req.body);
    if (rows.length === 0) {
      res.status(400).json({ error: "No triple rows provided" });
      return;
    }

    const result = await importSuiteTriples(rows);
    res.status(200).json(result);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Import failed";
    console.error("v1/rdf/import", error);

    if (message.includes("import_suite_triples") || message.includes("rdf_triples")) {
      res.status(503).json({
        error: "RDF schema not ready. Apply docs/schema/rdf-triples.sql to Aurora first.",
        detail: message,
      });
      return;
    }

    res.status(400).json({ error: message });
  }
}
