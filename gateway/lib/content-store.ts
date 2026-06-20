import type { CaptureRow, CorrelationSnapshot, EntryRow, GatewayPhase } from "./types.js";
import * as aurora from "./aurora-bridge.js";
import * as neo4j from "./neo4j-bridge.js";
import * as supabase from "./supabase-bridge.js";

function usesAurora(): boolean {
  return Boolean(process.env.AURORA_HOST || process.env.DATABASE_URL);
}

export function gatewayPhase(): GatewayPhase {
  if (usesAurora()) {
    return neo4j.neo4jEnabled() ? "aurora+neo4j" : "aurora";
  }
  return "supabase-bridge";
}

export async function fetchBeliefEntries(limit: number): Promise<EntryRow[]> {
  if (!usesAurora()) {
    return [];
  }
  return aurora.fetchValidatedBeliefEntriesFromRdf(limit);
}

export async function fetchCaptures(limit: number): Promise<CaptureRow[]> {
  if (usesAurora()) {
    return aurora.fetchCaptures(limit);
  }
  return supabase.fetchCaptures(limit);
}

export async function fetchLatestCorrelations(): Promise<CorrelationSnapshot | null> {
  if (!usesAurora()) {
    return supabase.fetchLatestCorrelations();
  }
  // Aurora holds the published snapshot; skip Neo4j enrichment on this hot path to avoid serverless timeouts.
  return aurora.fetchLatestCorrelations();
}
