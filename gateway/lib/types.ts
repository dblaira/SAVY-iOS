export type EntryRow = {
  id: string;
  headline: string;
  content: string;
  connection_type: string | null;
  entry_type: string | null;
};

export type CaptureRow = {
  id: string;
  title: string;
  meaning: string;
  created_at: string | null;
};

export type CorrelationSnapshot = {
  total_weeks: number;
  total_extractions: number;
  correlations: unknown[];
  category_stats: unknown[];
};

export type GatewayPhase = "aurora" | "supabase-bridge";
