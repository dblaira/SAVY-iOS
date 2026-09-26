import assert from "node:assert/strict";
import { generateKeyPairSync, sign } from "node:crypto";
import { afterEach, describe, it, mock } from "node:test";
import pg from "pg";
import handler from "../api/v1/documents.js";
import { resetCognitoKeyCacheForTests, verifyCognitoAccessToken } from "../lib/cognito-verify.js";
import { DocumentValidationError, mergeEntries, parseEntries, storedEntries } from "../lib/document-merge.js";
import { mergeUserDocument } from "../lib/document-store.js";

const issuer = "https://cognito-idp.us-west-2.amazonaws.com/us-west-2_TestPool";
const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
const jwks = { keys: [{ ...publicKey.export({ format: "jwk" }), kid: "test-key", alg: "RS256", use: "sig" }] };

function signature(unsigned: string, key = privateKey) {
  return sign("RSA-SHA256", new Uint8Array(Buffer.from(unsigned)), key).toString("base64url");
}

function token(payload: Record<string, unknown>, header: Record<string, unknown> = { alg: "RS256", kid: "test-key" }) {
  const encode = (value: unknown) => Buffer.from(JSON.stringify(value)).toString("base64url");
  const unsigned = `${encode(header)}.${encode(payload)}`;
  return `${unsigned}.${signature(unsigned)}`;
}

const now = Date.UTC(2026, 8, 24, 18, 0, 0);
const validClaims = { sub: "user-123", iss: issuer, token_use: "access", exp: now / 1000 + 600 };
const fetchJwks = async () => jwks;

describe("sync document merge", () => {
  it("keeps the later entry and leaves the stored entry on a tie", () => {
    const stored = {
      a: { value: "stored", modifiedAt: 10, deleted: false },
      b: { value: "stored", modifiedAt: 10, deleted: false },
      c: { value: "stored", modifiedAt: 10, deleted: false },
    };
    const { merged, changed } = mergeEntries(stored, {
      a: { value: "newer", modifiedAt: 11, deleted: false },
      b: { value: "same time", modifiedAt: 10, deleted: false },
      c: { value: "older", modifiedAt: 9, deleted: false },
      d: { value: "new key", modifiedAt: 0, deleted: false },
    });
    assert.equal(changed, true);
    assert.equal(merged.a.value, "newer");
    assert.equal(merged.b.value, "stored");
    assert.equal(merged.c.value, "stored");
    assert.equal(merged.d.value, "new key");
  });

  it("reports no change when nothing newer arrives", () => {
    const stored = { a: { value: 1, modifiedAt: 5, deleted: false } };
    assert.equal(mergeEntries(stored, { a: { value: 2, modifiedAt: 5, deleted: false } }).changed, false);
  });

  it("carries deletions as tombstones so they win over older copies", () => {
    const { merged } = mergeEntries(
      { post: { value: { text: "draft" }, modifiedAt: 20, deleted: false } },
      { post: { value: { text: "ignored" }, modifiedAt: 21, deleted: true } }
    );
    assert.deepEqual(merged.post, { value: { text: "ignored" }, modifiedAt: 21, deleted: true });
    assert.deepEqual(parseEntries({ post: { value: { text: "x" }, modifiedAt: 21, deleted: true } }).post.value, null);
  });

  it("rejects malformed entries instead of storing them", () => {
    for (const bad of [null, [], "x", { a: null }, { a: { value: 1, deleted: false } }, { a: { value: 1, modifiedAt: -1, deleted: false } },
      { a: { value: 1, modifiedAt: 1 } }, { "": { value: 1, modifiedAt: 1, deleted: false } }]) {
      assert.throws(() => parseEntries(bad), DocumentValidationError);
    }
    assert.deepEqual(storedEntries("corrupt"), {});
  });
});

describe("Cognito access token verification", () => {
  afterEach(() => resetCognitoKeyCacheForTests());

  it("accepts a correctly signed, unexpired access token from the pool", async () => {
    assert.equal(await verifyCognitoAccessToken(token(validClaims), { issuer, fetchJwks, now }), "user-123");
  });

  it("rejects forged, expired, foreign, and non-access tokens", async () => {
    const forged = token(validClaims).split(".");
    forged[1] = Buffer.from(JSON.stringify({ ...validClaims, sub: "someone-else" })).toString("base64url");
    const otherKey = generateKeyPairSync("rsa", { modulusLength: 2048 }).privateKey;
    const unsigned = token(validClaims).split(".").slice(0, 2).join(".");
    const wrongSigner = `${unsigned}.${signature(unsigned, otherKey)}`;
    for (const candidate of [
      forged.join("."),
      wrongSigner,
      token({ ...validClaims, exp: now / 1000 - 1 }),
      token({ ...validClaims, iss: "https://cognito-idp.us-west-2.amazonaws.com/other" }),
      token({ ...validClaims, token_use: "id" }),
      token(validClaims, { alg: "none", kid: "test-key" }),
      token(validClaims, { alg: "RS256", kid: "unknown-key" }),
      "not-a-token",
    ]) {
      assert.equal(await verifyCognitoAccessToken(candidate, { issuer, fetchJwks, now }), null);
    }
  });

  it("fails closed when the pool is not configured", async () => {
    assert.equal(await verifyCognitoAccessToken(token(validClaims), { issuer: null, fetchJwks, now }), null);
  });
});

describe("user document storage", () => {
  it("merges under a row lock and only writes when something changed", async () => {
    const previousHost = process.env.AURORA_HOST;
    process.env.AURORA_HOST = "postgresql://localhost/savy-document-test";
    const statements: string[] = [];
    let stored: Record<string, unknown> = { kept: { value: "phone", modifiedAt: 50, deleted: false } };
    const connection = {
      async query(sql: string, values: unknown[] = []) {
        statements.push(sql.replace(/\s+/g, " ").trim());
        if (sql.includes("FOR UPDATE")) {
          return { rows: [{ doc_key: values[1], entries: stored, revision: "3", updated_at: null }] };
        }
        if (sql.includes("UPDATE savy.user_documents")) {
          stored = JSON.parse(String(values[2]));
          return { rows: [{ doc_key: values[1], entries: stored, revision: "4", updated_at: "2026-09-24 18:00:00+00" }] };
        }
        return { rows: [] };
      },
      release() {},
    };
    const connect = mock.method(pg.Pool.prototype, "connect", async () => connection);
    try {
      const document = await mergeUserDocument("user-123", "connections", {
        kept: { value: "older mac copy", modifiedAt: 40, deleted: false },
        added: { value: { title: "New" }, modifiedAt: 60, deleted: false },
      });
      assert.equal(document.revision, 4);
      assert.deepEqual(Object.keys(document.entries).sort(), ["added", "kept"]);
      assert.equal(document.entries.kept.value, "phone");
      assert.ok(statements.some((sql) => sql.includes("INSERT INTO savy.users")));
      assert.ok(statements.some((sql) => sql.includes("FOR UPDATE")));
      assert.equal(statements.at(-1), "COMMIT");

      statements.length = 0;
      const unchanged = await mergeUserDocument("user-123", "connections", {
        kept: { value: "older mac copy", modifiedAt: 40, deleted: false },
      });
      assert.equal(unchanged.revision, 3);
      assert.ok(!statements.some((sql) => sql.startsWith("UPDATE savy.user_documents")));
    } finally {
      connect.mock.restore();
      if (previousHost === undefined) delete process.env.AURORA_HOST;
      else process.env.AURORA_HOST = previousHost;
    }
  });
});

describe("v1/documents handler", () => {
  function response() {
    return {
      statusCode: 200,
      body: undefined as unknown,
      status(code: number) { this.statusCode = code; return this; },
      json(payload: unknown) { this.body = payload; return this; },
      end() { return this; },
    };
  }

  it("refuses an unsigned bearer token even with the API key", async () => {
    const previousKey = process.env.SAVY_API_KEY;
    const previousPool = process.env.COGNITO_USER_POOL_ID;
    process.env.SAVY_API_KEY = "test-key";
    process.env.COGNITO_USER_POOL_ID = "us-west-2_TestPool";
    try {
      const unsigned = [
        Buffer.from(JSON.stringify({ alg: "none" })).toString("base64url"),
        Buffer.from(JSON.stringify(validClaims)).toString("base64url"),
        "",
      ].join(".");
      const res = response();
      await handler({ method: "GET", headers: { "x-api-key": "test-key", authorization: `Bearer ${unsigned}` } } as never, res as never);
      assert.equal(res.statusCode, 401);
    } finally {
      if (previousKey === undefined) delete process.env.SAVY_API_KEY;
      else process.env.SAVY_API_KEY = previousKey;
      if (previousPool === undefined) delete process.env.COGNITO_USER_POOL_ID;
      else process.env.COGNITO_USER_POOL_ID = previousPool;
    }
  });
});
