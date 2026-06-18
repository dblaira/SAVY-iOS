import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import ws from "ws";
import type { CaptureRow, CorrelationSnapshot, EntryRow } from "./types.js";
import { normalizeCategoryStats, normalizeCorrelations } from "./normalize.js";

let client: SupabaseClient | null = null;

export function getSupabaseBridge(): SupabaseClient {
  if (client) return client;

  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!url || !key) {
    throw new Error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required for bridge phase");
  }

  client = createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
    realtime: { transport: ws as never },
  });

  return client;
}

export async function fetchBeliefEntries(limit: number): Promise<EntryRow[]> {
  const supabase = getSupabaseBridge();
  const { data, error } = await supabase
    .from("entries")
    .select("id, headline, content, connection_type, entry_type")
    .eq("entry_type", "connection")
    .order("pinned_at", { ascending: false, nullsFirst: false })
    .order("created_at", { ascending: false })
    .limit(limit);

  if (error) throw error;
  return (data ?? []) as EntryRow[];
}

export async function fetchCaptures(_limit: number): Promise<CaptureRow[]> {
  return [];
}

export async function fetchLatestCorrelations(): Promise<CorrelationSnapshot | null> {
  const supabase = getSupabaseBridge();
  const { data, error } = await supabase
    .from("correlation_analyses")
    .select("total_weeks, total_extractions, correlations, category_stats")
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (error) throw error;
  if (!data) return null;

  return {
    total_weeks: data.total_weeks,
    total_extractions: data.total_extractions,
    correlations: normalizeCorrelations(data.correlations),
    category_stats: normalizeCategoryStats(data.category_stats),
  };
}
