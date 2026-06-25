import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, it } from "node:test";

import { parseSuiteTripleRows } from "../lib/rdf-import.js";

const fixturePath = join(
  dirname(fileURLToPath(import.meta.url)),
  "../../../understood-app/fixtures/ontology/suite-triples.json"
);

describe("parseSuiteTripleRows", () => {
  it("accepts understood-app export shape", () => {
    const raw = JSON.parse(readFileSync(fixturePath, "utf8"));
    const rows = parseSuiteTripleRows(raw);

    assert.ok(rows.length > 0);
    assert.equal(rows[0]?.graphIri, "https://understood.app/graph/personal");
    assert.equal(rows[0]?.sourceApp, "understood");
  });

  it("rejects invalid payloads", () => {
    assert.throws(() => parseSuiteTripleRows({}), /JSON array/);
    assert.throws(
      () =>
        parseSuiteTripleRows([
          {
            graphIri: "https://understood.app/graph/personal",
            subject: "",
            predicate: "p",
            object: "o",
            objectIsIri: true,
            sourceApp: "understood",
          },
        ]),
      /missing subject/
    );
  });
});
