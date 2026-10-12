import Foundation

struct SavyCloudRecordID: Hashable, Codable, Sendable {
    var documentKey: String
    var key: String
}

/// The portable version and opaque CloudKit change-tag metadata travel independently.
struct SavyCloudRecord: Codable, Equatable, Sendable {
    var id: SavyCloudRecordID
    var entry: SyncEntry
    var systemFields: Data? = nil
}

/// Both complete originals are retained before a differing value can be displaced.
struct SavyCloudConflict: Codable, Equatable, Sendable {
    var id: SavyCloudRecordID
    var displaced: SyncEntry
    var retained: SyncEntry
}

enum SavyCloudSyncStateError: Error, Equatable {
    case unreadableSource(String)
    case staleGeneration
    case invalidRecord
    case invalidState
}

/// One atomic journal owns the confirmed versions, exact pending versions, incoming replay,
/// conflict originals, CloudKit system fields, and fetch checkpoints. It never opens a network.
@MainActor
final class SavyCloudSyncState {
    enum AccountStatus: Equatable {
        case unavailable
        case authorized
        case differentAccount
    }

    private struct Document: Codable, Equatable {
        var entries: [String: SyncEntry] = [:]
        var pending: [String: SyncEntry] = [:]
        var incoming: [String: SyncEntry] = [:]
        // The inbox keeps the portable winner; only the latest fetched payload proves
        // what the server contains. One receipt per incoming key, released after apply.
        // Legacy journals omit this field and conservatively re-send their winner.
        var incomingReceipts: [String: SyncEntry]? = nil
        var systemFields: [String: Data] = [:]
        // Written before a store apply. If the journal's final write fails after the store
        // succeeds, this target identifies that durable store content as replay, not an edit.
        var applyTarget: [String: SyncEntry]? = nil
        // The last target actually observed in the store before staging its replacement.
        // Keep one bounded copy until the replacement's store and journal both confirm.
        var materializedTarget: [String: SyncEntry]? = nil
        var initialized = false
    }

    private struct Archive: Codable, Equatable {
        var formatVersion = 1
        var originalOwner: String? = nil
        var generation: UInt64 = 0
        var documents: [String: Document] = [:]
        var conflicts: [SavyCloudConflict] = []
        var engineState: Data? = nil
        var foregroundChangeToken: Data? = nil
    }

    let fileURL: URL
    private var archive: Archive
    private var currentAccount: String?
    private(set) var generation: UInt64

    var originalOwner: String? { archive.originalOwner }
    var engineState: Data? { archive.engineState }
    var foregroundChangeToken: Data? { archive.foregroundChangeToken }
    var conflicts: [SavyCloudConflict] { archive.conflicts }
    var accountStatus: AccountStatus {
        guard let currentAccount else { return .unavailable }
        return archive.originalOwner == currentAccount ? .authorized : .differentAccount
    }

    var pendingRecords: [SavyCloudRecord] { records(\.pending) }
    var incomingRecords: [SavyCloudRecord] { records(\.incoming) }

    init(fileURL: URL) throws {
        self.fileURL = fileURL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: fileURL))
            guard archive.formatVersion == 1 else { throw SavyCloudSyncStateError.invalidState }
            for document in archive.documents.values {
                for entry in Array(document.entries.values) + Array(document.pending.values)
                    + Array(document.incoming.values) + Array((document.incomingReceipts ?? [:]).values) {
                    _ = try Self.normalized(entry)
                }
            }
        } else {
            archive = Archive()
        }
        generation = archive.generation
    }

    /// Every account transition invalidates prior callbacks, even if its journal write fails.
    /// The first owner remains bound; returning to that owner resumes the same retained state.
    @discardableResult
    func accountChanged(to identifier: String?) throws -> AccountStatus {
        guard currentAccount != identifier || archive.generation != generation
                || (archive.originalOwner == nil && identifier != nil) else { return accountStatus }
        currentAccount = identifier
        generation += 1
        var next = archive
        next.generation = generation
        if next.originalOwner == nil, let identifier { next.originalOwner = identifier }
        try commit(next)
        return accountStatus
    }

    func canTransport(generation candidate: UInt64) -> Bool {
        candidate == generation && accountStatus == .authorized
    }

    func entry(for id: SavyCloudRecordID) -> SyncEntry? {
        archive.documents[id.documentKey]?.entries[id.key]
    }

    func systemFields(for id: SavyCloudRecordID) -> Data? {
        archive.documents[id.documentKey]?.systemFields[id.key]
    }

    /// Read the actual store before enqueueing transport work. First import uses each record's
    /// real date; subsequent edits advance beyond the greatest version already seen here.
    @discardableResult
    func observeLocal(adapter: any SavySyncAdapter, legacyDevice: Bool, now: Double) throws -> [SavyCloudRecord] {
        guard adapter.isReady else { throw SavyCloudSyncStateError.unreadableSource(adapter.documentKey) }
        (adapter as? any SavyPassthroughSyncAdapter)?.restoreUndecodable(
            Self.liveValues(archive.documents[adapter.documentKey]?.entries ?? [:]))
        let values = adapter.snapshot()
        let tombstones = (adapter as? any SavyTombstoneSyncAdapter)?.localTombstones ?? [:]
        var document = archive.documents[adapter.documentKey] ?? Document()
        if let target = document.applyTarget, values == Self.liveValues(target), tombstones.isEmpty {
            return pendingRecords.filter { $0.id.documentKey == adapter.documentKey }
        }
        if let target = document.materializedTarget, values == Self.liveValues(target), tombstones.isEmpty {
            return pendingRecords.filter { $0.id.documentKey == adapter.documentKey }
        }
        var known = document.entries
        for (key, materialized) in document.materializedTarget ?? [:] {
            known[key] = try Self.newest(known[key], materialized)
        }
        let firstRun = !document.initialized
        for (key, value) in values {
            let previous = known[key]
            if previous?.deleted == false && previous?.value == value { continue }
            // A successful store apply followed by a failed journal write is still incoming.
            if document.applyTarget?[key]?.deleted == false && document.applyTarget?[key]?.value == value { continue }
            let latest = try Self.newest(previous, document.incoming[key])
            let stamp = adapter.stamp(key: key, value: value, context: firstRun
                ? .firstRun(legacyDevice: legacyDevice) : .change(previous: latest, now: now))
            let entry = try Self.normalized(SyncEntry(value: value, modifiedAt: stamp.modifiedAt, deleted: false))
            document.entries[key] = entry
            if stamp.uploads { document.pending[key] = entry } else { document.pending.removeValue(forKey: key) }
        }
        for (key, date) in tombstones {
            let previous = known[key]
            if previous?.deleted == true, let previous, previous.modifiedAt >= date { continue }
            if let target = document.applyTarget?[key], target.deleted, target.modifiedAt >= date { continue }
            let latest = try Self.newest(previous, document.incoming[key])
            let time = firstRun ? date : SyncChangeContext.stampAfter(latest, now: max(now, date))
            let entry = try Self.normalized(SyncEntry(value: nil, modifiedAt: time, deleted: true))
            document.entries[key] = entry
            document.pending[key] = entry
        }
        if !firstRun {
            for (key, previous) in known where !previous.deleted && values[key] == nil && tombstones[key] == nil {
                if document.applyTarget?[key]?.deleted == true { continue }
                let latest = try Self.newest(previous, document.incoming[key])
                let entry = SyncEntry(value: nil, modifiedAt: SyncChangeContext.stampAfter(latest, now: now), deleted: true)
                document.entries[key] = entry
                document.pending[key] = entry
            }
        }
        document.initialized = true
        var next = archive
        next.documents[adapter.documentKey] = document
        try commit(next)
        return pendingRecords.filter { $0.id.documentKey == adapter.documentKey }
    }

    /// Call this before accepting the engine's advanced fetch serialization. Opaque system
    /// fields are retained even when the portable local version wins a server conflict.
    func retainIncoming(_ records: [SavyCloudRecord], generation: UInt64) throws {
        try requireGeneration(generation)
        var next = archive
        for record in records {
            let incoming = try Self.normalized(record.entry)
            var document = next.documents[record.id.documentKey] ?? Document()
            if let fields = record.systemFields { document.systemFields[record.id.key] = fields }
            if let previous = document.incoming[record.id.key] {
                let winner = try Self.winner(previous, incoming)
                Self.preserve(id: record.id, first: previous, second: incoming, winner: winner, in: &next)
                document.incoming[record.id.key] = winner
            } else {
                document.incoming[record.id.key] = incoming
            }
            var receipts = document.incomingReceipts ?? [:]
            receipts[record.id.key] = incoming
            document.incomingReceipts = receipts
            // Retain a prior staged target until replay replaces it. It still identifies
            // already-applied store content when a newer fetch arrives after a failed ack.
            next.documents[record.id.documentKey] = document
        }
        try commit(next)
    }

    /// Returns the document keys successfully applied. Failed/unready adapters keep their
    /// incoming versions durably replayable while other independent stores can make progress.
    @discardableResult
    func replayIncoming(using adapters: [String: any SavySyncAdapter], generation: UInt64) throws -> Set<String> {
        try requireGeneration(generation)
        var applied: Set<String> = []
        for documentKey in archive.documents.keys.sorted() {
            guard var document = archive.documents[documentKey], !document.incoming.isEmpty,
                  let adapter = adapters[documentKey], adapter.isReady else { continue }
            var target = document.entries
            var pending = document.pending
            var prepared = archive
            for (key, incoming) in document.incoming {
                let id = SavyCloudRecordID(documentKey: documentKey, key: key)
                let winner: SyncEntry
                if let previous = target[key] {
                    winner = try Self.winner(previous, incoming)
                    Self.preserve(id: id, first: previous, second: incoming, winner: winner, in: &prepared)
                } else {
                    winner = incoming
                }
                target[key] = winner
                if winner == document.incomingReceipts?[key] {
                    pending.removeValue(forKey: key)
                } else {
                    pending[key] = winner
                }
            }
            // If B reached the store but its final journal confirmation failed, staging C
            // must preserve recognition of B when C's store write later fails. Replace
            // this one slot only after observing the prior target in the actual adapter.
            if let previousTarget = document.applyTarget, adapter.snapshot() == Self.liveValues(previousTarget) {
                document.materializedTarget = previousTarget
            }
            document.applyTarget = target
            prepared.documents[documentKey] = document
            // Originals and target reach disk before the local record can be overwritten.
            try commit(prepared)
            try requireGeneration(generation)
            guard adapter.applyAndConfirm(Self.liveValues(target)) else { continue }
            try requireGeneration(generation)
            document.entries = target
            document.pending = pending
            document.incoming = [:]
            document.incomingReceipts = nil
            document.applyTarget = nil
            document.materializedTarget = nil
            document.initialized = true
            var confirmed = archive
            confirmed.documents[documentKey] = document
            try commit(confirmed)
            applied.insert(documentKey)
        }
        return applied
    }

    /// An old save response may refresh its CloudKit change tag, but only the exact portable
    /// version sent by that operation can remove the pending version currently on this device.
    func acknowledgeSaved(_ records: [SavyCloudRecord], generation: UInt64) throws {
        try requireGeneration(generation)
        var next = archive
        for record in records {
            let saved = try Self.normalized(record.entry)
            guard var document = next.documents[record.id.documentKey] else { continue }
            if let fields = record.systemFields { document.systemFields[record.id.key] = fields }
            if document.pending[record.id.key] == saved { document.pending.removeValue(forKey: record.id.key) }
            next.documents[record.id.documentKey] = document
        }
        try commit(next)
    }

    func persistEngineState(_ serialization: Data?, generation: UInt64) throws {
        try requireGeneration(generation)
        var next = archive
        next.engineState = serialization
        try commit(next)
    }

    /// The foreground zone cursor is opaque and independent of the engine checkpoint.
    /// Retain fetched records durably before advancing this cursor in the same journal.
    func persistForegroundChangeToken(_ data: Data?, generation: UInt64) throws {
        try requireGeneration(generation)
        var next = archive
        next.foregroundChangeToken = data
        try commit(next)
    }

    /// Deterministic in either receive order: later date, then deletion, then canonical live JSON.
    static func winner(_ first: SyncEntry, _ second: SyncEntry) throws -> SyncEntry {
        let first = try normalized(first), second = try normalized(second)
        if first.modifiedAt != second.modifiedAt { return first.modifiedAt > second.modifiedAt ? first : second }
        if first.deleted != second.deleted { return first.deleted ? first : second }
        if first.deleted || first.value == second.value { return first }
        let a = try canonicalData(first.value!), b = try canonicalData(second.value!)
        return a.lexicographicallyPrecedes(b) ? second : first
    }

    private static func newest(_ first: SyncEntry?, _ second: SyncEntry?) throws -> SyncEntry? {
        switch (first, second) {
        case let (first?, second?): try winner(first, second)
        case let (first?, nil): first
        case let (nil, second?): second
        case (nil, nil): nil
        }
    }

    private static func normalized(_ entry: SyncEntry) throws -> SyncEntry {
        guard entry.modifiedAt.isFinite else { throw SavyCloudSyncStateError.invalidRecord }
        if entry.deleted { return SyncEntry(value: nil, modifiedAt: entry.modifiedAt, deleted: true) }
        guard let value = entry.value else { throw SavyCloudSyncStateError.invalidRecord }
        _ = try canonicalData(value)
        return entry
    }

    private static func canonicalData(_ value: SyncJSON) throws -> Data {
        try JSONSerialization.data(withJSONObject: value.anyValue, options: [.sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes])
    }

    private static func liveValues(_ entries: [String: SyncEntry]) -> [String: SyncJSON] {
        entries.reduce(into: [:]) { values, pair in
            if !pair.value.deleted, let value = pair.value.value { values[pair.key] = value }
        }
    }

    private static func preserve(id: SavyCloudRecordID, first: SyncEntry, second: SyncEntry, winner: SyncEntry, in archive: inout Archive) {
        guard first.value != second.value else { return }
        let displaced = winner == first ? second : first
        let conflict = SavyCloudConflict(id: id, displaced: displaced, retained: winner)
        if !archive.conflicts.contains(conflict) { archive.conflicts.append(conflict) }
    }

    private func requireGeneration(_ candidate: UInt64) throws {
        guard canTransport(generation: candidate) else { throw SavyCloudSyncStateError.staleGeneration }
    }

    private func records(_ keyPath: KeyPath<Document, [String: SyncEntry]>) -> [SavyCloudRecord] {
        archive.documents.keys.sorted().flatMap { documentKey in
            let document = archive.documents[documentKey]!
            return document[keyPath: keyPath].keys.sorted().map { key in
                SavyCloudRecord(id: SavyCloudRecordID(documentKey: documentKey, key: key),
                                entry: document[keyPath: keyPath][key]!, systemFields: document.systemFields[key])
            }
        }
    }

    /// Throwing and atomic. A failed encode or write never advances the in-memory journal.
    private func commit(_ next: Archive) throws {
        guard next != archive else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(next)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: [.atomic])
        archive = next
    }
}
