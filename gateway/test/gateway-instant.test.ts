import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { gatewayInstant } from "../lib/gateway-instant.js";

describe("gateway reminder instants", () => {
  it("turns Aurora timestamptz text into ISO 8601 the installed apps already parse", () => {
    assert.equal(gatewayInstant("2026-10-05 20:16:48.331407+00"), "2026-10-05T20:16:48Z");
    assert.equal(gatewayInstant("2026-10-05 20:16:48+00"), "2026-10-05T20:16:48Z");
    assert.equal(gatewayInstant("2026-10-05T20:16:48.331Z"), "2026-10-05T20:16:48Z");
    assert.equal(gatewayInstant(null), null);
    assert.equal(gatewayInstant("not-a-date"), null);
  });
});
