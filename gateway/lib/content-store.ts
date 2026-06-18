import type { CaptureRow, CorrelationSnapshot, EntryRow, GatewayPhase } from "./types.js";
import * as aurora from "./aurora-bridge.js";
import * as supabase from "./supabase-bridge.js";

export function gatewayPhase(): GatewayPhase {
  if (process.env.AURORA_HOST || process.env.DATABASE_URL) {
    return "aurora";
  }
  return "supabase-bridge";
}

export async function fetchBeliefEntries(limit: number): Promise<EntryRow[]> {
  if (gatewayPhase() === "aurora") {
    return aurora.fetchBeliefEntries(limit);
  }
  return supabase.fetchBeliefEntries(limit);
}

export async function fetchCaptures(limit: number): Promise<CaptureRow[]> {
  if (gatewayPhase() === "aurora") {
    return aurora.fetchCaptures(limit);
  }
  return supabase.fetchCaptures(limit);
}

export async function fetchLatestCorrelations(): Promise<CorrelationSnapshot | null> {
  if (gatewayPhase() === "aurora") {
    return aurora.fetchLatestCorrelations();
  }
  return supabase.fetchLatestCorrelations();
}
