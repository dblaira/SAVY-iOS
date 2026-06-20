import type { RdfImportResult, RdfTripleRow } from "./types.js";
import * as aurora from "./aurora-bridge.js";

const DEFAULT_GRAPH_IRI = "https://understood.app/graph/personal";

function usesAurora(): boolean {
  return Boolean(process.env.AURORA_HOST || process.env.DATABASE_URL);
}

export function rdfStoreAvailable(): boolean {
  return usesAurora();
}

export async function importSuiteTriples(rows: RdfTripleRow[]): Promise<RdfImportResult> {
  if (!usesAurora()) {
    throw new Error("RDF triple import requires Aurora (AURORA_HOST or DATABASE_URL)");
  }

  const graphIri = rows[0]?.graphIri ?? DEFAULT_GRAPH_IRI;
  const inserted = await aurora.importSuiteTriples(rows);
  const total = await aurora.countRdfTriples(graphIri);

  return {
    inserted,
    graphIri,
    totalRows: total,
  };
}

export async function fetchRdfTriples(options: {
  graphIri?: string;
  subject?: string;
  predicate?: string;
  limit?: number;
}): Promise<RdfTripleRow[]> {
  if (!usesAurora()) {
    throw new Error("RDF triple reads require Aurora (AURORA_HOST or DATABASE_URL)");
  }

  return aurora.fetchRdfTriples(options);
}

export async function fetchRdfTriplesForBeliefTrace(
  entryId: string,
  graphIri?: string
): Promise<RdfTripleRow[]> {
  if (!usesAurora()) {
    throw new Error("RDF triple reads require Aurora (AURORA_HOST or DATABASE_URL)");
  }

  return aurora.fetchRdfTriplesForBeliefTrace(entryId, graphIri);
}

export async function fetchRdfTripleCount(graphIri?: string): Promise<number> {
  if (!usesAurora()) {
    return 0;
  }

  return aurora.countRdfTriples(graphIri ?? DEFAULT_GRAPH_IRI);
}
