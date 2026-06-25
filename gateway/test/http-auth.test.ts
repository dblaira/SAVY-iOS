import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { requireGatewayOrCron } from "../lib/http.js";

function mockResponse() {
  const response = {
    statusCode: 200,
    body: undefined as unknown,
    status(code: number) {
      this.statusCode = code;
      return this;
    },
    json(payload: unknown) {
      this.body = payload;
      return this;
    },
    end() {
      return this;
    },
  };

  return response;
}

describe("requireGatewayOrCron", () => {
  it("accepts a valid cron bearer token", () => {
    const previous = process.env.CRON_SECRET;
    process.env.CRON_SECRET = "cron-test-secret";

    try {
      const res = mockResponse();
      const allowed = requireGatewayOrCron(
        {
          headers: { authorization: "Bearer cron-test-secret" },
        } as never,
        res as never
      );

      assert.equal(allowed, true);
      assert.equal(res.statusCode, 200);
    } finally {
      process.env.CRON_SECRET = previous;
    }
  });
});
