import type { BeliefEntryExportRow } from "./rdf-entry-export.js";
import { entryDisplayLabel, firstDisplaySentence } from "./rdf-entry-export.js";
import type { ExportableAxiom } from "./rdf-axiom-types.js";
import { isExportablePersonalAxiom } from "./rdf-axiom-types.js";
import type { RdfTripleRow } from "./types.js";

const PERSONAL_GRAPH_IRI = "https://understood.app/graph/personal";
const ONTOLOGY_BASE = "https://understood.app/ontology";
const UNDERSTOOD_NS = "https://understood.app/ontology#";
const RDF_TYPE = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type";
const ENTRY_BASE_IRI = "https://understood.app/entry";

export function deriveValidatedPrincipleAxiom(entry: BeliefEntryExportRow): ExportableAxiom | null {
  if (entry.entry_type !== "connection" || entry.connection_type !== "validated_principle") {
    return null;
  }

  const { antecedent, consequent, relationshipType } = deriveIfThenFromConnection(
    entry.headline,
    entry.content
  );

  return {
    id: `entry-${entry.id}`,
    antecedent,
    consequent,
    confidence: 0.75,
    status: "confirmed",
    scope: "personal",
    relationshipType,
    evidenceEntryIds: [entry.id],
    evidenceCount: 1,
    provenance: {
      source: "validated_principle_connection",
      entryId: entry.id,
    },
  };
}

export function deriveIfThenFromConnection(
  headline: string,
  content: string
): { antecedent: string; consequent: string; relationshipType: string } {
  const normalized = content.replace(/\s+/g, " ").trim();
  const sentences = normalized.split(/(?<=[.!?])\s+/).filter(Boolean);

  if (sentences.length >= 2) {
    return {
      antecedent: trimSentence(sentences[0]),
      consequent: trimSentence(sentences[1]),
      relationshipType: "causes",
    };
  }

  const label = entryDisplayLabel(headline, content);
  return {
    antecedent: label,
    consequent: "this validated principle holds in your personal graph",
    relationshipType: "supports",
  };
}

export function buildTripleRowsFromAxioms(
  axioms: ExportableAxiom[],
  options: { sourceApp?: RdfTripleRow["sourceApp"] } = {}
): RdfTripleRow[] {
  const sourceApp = options.sourceApp ?? "understood";
  const rows: RdfTripleRow[] = [];

  for (const axiom of axioms.filter(isExportablePersonalAxiom)) {
    const axiomIri = `${ONTOLOGY_BASE}/axiom/${encodeURIComponent(axiom.id)}`;
    const antecedentIri = `${ONTOLOGY_BASE}/concept/${slugify(axiom.antecedent)}`;
    const consequentIri = `${ONTOLOGY_BASE}/concept/${slugify(axiom.consequent)}`;
    const policyIri = `${ONTOLOGY_BASE}/relation/${encodeURIComponent(axiom.relationshipType)}`;
    const provenanceSource =
      typeof axiom.provenance.source === "string" ? axiom.provenance.source : "unknown";

    rows.push(
      triple(antecedentIri, RDF_TYPE, `${UNDERSTOOD_NS}Concept`, true, sourceApp),
      triple(antecedentIri, `${UNDERSTOOD_NS}label`, axiom.antecedent, false, sourceApp),
      triple(consequentIri, RDF_TYPE, `${UNDERSTOOD_NS}Concept`, true, sourceApp),
      triple(consequentIri, `${UNDERSTOOD_NS}label`, axiom.consequent, false, sourceApp),
      triple(axiomIri, RDF_TYPE, `${UNDERSTOOD_NS}Axiom`, true, sourceApp),
      triple(axiomIri, `${UNDERSTOOD_NS}axiomId`, axiom.id, false, sourceApp),
      triple(axiomIri, `${UNDERSTOOD_NS}antecedent`, antecedentIri, true, sourceApp),
      triple(axiomIri, `${UNDERSTOOD_NS}antecedentLabel`, axiom.antecedent, false, sourceApp),
      triple(axiomIri, `${UNDERSTOOD_NS}consequent`, consequentIri, true, sourceApp),
      triple(axiomIri, `${UNDERSTOOD_NS}consequentLabel`, axiom.consequent, false, sourceApp),
      triple(axiomIri, `${UNDERSTOOD_NS}relationshipPolicy`, policyIri, true, sourceApp),
      triple(axiomIri, `${UNDERSTOOD_NS}relationshipType`, axiom.relationshipType, false, sourceApp),
      triple(axiomIri, `${UNDERSTOOD_NS}confidence`, formatDecimal(axiom.confidence), false, sourceApp),
      triple(
        axiomIri,
        `${UNDERSTOOD_NS}evidenceCount`,
        String(Math.max(axiom.evidenceCount, axiom.evidenceEntryIds.length)),
        false,
        sourceApp
      ),
      triple(axiomIri, `${UNDERSTOOD_NS}status`, axiom.status, false, sourceApp),
      triple(axiomIri, `${UNDERSTOOD_NS}scope`, axiom.scope, false, sourceApp),
      triple(axiomIri, `${UNDERSTOOD_NS}provenanceSource`, provenanceSource, false, sourceApp),
      triple(policyIri, RDF_TYPE, `${UNDERSTOOD_NS}RelationPolicy`, true, sourceApp),
      triple(policyIri, `${UNDERSTOOD_NS}relationshipType`, axiom.relationshipType, false, sourceApp)
    );

    for (const entryId of [...new Set(axiom.evidenceEntryIds.filter(Boolean))]) {
      rows.push(
        triple(
          axiomIri,
          `${UNDERSTOOD_NS}supportedBy`,
          `${ENTRY_BASE_IRI}/${encodeURIComponent(entryId)}`,
          true,
          sourceApp
        )
      );
    }
  }

  return dedupeTripleRows(rows);
}

function trimSentence(value: string): string {
  return value.replace(/[.!?]+$/, "").trim();
}

function slugify(value: string): string {
  const slug = value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");

  return slug || "unnamed";
}

function formatDecimal(value: number): string {
  if (!Number.isFinite(value)) return "0";
  return String(value);
}

function triple(
  subject: string,
  predicate: string,
  object: string,
  objectIsIri: boolean,
  sourceApp: RdfTripleRow["sourceApp"]
): RdfTripleRow {
  return {
    graphIri: PERSONAL_GRAPH_IRI,
    subject,
    predicate,
    object,
    objectIsIri,
    sourceApp,
  };
}

function dedupeTripleRows(rows: RdfTripleRow[]): RdfTripleRow[] {
  const seen = new Set<string>();
  const out: RdfTripleRow[] = [];

  for (const row of rows) {
    const key = `${row.graphIri}|${row.subject}|${row.predicate}|${row.object}`;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(row);
  }

  return out;
}

export { firstDisplaySentence };
