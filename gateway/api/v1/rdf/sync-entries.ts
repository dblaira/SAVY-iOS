import type { VercelRequest, VercelResponse } from "@vercel/node";
import { cors, requireGatewayOrCron } from "../../../lib/http.js";
import { syncAllAxiomRdf } from "../../../lib/rdf-axiom-sync.js";
import { syncAllBeliefEntryRdf, syncBeliefEntryRdf } from "../../../lib/rdf-entry-sync.js";
import { rdfStoreAvailable } from "../../../lib/rdf-store.js";

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (cors(req, res)) return;

  if (req.method !== "GET" && req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }
  if (!requireGatewayOrCron(req, res)) return;

  if (!rdfStoreAvailable()) {
    res.status(503).json({
      error: "Belief RDF sync requires Aurora. Set AURORA_HOST and apply docs/schema/rdf-entry-sync.sql.",
    });
    return;
  }

  const entryId = typeof req.query.entryId === "string" ? req.query.entryId.trim() : "";

  try {
    if (entryId) {
      const inserted = await syncBeliefEntryRdf(entryId);
      const axioms = await syncAllAxiomRdf();
      res.status(200).json({
        mode: "single-entry",
        entryId,
        inserted,
        axioms,
      });
      return;
    }

    const beliefs = await syncAllBeliefEntryRdf();
    const axioms = await syncAllAxiomRdf();
    res.status(200).json({
      mode: "full-graph-sync",
      beliefs,
      axioms,
    });
  } catch (error) {
    console.error("v1/rdf/sync-entries", error);
    const message = error instanceof Error ? error.message : "Belief RDF sync failed";

    if (message.includes("sync_entry_rdf_triples") || message.includes("sync_all_belief_entry_rdf")) {
      res.status(503).json({
        error: "RDF entry sync schema not ready. Apply docs/schema/rdf-entry-sync.sql to Aurora first.",
        detail: message,
      });
      return;
    }

    res.status(500).json({ error: message });
  }
}
