import { normalizeScheduleFields, ScheduleValidationError } from "./reminder-schedule.js";

/**
 * Per-user sync documents hold records that used to live on a single device: authored
 * Connections, older News/Advertising posts, Stories, card order and pins, the post-number
 * ledger, and Personal Authority decisions. They are never RDF authority.
 *
 * Each document is a map of entry key -> { value, modifiedAt, deleted }. Merging keeps the
 * entry with the later modifiedAt; on a tie the stored entry stays, which is what lets
 * clients express "first writer wins" by stamping an entry with a constant time.
 */

export const DOCUMENT_KEYS = [
  "connections",
  "social-posts",
  "stories",
  "card-preferences",
  "post-numbers",
  "personal-authority",
] as const;

export type DocumentKey = (typeof DOCUMENT_KEYS)[number];

export interface SyncEntry {
  value: unknown;
  modifiedAt: number;
  deleted: boolean;
}

export type SyncEntries = Record<string, SyncEntry>;

export interface SyncDocument {
  key: DocumentKey;
  entries: SyncEntries;
  revision: number;
  updatedAt: string | null;
}

export const MAX_ENTRY_KEY_LENGTH = 200;
export const MAX_ENTRIES_PER_REQUEST = 5000;
export const MAX_ENTRIES_PER_DOCUMENT = 20000;

export function isDocumentKey(value: unknown): value is DocumentKey {
  return typeof value === "string" && (DOCUMENT_KEYS as readonly string[]).includes(value);
}

export class DocumentValidationError extends Error {}

/** Validates client input. Throws `DocumentValidationError` with a reason on bad input. */
export function parseEntries(input: unknown, limit = MAX_ENTRIES_PER_REQUEST): SyncEntries {
  if (typeof input !== "object" || input === null || Array.isArray(input)) {
    throw new DocumentValidationError("entries must be an object");
  }
  const keys = Object.keys(input);
  if (keys.length > limit) {
    throw new DocumentValidationError(`at most ${limit} entries per request`);
  }
  const parsed: SyncEntries = {};
  for (const key of keys) {
    if (key.length === 0 || key.length > MAX_ENTRY_KEY_LENGTH) {
      throw new DocumentValidationError("entry keys must be 1-200 characters");
    }
    const raw = (input as Record<string, unknown>)[key];
    if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
      throw new DocumentValidationError(`entry ${key} must be an object`);
    }
    const { value, modifiedAt, deleted } = raw as Record<string, unknown>;
    if (typeof modifiedAt !== "number" || !Number.isFinite(modifiedAt) || modifiedAt < 0) {
      throw new DocumentValidationError(`entry ${key} needs a non-negative modifiedAt`);
    }
    if (typeof deleted !== "boolean") {
      throw new DocumentValidationError(`entry ${key} needs a deleted flag`);
    }
    parsed[key] = { value: deleted ? null : (value ?? null), modifiedAt, deleted };
  }
  return parsed;
}

/** Stored JSON is trusted but may predate a field; anything malformed is dropped rather than served. */
export function storedEntries(input: unknown): SyncEntries {
  try {
    return parseEntries(input ?? {}, Number.MAX_SAFE_INTEGER);
  } catch {
    return {};
  }
}

export function mergeEntries(
  existing: SyncEntries,
  incoming: SyncEntries,
  documentKey?: DocumentKey
): { merged: SyncEntries; changed: boolean } {
  const merged: SyncEntries = { ...existing };
  let changed = false;
  for (const [key, entry] of Object.entries(incoming)) {
    const current = merged[key];
    if (!current || entry.modifiedAt > current.modifiedAt) {
      merged[key] = documentKey === "connections" && key.startsWith("entry:")
        ? mergeConnectionSchedule(current, entry) : entry;
      changed = true;
    }
  }
  if (Object.keys(merged).length > MAX_ENTRIES_PER_DOCUMENT) {
    throw new DocumentValidationError(`a document holds at most ${MAX_ENTRIES_PER_DOCUMENT} entries`);
  }
  return { merged, changed };
}

function object(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown> : undefined;
}

/** Old document clients omit Schedule entirely when editing an entry's writing. */
function mergeConnectionSchedule(current: SyncEntry | undefined, incoming: SyncEntry): SyncEntry {
  if (incoming.deleted) return incoming;
  const value = object(incoming.value);
  const originalMetadata = object(value?.metadata);
  if (!value || !originalMetadata) return incoming;
  const metadata = { ...originalMetadata };
  const currentMetadata = object(object(current?.value)?.metadata);
  const hasSchedule = Object.prototype.hasOwnProperty.call(metadata, "schedule");
  if (!hasSchedule && metadata.scheduleSyncVersion == null) {
    if (currentMetadata?.scheduleSyncVersion === 1) {
      for (const field of ["schedule", "scheduleSyncVersion", "dueDate", "dueTime", "endTime"]) {
        if (Object.prototype.hasOwnProperty.call(currentMetadata, field)) metadata[field] = currentMetadata[field];
        else delete metadata[field];
      }
    }
  }
  if (Object.prototype.hasOwnProperty.call(metadata, "schedule") || metadata.scheduleSyncVersion != null) {
    try {
      const normalized = normalizeScheduleFields({
        schedule: metadata.schedule ?? null,
        schedule_version: metadata.scheduleSyncVersion,
      });
      metadata.scheduleSyncVersion = normalized.schedule_version;
      // The Swift document encoder omits nil optionals. Keep that representation on clear.
      if (normalized.schedule == null) delete metadata.schedule;
      else metadata.schedule = normalized.schedule;
    } catch (error) {
      if (error instanceof ScheduleValidationError) throw new DocumentValidationError(error.message);
      throw error;
    }
  }
  return { ...incoming, value: { ...value, metadata } };
}
