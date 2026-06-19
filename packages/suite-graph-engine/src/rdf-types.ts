export type RdfTripleRow = {
  graphIri: string;
  subject: string;
  predicate: string;
  object: string;
  objectIsIri: boolean;
  sourceApp: "understood" | "recall" | "savy";
};

export type BeliefGraphTrace = {
  matchedAxiomIris: string[];
  evidenceEntryIri: string;
  paths: string[];
  triplePaths: Array<{
    axiomIri: string;
    antecedentLabel: string | null;
    consequentLabel: string | null;
    relationshipType: string | null;
    supportedBy: string;
  }>;
  rankingMethod: string;
};

export type BeliefGraphTraceResult = {
  decision: "belief-graph-match" | "connection-graph-match" | "no-graph-path";
  confidence: "high" | "low";
  entryId: string;
  graphTrace: BeliefGraphTrace | null;
  reason: string;
};
