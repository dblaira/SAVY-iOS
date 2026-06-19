import type { RdfTripleRow } from "./types.js";

const PERSONAL_GRAPH_IRI = "https://understood.app/graph/personal";
const UNDERSTOOD_NS = "https://understood.app/ontology#";
const RDF_TYPE = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type";

export type BeliefEntryExportRow = {
  id: string;
  headline: string;
  content: string;
  connection_type: string | null;
  entry_type: string | null;
};

export function entryIriForId(entryId: string): string {
  return `https://understood.app/entry/${encodeURIComponent(entryId)}`;
}

export function entryDisplayLabel(headline: string, content: string): string {
  const trimmedHeadline = headline.trim();
  const trimmedContent = content.trim();

  if (trimmedHeadline && !isTruncatedHeadline(trimmedHeadline, trimmedContent)) {
    return trimmedHeadline;
  }

  if (trimmedContent) {
    return firstDisplaySentence(trimmedContent);
  }

  return trimmedHeadline;
}

export function isTruncatedHeadline(headline: string, content: string): boolean {
  if (headline.endsWith("...") || headline.endsWith("…")) {
    return true;
  }

  const headlineStem = headline.replace(/\.{3}$/, "").replace(/…$/, "").trim();
  if (!headlineStem || !content) {
    return false;
  }

  return content.startsWith(headlineStem) && content.length > headline.length;
}

export function firstDisplaySentence(text: string, maxLength = 160): string {
  const normalized = text.replace(/\s+/g, " ").trim();
  if (!normalized) return "";

  const sentenceMatch = normalized.match(/^[^.!?]+[.!?](?=\s|$)|^[^.!?]+$/);
  const sentence = (sentenceMatch?.[0] ?? normalized).trim();

  if (sentence.length <= maxLength) {
    return sentence;
  }

  return `${sentence.slice(0, maxLength - 1).trim()}…`;
}

export function buildTripleRowsFromBeliefEntries(entries: BeliefEntryExportRow[]): RdfTripleRow[] {
  const rows: RdfTripleRow[] = [];

  for (const entry of entries) {
    if (entry.entry_type !== "connection") continue;

    const subject = entryIriForId(entry.id);
    const label = entryDisplayLabel(entry.headline, entry.content);
    if (!label) continue;

    const connectionType = entry.connection_type?.trim() || "personal_connection";

    rows.push(
      triple(subject, RDF_TYPE, `${UNDERSTOOD_NS}Connection`, true),
      triple(subject, `${UNDERSTOOD_NS}label`, label, false),
      triple(subject, `${UNDERSTOOD_NS}connectionType`, connectionType, false),
      triple(subject, `${UNDERSTOOD_NS}entryType`, "connection", false)
    );
  }

  return dedupeTripleRows(rows);
}

function triple(
  subject: string,
  predicate: string,
  object: string,
  objectIsIri: boolean
): RdfTripleRow {
  return {
    graphIri: PERSONAL_GRAPH_IRI,
    subject,
    predicate,
    object,
    objectIsIri,
    sourceApp: "savy",
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
