import * as aurora from "./aurora-bridge.js";
import {
  buildTripleRowsFromBeliefEntries,
  entryIriForId,
  type BeliefEntryExportRow,
} from "./rdf-entry-export.js";

export async function syncBeliefEntryRdf(entryId: string): Promise<number> {
  if (await aurora.rdfEntrySyncAvailable()) {
    return aurora.syncEntryRdfTriples(entryId);
  }

  return syncBeliefEntryRdfViaTypescript(entryId);
}

export async function syncAllBeliefEntryRdf(): Promise<{
  syncedEntries: number;
  totalRdfRows: number;
}> {
  if (await aurora.rdfEntrySyncAvailable()) {
    const syncedEntries = await aurora.syncAllBeliefEntryRdf();
    const totalRdfRows = await aurora.countRdfTriples();
    return { syncedEntries, totalRdfRows };
  }

  return syncAllBeliefEntryRdfViaTypescript();
}

async function syncBeliefEntryRdfViaTypescript(entryId: string): Promise<number> {
  const entry = await aurora.fetchBeliefEntryById(entryId);
  if (!entry) {
    await aurora.deleteEntryRdfTriples(entryIriForId(entryId));
    return 0;
  }

  const rows = buildTripleRowsFromBeliefEntries([entry]);
  await aurora.replaceEntryRdfTriples(entryIriForId(entryId), rows);
  return rows.length;
}

async function syncAllBeliefEntryRdfViaTypescript(): Promise<{
  syncedEntries: number;
  totalRdfRows: number;
}> {
  const entries = await aurora.fetchAllBeliefEntries();
  await aurora.deleteBeliefEntryRdfTriples();
  const rows = buildTripleRowsFromBeliefEntries(entries);
  const inserted = await aurora.importSuiteTriples(rows);
  const totalRdfRows = await aurora.countRdfTriples();
  return { syncedEntries: entries.length, totalRdfRows: totalRdfRows || inserted };
}

export type { BeliefEntryExportRow };
