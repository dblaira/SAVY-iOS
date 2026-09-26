import * as aurora from "./aurora-bridge.js";
import { gatewayPhase } from "./content-store.js";
import type { UserDocumentRow } from "./aurora-bridge.js";
import {
  isDocumentKey,
  mergeEntries,
  storedEntries,
  type DocumentKey,
  type SyncDocument,
  type SyncEntries,
} from "./document-merge.js";

export function documentStoreAvailable(): boolean {
  return gatewayPhase() !== "supabase-bridge";
}

/** Postgres "undefined_table": the schema script has not been applied to this database yet. */
export function isMissingDocumentTable(error: unknown): boolean {
  return typeof error === "object" && error !== null && (error as { code?: unknown }).code === "42P01";
}

function toDocument(row: UserDocumentRow): SyncDocument | null {
  if (!isDocumentKey(row.doc_key)) return null;
  return {
    key: row.doc_key,
    entries: storedEntries(row.entries),
    revision: Number(row.revision) || 0,
    updatedAt: row.updated_at ?? null,
  };
}

export async function fetchUserDocuments(userId: string): Promise<SyncDocument[]> {
  const rows = await aurora.fetchDocumentsForUser(userId);
  return rows.map(toDocument).filter((document): document is SyncDocument => document !== null);
}

export async function mergeUserDocument(
  userId: string,
  key: DocumentKey,
  incoming: SyncEntries,
  email?: string | null
): Promise<SyncDocument> {
  await aurora.ensureSavyUser(userId, email);
  const row = await aurora.mergeDocumentForUser(userId, key, (stored) =>
    mergeEntries(storedEntries(stored), incoming)
  );
  return toDocument(row) ?? { key, entries: {}, revision: 0, updatedAt: null };
}
