import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { buildBeliefGraphTrace } from "../src/belief-graph-trace.js";
import type { RdfTripleRow } from "../src/rdf-types.js";

const GRAPH = "https://understood.app/graph/personal";
const NS = "https://understood.app/ontology#";
const RDF_TYPE = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type";

function row(
  subject: string,
  predicate: string,
  object: string,
  objectIsIri: boolean
): RdfTripleRow {
  return {
    graphIri: GRAPH,
    subject,
    predicate,
    object,
    objectIsIri,
    sourceApp: "understood",
  };
}

describe("buildBeliefGraphTrace", () => {
  it("returns graphTrace when an axiom supportedBy links to the entry", () => {
    const axiom = "https://understood.app/ontology/axiom/axiom-learning-affect";
    const triples: RdfTripleRow[] = [
      row(axiom, `${NS}supportedBy`, "https://understood.app/entry/entry-1", true),
      row(axiom, `${NS}antecedentLabel`, "High Learning", false),
      row(axiom, `${NS}consequentLabel`, "Higher Affect", false),
      row(axiom, `${NS}relationshipType`, "predicts", false),
    ];

    const result = buildBeliefGraphTrace("entry-1", triples);

    assert.equal(result.decision, "belief-graph-match");
    assert.equal(result.confidence, "high");
    assert.ok(result.graphTrace);
    assert.deepEqual(result.graphTrace?.matchedAxiomIris, [axiom]);
    assert.match(result.graphTrace?.paths[0] ?? "", /High Learning → predicts → Higher Affect/);
  });

  it("refuses when no supportedBy path exists for the entry", () => {
    const result = buildBeliefGraphTrace("missing-entry", []);

    assert.equal(result.decision, "no-graph-path");
    assert.equal(result.graphTrace, null);
    assert.match(result.reason, /No confirmed axiom/);
  });

  it("returns connection graphTrace when the entry is a personal connection", () => {
    const entryId = "869f0928-2c44-4a51-b2c5-aba5613c7dd7";
    const entryIri = `https://understood.app/entry/${entryId}`;
    const triples: RdfTripleRow[] = [
      row(entryIri, RDF_TYPE, `${NS}Connection`, true),
      row(entryIri, `${NS}label`, "Focus on What's in Your Control", false),
      row(entryIri, `${NS}connectionType`, "personal_connection", false),
    ];

    const result = buildBeliefGraphTrace(entryId, triples);

    assert.equal(result.decision, "connection-graph-match");
    assert.match(result.graphTrace?.paths[0] ?? "", /Focus on What's in Your Control → Personal Connection/);
  });
});
