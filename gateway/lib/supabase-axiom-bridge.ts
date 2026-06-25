import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import ws from "ws";

import type { ExportableAxiom } from "./rdf-axiom-types.js";

type SupabaseAxiomRow = {
  id: string;
  name: string;
  antecedent: string;
  consequent: string;
  confidence: number | string;
  status: ExportableAxiom["status"];
  scope: ExportableAxiom["scope"];
  relationship_type: string;
  evidence_entry_ids: string[] | null;
  evidence_count: number | null;
  provenance: Record<string, unknown> | null;
};

let client: SupabaseClient | null = null;

function getSupabaseClient(): SupabaseClient | null {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return null;

  if (!client) {
    try {
      client = createClient(url, key, {
        auth: { persistSession: false, autoRefreshToken: false },
        realtime: { transport: ws },
      });
    } catch (error) {
      console.error("supabase-axiom-bridge: client init failed", error);
      return null;
    }
  }

  return client;
}

export function supabaseAxiomBridgeAvailable(): boolean {
  return Boolean(process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY);
}

export async function fetchConfirmedPersonalAxioms(): Promise<ExportableAxiom[]> {
  const supabase = getSupabaseClient();
  if (!supabase) return [];

  try {
    const { data, error } = await supabase
      .from("ontology_axioms")
      .select(
        "id,name,antecedent,consequent,confidence,status,scope,relationship_type,evidence_entry_ids,evidence_count,provenance"
      )
      .eq("status", "confirmed")
      .eq("scope", "personal");

    if (error) {
      throw new Error(`Failed to load ontology_axioms from Supabase: ${error.message}`);
    }

    return (data as SupabaseAxiomRow[] | null)?.map(mapSupabaseAxiom) ?? [];
  } catch (error) {
    console.error("supabase-axiom-bridge", error);
    return [];
  }
}

function mapSupabaseAxiom(row: SupabaseAxiomRow): ExportableAxiom {
  return {
    id: row.id,
    antecedent: row.antecedent,
    consequent: row.consequent,
    confidence: Number(row.confidence),
    status: row.status,
    scope: row.scope,
    relationshipType: row.relationship_type,
    evidenceEntryIds: row.evidence_entry_ids ?? [],
    evidenceCount: row.evidence_count ?? row.evidence_entry_ids?.length ?? 0,
    provenance: row.provenance ?? { source: "supabase.ontology_axioms" },
  };
}
