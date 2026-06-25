import * as aurora from "./aurora-bridge.js";
import {
  buildTripleRowsFromAxioms,
  deriveValidatedPrincipleAxiom,
} from "./rdf-axiom-export.js";
import type { ExportableAxiom } from "./rdf-axiom-types.js";
import { fetchConfirmedPersonalAxioms, supabaseAxiomBridgeAvailable } from "./supabase-axiom-bridge.js";

export async function collectExportableAxioms(): Promise<ExportableAxiom[]> {
  const axioms: ExportableAxiom[] = [];

  if (supabaseAxiomBridgeAvailable()) {
    axioms.push(...(await fetchConfirmedPersonalAxioms()));
  }

  const entries = await aurora.fetchAllBeliefEntries();
  for (const entry of entries) {
    const derived = deriveValidatedPrincipleAxiom(entry);
    if (derived) {
      axioms.push(derived);
    }
  }

  return dedupeAxioms(axioms);
}

export async function syncAllAxiomRdf(): Promise<{
  axiomCount: number;
  inserted: number;
  totalRdfRows: number;
}> {
  const axioms = await collectExportableAxioms();
  const rows = buildTripleRowsFromAxioms(axioms);

  await aurora.deleteAxiomProjectionTriples();
  const inserted = rows.length > 0 ? await aurora.importSuiteTriples(rows) : 0;
  const totalRdfRows = await aurora.countRdfTriples();

  return {
    axiomCount: axioms.length,
    inserted,
    totalRdfRows,
  };
}

function dedupeAxioms(axioms: ExportableAxiom[]): ExportableAxiom[] {
  const byId = new Map<string, ExportableAxiom>();
  for (const axiom of axioms) {
    byId.set(axiom.id, axiom);
  }
  return [...byId.values()];
}
