import type { RdfTripleRow } from "./types.js";

export function parseSuiteTripleRows(body: unknown): RdfTripleRow[] {
  if (!Array.isArray(body)) {
    throw new Error("Request body must be a JSON array of triple rows");
  }

  return body.map((row, index) => {
    if (!row || typeof row !== "object") {
      throw new Error(`Row ${index} is not an object`);
    }

    const record = row as Record<string, unknown>;
    const subject = String(record.subject ?? "");
    const predicate = String(record.predicate ?? "");
    const object = String(record.object ?? "");

    if (!subject || !predicate || !object) {
      throw new Error(`Row ${index} missing subject, predicate, or object`);
    }

    const sourceApp = record.sourceApp;
    if (sourceApp !== "understood" && sourceApp !== "recall") {
      throw new Error(
        `Row ${index} has invalid sourceApp "${String(sourceApp)}". Only understood or recall suite exports are authoritative.`
      );
    }

    return {
      graphIri: String(record.graphIri ?? "https://understood.app/graph/personal"),
      subject,
      predicate,
      object,
      objectIsIri: Boolean(record.objectIsIri ?? true),
      sourceApp,
    };
  });
}
