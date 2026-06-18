import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import ws from "ws";

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
    realtime: { transport: ws },
  });

  return client;
}

export type EntryRow = {
  id: string;
  headline: string;
  content: string;
  connection_type: string | null;
  entry_type: string | null;
};

export type CorrelationSnapshot = {
  total_weeks: number;
  total_extractions: number;
  correlations: unknown[];
  category_stats: unknown[];
};

type JsonRecord = Record<string, unknown>;

function normalizeCorrelation(raw: unknown): JsonRecord {
  const row = (raw ?? {}) as JsonRecord;
  return {
    category_a: row.category_a ?? row.categoryA,
    category_b: row.category_b ?? row.categoryB,
    coefficient: row.coefficient,
    lag: row.lag,
    type: row.type,
  };
}

function normalizeCategoryStat(raw: unknown): JsonRecord {
  const row = (raw ?? {}) as JsonRecord;
  return {
    category: row.category,
    mean: row.mean,
    std_dev: row.std_dev ?? row.stdDev,
    weeks_with_data: row.weeks_with_data ?? row.weeksWithData,
    total_count: row.total_count ?? row.totalCount,
    coverage_percent: row.coverage_percent ?? row.coveragePercent,
  };
}

function normalizeCorrelations(rows: unknown): unknown[] {
  if (!Array.isArray(rows)) return [];
  return rows.map(normalizeCorrelation);
}

function normalizeCategoryStats(rows: unknown): unknown[] {
  if (!Array.isArray(rows)) return [];
  return rows.map(normalizeCategoryStat);
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
