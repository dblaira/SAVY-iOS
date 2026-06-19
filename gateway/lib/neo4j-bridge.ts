import neo4j, { type Driver } from "neo4j-driver";
import type { CorrelationSnapshot } from "./types.js";
import { normalizeCorrelations } from "./normalize.js";
import { TimeoutError, withTimeout } from "./timeout.js";
import * as aurora from "./aurora-bridge.js";

const NEO4J_QUERY_TIMEOUT_MS = 4_500;

let driver: Driver | null = null;

function neo4jConfig() {
  const uri = process.env.NEO4J_URI;
  const user = process.env.NEO4J_USER ?? "neo4j";
  const password = process.env.NEO4J_PASSWORD;

  if (!uri || !password) {
    throw new Error("NEO4J_URI and NEO4J_PASSWORD required for Neo4j phase");
  }

  return { uri, user, password };
}

function neo4jDatabase(): string {
  return process.env.NEO4J_DATABASE ?? process.env.NEO4J_USER ?? "neo4j";
}

export function neo4jEnabled(): boolean {
  return Boolean(process.env.NEO4J_URI && process.env.NEO4J_PASSWORD);
}

function getDriver(): Driver {
  if (driver) return driver;

  const { uri, user, password } = neo4jConfig();
  driver = neo4j.driver(uri, neo4j.auth.basic(user, password), {
    maxConnectionPoolSize: 2,
    connectionAcquisitionTimeout: NEO4J_QUERY_TIMEOUT_MS,
    connectionTimeout: NEO4J_QUERY_TIMEOUT_MS,
    maxTransactionRetryTime: NEO4J_QUERY_TIMEOUT_MS,
  });
  return driver;
}

function openSession() {
  return getDriver().session({ database: neo4jDatabase() });
}

export async function verifyConnectivity(): Promise<boolean> {
  const session = openSession();
  try {
    await withTimeout(
      session.run("RETURN 1 AS ok"),
      NEO4J_QUERY_TIMEOUT_MS,
      "Neo4j connectivity check timed out"
    );
    return true;
  } catch {
    return false;
  } finally {
    await session.close();
  }
}

export async function fetchCorrelationsFromGraph(limit = 50): Promise<unknown[]> {
  const session = openSession();
  try {
    const result = await withTimeout(
      session.run(
        `MATCH (a:Category)-[c:CORRELATES_WITH]->(b:Category)
         RETURN a.name AS category_a,
                b.name AS category_b,
                c.coefficient AS coefficient,
                c.type AS type,
                c.lag AS lag
         ORDER BY abs(c.coefficient) DESC
         LIMIT $limit`,
        { limit: neo4j.int(limit) }
      ),
      NEO4J_QUERY_TIMEOUT_MS,
      "Neo4j correlation query timed out"
    );

    return result.records.map((record) => ({
      category_a: record.get("category_a"),
      category_b: record.get("category_b"),
      coefficient: record.get("coefficient"),
      type: record.get("type"),
      lag: record.get("lag"),
    }));
  } finally {
    await session.close();
  }
}

export async function fetchLatestCorrelations(): Promise<CorrelationSnapshot | null> {
  const stats = await aurora.fetchLatestCorrelations();
  if (!stats) return null;

  if (!neo4jEnabled()) {
    return stats;
  }

  try {
    const graphCorrelations = normalizeCorrelations(await fetchCorrelationsFromGraph());
    if (graphCorrelations.length === 0) {
      return stats;
    }

    return {
      ...stats,
      correlations: graphCorrelations,
    };
  } catch (error) {
    const reason =
      error instanceof TimeoutError
        ? "Neo4j enrichment timed out"
        : error instanceof Error
          ? error.message
          : "Neo4j enrichment failed";
    console.warn("v1/correlations/latest falling back to Aurora snapshot:", reason);
    return stats;
  }
}
