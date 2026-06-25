export type ExportableAxiom = {
  id: string;
  antecedent: string;
  consequent: string;
  confidence: number;
  status: "confirmed" | "candidate" | "rejected" | "retired";
  scope: "personal" | "starter_hypothesis" | "demo";
  relationshipType: string;
  evidenceEntryIds: string[];
  evidenceCount: number;
  provenance: Record<string, unknown>;
};

export function isExportablePersonalAxiom(axiom: ExportableAxiom): boolean {
  if (axiom.status !== "confirmed" || axiom.scope !== "personal") {
    return false;
  }

  return !isUnsafePlaceholderRule(axiom);
}

function isUnsafePlaceholderRule(axiom: ExportableAxiom): boolean {
  const parser = typeof axiom.provenance.parser === "string" ? axiom.provenance.parser : null;
  const antecedent = axiom.antecedent.trim();
  const consequent = axiom.consequent.trim();

  if (
    parser === "claim_as_pattern" ||
    antecedent.startsWith("Adam treats this as a reusable pattern:") ||
    consequent.toLowerCase() === "future reasoning should consider this pattern only after human confirmation"
  ) {
    return true;
  }

  return false;
}
