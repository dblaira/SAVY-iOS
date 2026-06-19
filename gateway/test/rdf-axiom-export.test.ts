import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  buildTripleRowsFromAxioms,
  deriveIfThenFromConnection,
  deriveValidatedPrincipleAxiom,
} from "../lib/rdf-axiom-export.js";

describe("deriveIfThenFromConnection", () => {
  it("splits a two-sentence validated principle into antecedent and consequent", () => {
    const result = deriveIfThenFromConnection(
      "The 10 minutes exporting your judgment builds a system th...",
      "The 10 minutes exporting your judgment builds a system that compounds. The 10 minutes just doing the task is gone forever."
    );

    assert.equal(
      result.antecedent,
      "The 10 minutes exporting your judgment builds a system that compounds"
    );
    assert.equal(result.consequent, "The 10 minutes just doing the task is gone forever");
    assert.equal(result.relationshipType, "causes");
  });
});

describe("deriveValidatedPrincipleAxiom", () => {
  it("creates a confirmed personal axiom citing the connection entry", () => {
    const axiom = deriveValidatedPrincipleAxiom({
      id: "380cb499-7a80-4476-8d32-3fb3fd2b3b8b",
      headline: "The 10 minutes exporting your judgment builds a system th...",
      content:
        "The 10 minutes exporting your judgment builds a system that compounds. The 10 minutes just doing the task is gone forever.",
      connection_type: "validated_principle",
      entry_type: "connection",
    });

    assert.ok(axiom);
    assert.equal(axiom?.evidenceEntryIds[0], "380cb499-7a80-4476-8d32-3fb3fd2b3b8b");
    assert.equal(axiom?.status, "confirmed");
    assert.equal(axiom?.scope, "personal");
  });
});

describe("buildTripleRowsFromAxioms", () => {
  it("emits supportedBy triples with real entry UUIDs", () => {
    const rows = buildTripleRowsFromAxioms([
      {
        id: "entry-380cb499",
        antecedent: "Export judgment",
        consequent: "System compounds",
        confidence: 0.75,
        status: "confirmed",
        scope: "personal",
        relationshipType: "causes",
        evidenceEntryIds: ["380cb499-7a80-4476-8d32-3fb3fd2b3b8b"],
        evidenceCount: 1,
        provenance: { source: "validated_principle_connection" },
      },
    ]);

    assert.ok(
      rows.some(
        (row) =>
          row.subject.includes("/axiom/entry-380cb499") &&
          row.predicate.endsWith("supportedBy") &&
          row.object === "https://understood.app/entry/380cb499-7a80-4476-8d32-3fb3fd2b3b8b"
      )
    );
  });
});
