import type { BeliefGraphTraceResult, RdfTripleRow } from "./rdf-types.js";

const UNDERSTOOD_NS = "https://understood.app/ontology#";
const ENTRY_BASE_IRI = "https://understood.app/entry/";
const PERSONAL_GRAPH_IRI = "https://understood.app/graph/personal";
const RDF_TYPE = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type";

const PREDICATE_SUPPORTED_BY = `${UNDERSTOOD_NS}supportedBy`;
const PREDICATE_ANTECEDENT_LABEL = `${UNDERSTOOD_NS}antecedentLabel`;
const PREDICATE_CONSEQUENT_LABEL = `${UNDERSTOOD_NS}consequentLabel`;
const PREDICATE_RELATIONSHIP_TYPE = `${UNDERSTOOD_NS}relationshipType`;
const PREDICATE_LABEL = `${UNDERSTOOD_NS}label`;
const PREDICATE_CONNECTION_TYPE = `${UNDERSTOOD_NS}connectionType`;
const CONNECTION_CLASS = `${UNDERSTOOD_NS}Connection`;

export function entryIriForId(entryId: string): string {
  return `${ENTRY_BASE_IRI}${encodeURIComponent(entryId)}`;
}

export function buildBeliefGraphTrace(
  entryId: string,
  triples: RdfTripleRow[],
  options: { graphIri?: string } = {}
): BeliefGraphTraceResult {
  const graphIri = options.graphIri ?? PERSONAL_GRAPH_IRI;
  const entryIri = entryIriForId(entryId);
  const inGraph = triples.filter((row) => row.graphIri === graphIri);

  const evidenceLinks = inGraph.filter(
    (row) => row.predicate === PREDICATE_SUPPORTED_BY && row.object === entryIri
  );

  if (evidenceLinks.length > 0) {
    const triplePaths = evidenceLinks.map((link) => {
      const axiomIri = link.subject;
      return {
        axiomIri,
        antecedentLabel: literalForSubject(inGraph, axiomIri, PREDICATE_ANTECEDENT_LABEL),
        consequentLabel: literalForSubject(inGraph, axiomIri, PREDICATE_CONSEQUENT_LABEL),
        relationshipType: literalForSubject(inGraph, axiomIri, PREDICATE_RELATIONSHIP_TYPE),
        supportedBy: entryIri,
      };
    });

    const paths = triplePaths.map((path) => {
      const antecedent = path.antecedentLabel ?? conceptLabelForIri(inGraph, path.axiomIri, "antecedent");
      const consequent = path.consequentLabel ?? conceptLabelForIri(inGraph, path.axiomIri, "consequent");
      const relation = path.relationshipType ?? "relates";
      return `${antecedent} → ${relation} → ${consequent}`;
    });

    return {
      decision: "belief-graph-match",
      confidence: "high",
      entryId,
      graphTrace: {
        matchedAxiomIris: triplePaths.map((path) => path.axiomIri),
        evidenceEntryIri: entryIri,
        paths,
        triplePaths,
        rankingMethod: "evidence-supportedBy-entry — deterministic personal graph only",
      },
      reason: `${triplePaths.length} confirmed axiom path(s) cite this entry as evidence.`,
    };
  }

  const connectionTrace = buildConnectionGraphTrace(entryId, entryIri, inGraph);
  if (connectionTrace) {
    return connectionTrace;
  }

  return {
    decision: "no-graph-path",
    confidence: "low",
    entryId,
    graphTrace: null,
    reason:
      "No confirmed axiom or personal connection cites this entry in the graph. Surface display-only or await export/import.",
  };
}

function buildConnectionGraphTrace(
  entryId: string,
  entryIri: string,
  inGraph: RdfTripleRow[]
): BeliefGraphTraceResult | null {
  const isConnection = inGraph.some(
    (row) => row.subject === entryIri && row.predicate === RDF_TYPE && row.object === CONNECTION_CLASS
  );
  if (!isConnection) return null;

  const label = literalForSubject(inGraph, entryIri, PREDICATE_LABEL) ?? "Personal connection";
  const connectionType =
    literalForSubject(inGraph, entryIri, PREDICATE_CONNECTION_TYPE) ?? "connection";
  const typeDisplay = formatConnectionType(connectionType);

  return {
    decision: "connection-graph-match",
    confidence: "high",
    entryId,
    graphTrace: {
      matchedAxiomIris: [entryIri],
      evidenceEntryIri: entryIri,
      paths: [`${label} → ${typeDisplay}`],
      triplePaths: [
        {
          axiomIri: entryIri,
          antecedentLabel: label,
          consequentLabel: typeDisplay,
          relationshipType: "personal connection",
          supportedBy: entryIri,
        },
      ],
      rankingMethod: "entry-as-understood:Connection in personal graph",
    },
    reason: "This belief is a formal personal connection in the suite graph.",
  };
}

function conceptLabelForIri(
  triples: RdfTripleRow[],
  axiomIri: string,
  role: "antecedent" | "consequent"
): string {
  const predicate =
    role === "antecedent" ? `${UNDERSTOOD_NS}antecedent` : `${UNDERSTOOD_NS}consequent`;
  const conceptIri = triples.find(
    (row) => row.subject === axiomIri && row.predicate === predicate && row.objectIsIri
  )?.object;
  if (!conceptIri) return `unknown ${role}`;

  return literalForSubject(triples, conceptIri, PREDICATE_LABEL) ?? `unknown ${role}`;
}

function formatConnectionType(value: string): string {
  if (value === "connection" || value === "personal_connection") {
    return "Personal Connection";
  }

  return value.replace(/_/g, " ").replace(/\b\w/g, (char) => char.toUpperCase());
}

function literalForSubject(
  triples: RdfTripleRow[],
  subject: string,
  predicate: string
): string | null {
  const row = triples.find(
    (candidate) =>
      candidate.subject === subject &&
      candidate.predicate === predicate &&
      !candidate.objectIsIri
  );
  return row?.object ?? null;
}
