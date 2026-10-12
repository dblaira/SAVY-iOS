import CloudKit
import Combine
import CryptoKit
import Foundation

enum SavyCloudKitTransportError: Error {
    case invalidRecord
    case invalidSystemFields
    case invalidCheckpoint
    case invalidForegroundToken
    case checkpointBlocked
    case invalidSafetyState
    case recoveryHeld
}

/// Notifications may arrive off the main actor while an identity request is suspended.
/// This tiny locked epoch invalidates that request synchronously at notification delivery.
private final class SavyCloudKitAccountEpoch: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 0
    func current() -> UInt64 { lock.withLock { value } }
    func advance() { lock.withLock { value += 1 } }
}

/// Pure record conversion. Creating records, scopes and secure archives here never opens
/// a container, database, subscription or network connection.
enum SavyCloudKitRecordCodec {
    static let containerIdentifier = "iCloud.com.adamblair.harness"
    static let zoneName = "SAVYEntriesV1"
    static let recordType = "SAVYRecordV1"
    static let subscriptionIdentifier = "SAVYEntriesV1.PrivateSubscription"
    static let environment = "Development"
    static let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)

    private struct Payload: Codable {
        var formatVersion: Int
        var id: SavyCloudRecordID
        var entry: SyncEntry
    }

    static func recordID(for id: SavyCloudRecordID) -> CKRecord.ID {
        // Length-delimited input prevents ambiguous concatenation. Hashing also keeps
        // long source keys and authored source identifiers out of CloudKit record names.
        let input = "\(id.documentKey.utf8.count):\(id.documentKey)\(id.key.utf8.count):\(id.key)"
        let digest = SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
        return .init(recordName: "\(recordType):\(digest)", zoneID: zoneID)
    }

    static func owns(_ id: CKRecord.ID) -> Bool { id.zoneID == zoneID }

    static func fetchOptions() -> CKSyncEngine.FetchChangesOptions {
        .init(scope: .zoneIDs([zoneID]))
    }

    static func sendOptions() -> CKSyncEngine.SendChangesOptions {
        .init(scope: .zoneIDs([zoneID]))
    }

    static func encode(_ source: SavyCloudRecord) throws -> CKRecord {
        let entry = try normalized(source.entry)
        let id = recordID(for: source.id)
        let record: CKRecord
        if let fields = source.systemFields {
            record = try restoreSystemFields(fields)
            guard record.recordType == recordType, record.recordID == id else {
                throw SavyCloudKitTransportError.invalidSystemFields
            }
        } else {
            record = CKRecord(recordType: recordType, recordID: id)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(Payload(formatVersion: 1, id: source.id, entry: entry))
        record["schemaVersion"] = NSNumber(value: 1)
        record.encryptedValues["payload"] = data as NSData
        return record
    }

    static func decodeIfOwned(_ record: CKRecord, documents: Set<String>) throws -> SavyCloudRecord? {
        guard owns(record.recordID) else { return nil }
        return try decode(record, documents: documents)
    }

    static func decode(_ record: CKRecord, documents: Set<String>) throws -> SavyCloudRecord {
        guard owns(record.recordID), record.recordType == recordType,
              (record["schemaVersion"] as? NSNumber)?.intValue == 1,
              let data = record.encryptedValues["payload"] as? Data else {
            throw SavyCloudKitTransportError.invalidRecord
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard payload.formatVersion == 1, documents.contains(payload.id.documentKey),
              !payload.id.key.isEmpty, recordID(for: payload.id) == record.recordID else {
            throw SavyCloudKitTransportError.invalidRecord
        }
        return .init(id: payload.id, entry: try normalized(payload.entry),
                     systemFields: try systemFields(of: record))
    }

    static func systemFields(of record: CKRecord) throws -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        if let error = archiver.error { throw error }
        return archiver.encodedData
    }

    static func restoreSystemFields(_ data: Data) throws -> CKRecord {
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = true
        unarchiver.decodingFailurePolicy = .setErrorAndReturn
        defer { unarchiver.finishDecoding() }
        guard let record = CKRecord(coder: unarchiver), unarchiver.error == nil else {
            throw SavyCloudKitTransportError.invalidSystemFields
        }
        return record
    }

    static func foregroundToken(from data: Data?) throws -> CKServerChangeToken? {
        guard let data else { return nil }
        guard let token = try NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data) else {
            throw SavyCloudKitTransportError.invalidForegroundToken
        }
        return token
    }

    static func foregroundTokenData(_ token: CKServerChangeToken) throws -> Data {
        try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    private static func normalized(_ entry: SyncEntry) throws -> SyncEntry {
        guard entry.modifiedAt.isFinite, entry.deleted || entry.value != nil else {
            throw SavyCloudKitTransportError.invalidRecord
        }
        if entry.deleted { return .init(value: nil, modifiedAt: entry.modifiedAt, deleted: true) }
        _ = try JSONEncoder().encode(entry)
        return entry
    }
}

/// The same bridge is used by the real engine delegate and the container-free transport
/// checks. It owns no engine; every remote mutation still passes the durable U1 journal.
@MainActor
final class SavyCloudKitTransportBridge {
    private struct Safety: Codable {
        var formatVersion = 1
        var containerIdentifier = SavyCloudKitRecordCodec.containerIdentifier
        var environment = SavyCloudKitRecordCodec.environment
        var zoneName = SavyCloudKitRecordCodec.zoneName
        var confirmedZone = false
        var recoveryReason: String? = nil
    }

    let state: SavyCloudSyncState
    let adapters: [String: any SavySyncAdapter]
    private let safetyURL: URL
    private let legacyDevice: Bool
    private var safety: Safety
    private(set) var fetchedInitialChanges = false
    private(set) var checkpointBlocked = false
    private(set) var preparationFailureCount = 0

    // Asset integration can prepare stable upload files and atomically retain fetched
    // bytes before the referencing entry reaches the journal or any local store.
    var prepareOutgoingRecord: ((CKRecord, SavyCloudRecord) throws -> Void)?
    var prepareIncomingRecord: ((CKRecord, SavyCloudRecord) throws -> Void)?
    var recordPreparationFailed: ((SavyCloudRecordID, Error) -> Void)?

    var recoveryReason: String? { safety.recoveryReason }
    var hasConfirmedZone: Bool { safety.confirmedZone }

    func acceptsInitialSignIn(_ change: CKSyncEngine.Event.AccountChange.ChangeType, generation: UInt64) -> Bool {
        guard state.canTransport(generation: generation), case .signIn(let user) = change else { return false }
        return user.recordName == state.originalOwner
    }

    /// References belong to their records. Report a real offline collision while keeping
    /// both numbers, rather than silently changing a reference Adam already used.
    var postNumberCollisions: [Int: [SavyCloudRecordID]] {
        var references: [Int: [SavyCloudRecordID]] = [:]
        for document in ["reminders", "social-posts"] {
            guard let adapter = adapters[document], adapter.isReady else { continue }
            for (key, value) in adapter.snapshot() {
                guard case .object(let fields) = value,
                      document != "reminders" || fields["kind"]?.stringValue == "post",
                      fields["status"]?.stringValue != "deleted",
                      let number = fields["postNumber"]?.numberValue, number.isFinite,
                      number > 0, number < Double(Int.max), number.rounded() == number else { continue }
                references[Int(number), default: []].append(.init(documentKey: document, key: key))
            }
        }
        return references.filter { $0.value.count > 1 }
    }

    init(state: SavyCloudSyncState, adapters: [String: any SavySyncAdapter], safetyURL: URL, legacyDevice: Bool = true) throws {
        self.state = state
        self.adapters = adapters
        self.safetyURL = safetyURL
        self.legacyDevice = legacyDevice
        if FileManager.default.fileExists(atPath: safetyURL.path) {
            safety = try JSONDecoder().decode(Safety.self, from: Data(contentsOf: safetyURL))
            guard safety.formatVersion == 1,
                  safety.containerIdentifier == SavyCloudKitRecordCodec.containerIdentifier,
                  safety.environment == SavyCloudKitRecordCodec.environment,
                  safety.zoneName == SavyCloudKitRecordCodec.zoneName else {
                throw SavyCloudKitTransportError.invalidSafetyState
            }
        } else { safety = Safety() }
    }

    func resetFetchGate() { fetchedInitialChanges = false }

    func observeLocalChanges(now: Double) throws {
        for adapter in adapters.values where adapter.isReady {
            _ = try state.observeLocal(adapter: adapter, legacyDevice: legacyDevice, now: now)
        }
    }

    func confirmZone(generation: UInt64) throws {
        try requireGeneration(generation)
        guard recoveryReason == nil else { throw SavyCloudKitTransportError.recoveryHeld }
        if !safety.confirmedZone {
            var next = safety
            next.confirmedZone = true
            try saveSafety(next)
            safety = next
        }
    }

    func fetchedChangesFinished(generation: UInt64) throws {
        try requireGeneration(generation)
        guard !checkpointBlocked, recoveryReason == nil else { throw SavyCloudKitTransportError.checkpointBlocked }
        try confirmZone(generation: generation)
        fetchedInitialChanges = true
    }

    func pendingReadyToSend(generation: UInt64) -> [SavyCloudRecord] {
        guard state.canTransport(generation: generation), fetchedInitialChanges,
              !checkpointBlocked, recoveryReason == nil else { return [] }
        let inboxDocuments = Set(state.incomingRecords.map { $0.id.documentKey })
        return state.pendingRecords.filter {
            adapters[$0.id.documentKey]?.isReady == true && !inboxDocuments.contains($0.id.documentKey)
        }
    }

    func pendingBatch(generation: UInt64,
                      scope: CKSyncEngine.SendChangesOptions.Scope = .zoneIDs([SavyCloudKitRecordCodec.zoneID])) throws -> CKSyncEngine.RecordZoneChangeBatch? {
        let sources = pendingReadyToSend(generation: generation).filter {
            scope.contains(SavyCloudKitRecordCodec.recordID(for: $0.id))
        }
        preparationFailureCount = 0
        guard !sources.isEmpty else { return nil }
        var records: [CKRecord] = []
        for source in sources {
            do {
                let record = try SavyCloudKitRecordCodec.encode(source)
                try prepareOutgoingRecord?(record, source)
                records.append(record)
                if records.count == 200 { break }
            } catch {
                preparationFailureCount += 1
                recordPreparationFailed?(source.id, error)
            }
        }
        guard !records.isEmpty else { return nil }
        // User deletions are records with dated tombstones. Never issue hard deletes.
        return .init(recordsToSave: records, recordIDsToDelete: [], atomicByZone: false)
    }

    func receive(_ records: [CKRecord], generation: UInt64) throws {
        try requireGeneration(generation)
        guard recoveryReason == nil else { throw SavyCloudKitTransportError.recoveryHeld }
        let owned = records.filter { SavyCloudKitRecordCodec.owns($0.recordID) }
        // An empty scoped fetch must replay an inbox retained by an earlier process.
        // A nonempty foreign batch remains entirely ignored.
        if owned.isEmpty {
            if records.isEmpty {
                try observeLocalChanges(now: Date().timeIntervalSince1970)
                _ = try state.replayIncoming(using: adapters, generation: generation)
            }
            return
        }
        let decoded: [SavyCloudRecord]
        do {
            decoded = try owned.map { try SavyCloudKitRecordCodec.decode($0, documents: Set(adapters.keys)) }
            for (record, source) in zip(owned, decoded) { try prepareIncomingRecord?(record, source) }
            // A saved user edit can precede its debounced publisher. Capture it before
            // any fetched/conflicting version is allowed to replace the actual store.
            try observeLocalChanges(now: Date().timeIntervalSince1970)
            try state.retainIncoming(decoded, generation: generation)
        } catch {
            // This engine already advanced its in-memory token. No later empty fetch may
            // unblock it; the service drops it and reconstructs from the durable token.
            checkpointBlocked = true
            throw error
        }
        // An apply failure is safe to checkpoint only because incoming is already on disk.
        _ = try state.replayIncoming(using: adapters, generation: generation)
    }

    func receiveServerConflict(_ error: CKError, generation: UInt64) throws {
        try requireGeneration(generation)
        guard error.code == .serverRecordChanged, let server = error.serverRecord else {
            checkpointBlocked = true
            throw SavyCloudKitTransportError.invalidRecord
        }
        try receive([server], generation: generation)
    }

    func acknowledgeSaved(_ records: [CKRecord], generation: UInt64) throws {
        try requireGeneration(generation)
        let owned = records.filter { SavyCloudKitRecordCodec.owns($0.recordID) }
        guard !owned.isEmpty else { return }
        let decoded = try owned.map { try SavyCloudKitRecordCodec.decode($0, documents: Set(adapters.keys)) }
        try state.acknowledgeSaved(decoded, generation: generation)
    }

    func persistCheckpoint(_ data: Data, generation: UInt64) throws {
        try requireGeneration(generation)
        guard !checkpointBlocked, recoveryReason == nil else { throw SavyCloudKitTransportError.checkpointBlocked }
        try state.persistEngineState(data, generation: generation)
    }

    /// A foreground page advances only after its assets and incoming records are durable.
    /// Store failures leave the inbox replayable; receipt or asset failures retain the old cursor.
    func receiveForegroundPage(_ records: [CKRecord], deletedIDs: [CKRecord.ID], token: Data,
                               generation: UInt64) throws {
        try requireGeneration(generation)
        guard !checkpointBlocked, recoveryReason == nil else { throw SavyCloudKitTransportError.checkpointBlocked }
        guard records.allSatisfy({ SavyCloudKitRecordCodec.owns($0.recordID) }),
              deletedIDs.allSatisfy(SavyCloudKitRecordCodec.owns) else { throw SavyCloudKitTransportError.invalidRecord }
        try recordsWereHardDeleted(deletedIDs, generation: generation)
        guard recoveryReason == nil else { throw SavyCloudKitTransportError.recoveryHeld }
        try receive(records, generation: generation)
        try state.persistForegroundChangeToken(token, generation: generation)
    }

    func recordsWereHardDeleted(_ ids: [CKRecord.ID], generation: UInt64) throws {
        guard ids.contains(where: SavyCloudKitRecordCodec.owns) else { return }
        try requireGeneration(generation)
        try holdForRecovery("unexpectedRecordDeletion")
    }

    func zoneWasDeleted(_ zoneID: CKRecordZone.ID, generation: UInt64) throws {
        guard zoneID == SavyCloudKitRecordCodec.zoneID else { return }
        try requireGeneration(generation)
        try holdForRecovery("unexpectedZoneDeletion")
    }

    private func holdForRecovery(_ reason: String) throws {
        // Block immediately even if persisting this diagnostic boundary fails. Existing
        // confirmed-zone metadata also prevents recreation before refetch on relaunch.
        safety.recoveryReason = reason
        fetchedInitialChanges = false
        checkpointBlocked = true
        try saveSafety(safety)
    }

    private func saveSafety(_ next: Safety) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(next)
        try FileManager.default.createDirectory(at: safetyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: safetyURL, options: .atomic)
    }

    private func requireGeneration(_ generation: UInt64) throws {
        guard state.canTransport(generation: generation) else { throw SavyCloudSyncStateError.staleGeneration }
    }
}

/// Native private-iCloud transport beside SAVY's immediate local saves. Initialization and
/// disabled starts are side-effect free; account access begins only in an enabled start.
@MainActor
final class CloudKitDocumentSync: ObservableObject, CKSyncEngineDelegate {
    @Published private(set) var status = "idle"
    @Published private(set) var lastError: String?

    private struct Diagnostics: Encodable {
        var status: String
        var error: String?
        var recoveryReason: String?
        var ownerIdentifier: String?
        var generation: UInt64
        var pendingCount: Int
        var incomingCount: Int
        var conflictCount: Int
        var localRecordCount: Int
        var lastFetch: Date?
        var lastForegroundFetch: Date?
        var lastForegroundFetchedRecordCount: Int
        var hasForegroundCursor: Bool
        var lastSave: Date?
        var lastFetchedRecordCount: Int
        var lastSavedRecordCount: Int
        var recordPreparationFailureCount: Int
        var activeSyncTrigger: String
        var postNumberCollisions: [Int: [SavyCloudRecordID]]
        var containerIdentifier = SavyCloudKitRecordCodec.containerIdentifier
        var zoneName = SavyCloudKitRecordCodec.zoneName
        var environment = SavyCloudKitRecordCodec.environment
    }

    private let adapters: [any SavySyncAdapter]
    private let legacyDevice: Bool
    private let enabled: Bool
    private let accountCheckOnly: Bool
    private let requestedStateURL: URL?
    private var state: SavyCloudSyncState?
    private var bridge: SavyCloudKitTransportBridge?
    private var container: CKContainer?
    private var engine: CKSyncEngine?
    private var engineGeneration: UInt64?
    private var engineAccountEpoch: UInt64?
    private var verifiedOwnerEpoch: UInt64?
    private var subscriptions: Set<AnyCancellable> = []
    private var started = false
    private var isSyncing = false
    private var isForegroundFetching = false
    private var syncRequested = false
    private let accountEpoch = SavyCloudKitAccountEpoch()
    private var fetchError: CKError?
    private var sendHadError = false
    private var lastFetch: Date?
    private var lastForegroundFetch: Date?
    private var foregroundFetchedRecordCount = 0
    private var foregroundRetryAfter: Date?
    private var lastSave: Date?
    private var fetchedRecordCount = 0
    private var savedRecordCount = 0
    private var activeSyncTrigger = "launch"

    // Root's CKAsset integration installs these hooks before start. They stay optional for
    // records without images and for the disabled, container-free lifecycle checks.
    var prepareOutgoingRecord: ((CKRecord, SavyCloudRecord) throws -> Void)?
    var prepareIncomingRecord: ((CKRecord, SavyCloudRecord) throws -> Void)?

    init(adapters: [any SavySyncAdapter], legacyDevice: Bool, enabled: Bool = true, stateURL: URL? = nil,
         accountCheckOnly: Bool = false) {
        self.adapters = adapters
        self.legacyDevice = legacyDevice
        self.enabled = enabled
        self.requestedStateURL = stateURL
        self.accountCheckOnly = accountCheckOnly
    }

    func start() async {
        guard enabled else { status = "disabled"; return }
        guard !started else { await syncNow(); return }
        do {
            let url = resolvedStateURL
            let state = try SavyCloudSyncState(fileURL: url)
            let indexed = Dictionary(uniqueKeysWithValues: adapters.map { ($0.documentKey, $0) })
            let bridge = try makeBridge(state: state, adapters: indexed)
            self.state = state
            self.bridge = bridge
            started = true
            _ = observeLocalChanges()
            let epoch = accountEpoch
            NotificationCenter.default.publisher(for: .CKAccountChanged)
                .sink { [weak self, epoch] _ in
                    epoch.advance()
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.discardEngine()
                        do { try self.state?.accountChanged(to: nil); self.setStatus("accountUnavailable") }
                        catch { self.reportFailure(error) }
                        await self.syncNow()
                    }
                }.store(in: &subscriptions)
            for adapter in adapters {
                // Store publishers can fire before @Published assigns the new snapshot.
                // A main-actor task reads after that synchronous save returns. Journal
                // this independently of both network debouncing and an in-flight fetch.
                adapter.localChanges.sink { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        _ = self.observeLocalChanges()
                        self.writeDiagnostics()
                    }
                }.store(in: &subscriptions)
                adapter.localChanges.debounce(for: .milliseconds(450), scheduler: RunLoop.main)
                    .sink { [weak self] in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            self.activeSyncTrigger = "localChange"
                            await self.syncNow()
                        }
                    }.store(in: &subscriptions)
            }
            await syncNow()
        } catch { reportFailure(error) }
    }

    func syncNow() async {
        guard enabled else { return }
        guard started else { await start(); return }
        guard observeLocalChanges() else { return }
        guard !isSyncing else { syncRequested = true; return }
        guard state != nil else { return }
        if let foregroundRetryAfter, foregroundRetryAfter > Date() { return }
        isSyncing = true
        isForegroundFetching = true
        bridge?.resetFetchGate()
        defer {
            isSyncing = false
            isForegroundFetching = false
            if syncRequested {
                syncRequested = false
                Task { @MainActor [weak self] in await self?.syncNow() }
            }
        }
        do {
            guard try await verifyCurrentOwner() else { return }
            guard !accountCheckOnly else { setStatus("accountReady"); return }
            guard bridge?.recoveryReason == nil else { setStatus("recoveryHeld"); return }
            if engine == nil { try createEngine() }
            guard let engine, let bridge, let generation = engineGeneration,
                  isCurrent(engine, generation: generation) else { return }
            try bridge.receive([], generation: generation)
            if !bridge.hasConfirmedZone {
                engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: SavyCloudKitRecordCodec.zoneID))])
                // No records are available from the provider until initial fetch succeeds.
                try await engine.sendChanges(SavyCloudKitRecordCodec.sendOptions())
                guard isCurrent(engine, generation: generation), bridge.hasConfirmedZone else { return }
            }
            guard try await fetchForegroundChanges(engine: engine, bridge: bridge, generation: generation) else { return }
            isForegroundFetching = false
            fetchError = nil
            try await engine.fetchChanges(SavyCloudKitRecordCodec.fetchOptions())
            guard isCurrent(engine, generation: generation), fetchError == nil,
                  !bridge.checkpointBlocked else { return }
            try bridge.receive([], generation: generation)
            try bridge.fetchedChangesFinished(generation: generation)
            lastFetch = Date()
            enqueuePending(in: engine, generation: generation)
            try await engine.sendChanges(SavyCloudKitRecordCodec.sendOptions())
            guard isCurrent(engine, generation: generation) else { return }
            if !sendHadError {
                if bridge.preparationFailureCount == 0 { lastError = nil }
                settleStatus()
            }
        } catch {
            if bridge?.checkpointBlocked == true { discardEngine() }
            if let cloudError = error as? CKError { handleCloudFailure(cloudError) }
            else { reportFailure(error) }
        }
    }

    /// CKSyncEngine remains the automatic transport. This separately checkpointed, scoped
    /// delta fetch supplies the foreground correctness floor when a long-lived engine's
    /// manual fetch reports success without delivering a newer record until relaunch.
    private func fetchForegroundChanges(engine: CKSyncEngine, bridge: SavyCloudKitTransportBridge,
                                        generation: UInt64) async throws -> Bool {
        guard let state, let container, isCurrent(engine, generation: generation) else { return false }
        var token = try SavyCloudKitRecordCodec.foregroundToken(from: state.foregroundChangeToken)
        var retriedExpiredToken = false
        foregroundFetchedRecordCount = 0
        while isCurrent(engine, generation: generation) {
            do {
                let page = try await container.privateCloudDatabase.recordZoneChanges(
                    inZoneWith: SavyCloudKitRecordCodec.zoneID, since: token, desiredKeys: nil, resultsLimit: 200)
                guard isCurrent(engine, generation: generation) else { return false }
                // A partial failure must not discard that record by advancing the page cursor.
                let records = try page.modificationResultsByID.values.map { try $0.get().record }
                try bridge.receiveForegroundPage(records, deletedIDs: page.deletions.map(\.recordID),
                    token: SavyCloudKitRecordCodec.foregroundTokenData(page.changeToken), generation: generation)
                foregroundFetchedRecordCount += records.count
                token = page.changeToken
                if !page.moreComing {
                    lastForegroundFetch = Date()
                    foregroundRetryAfter = nil
                    writeDiagnostics()
                    return true
                }
            } catch let error as CKError where error.code == .changeTokenExpired && !retriedExpiredToken {
                guard isCurrent(engine, generation: generation) else { return false }
                // Refetch this zone while retaining every local version and durable tombstone.
                try state.persistForegroundChangeToken(nil, generation: generation)
                token = nil
                retriedExpiredToken = true
            }
        }
        return false
    }

    private var resolvedStateURL: URL {
        requestedStateURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SAVY/CloudKit/state.json")
    }

    private func makeBridge(state: SavyCloudSyncState, adapters: [String: any SavySyncAdapter]) throws -> SavyCloudKitTransportBridge {
        let bridge = try SavyCloudKitTransportBridge(state: state, adapters: adapters,
            safetyURL: resolvedStateURL.deletingLastPathComponent().appendingPathComponent("safety.json"), legacyDevice: legacyDevice)
        bridge.prepareOutgoingRecord = prepareOutgoingRecord
        bridge.prepareIncomingRecord = prepareIncomingRecord
        bridge.recordPreparationFailed = { [weak self] _, error in self?.reportFailure(error) }
        return bridge
    }

    private func observeLocalChanges() -> Bool {
        guard let bridge else { return false }
        do { try bridge.observeLocalChanges(now: Date().timeIntervalSince1970); return true }
        catch { reportFailure(error); return false }
    }

    /// Identity requests carry no SAVY writing. Recheck before manual work and delegate
    /// fetch/send providers, rather than trusting a previous launch's owner verification.
    private func verifyCurrentOwner(expectedEngine: CKSyncEngine? = nil) async throws -> Bool {
        guard enabled, let state else { return false }
        let revision = accountEpoch.current()
        if container == nil { container = CKContainer(identifier: SavyCloudKitRecordCodec.containerIdentifier) }
        guard let container else { return false }
        let account = try await container.accountStatus()
        guard revision == accountEpoch.current() else { return false }
        if let expectedEngine, engine !== expectedEngine { return false }
        guard account == .available else {
            try state.accountChanged(to: nil)
            discardEngine()
            setStatus("accountUnavailable")
            return false
        }
        let identifier = try await container.userRecordID().recordName
        guard revision == accountEpoch.current() else { return false }
        if let expectedEngine, engine !== expectedEngine { return false }
        let authorization = try state.accountChanged(to: identifier)
        if engineGeneration != nil && engineGeneration != state.generation { discardEngine() }
        guard authorization == .authorized else {
            discardEngine()
            setStatus("differentAccount")
            return false
        }
        verifiedOwnerEpoch = revision
        return true
    }

    private func createEngine() throws {
        guard !accountCheckOnly, let state, let bridge, let container,
              let verifiedOwnerEpoch, verifiedOwnerEpoch == accountEpoch.current(),
              state.canTransport(generation: state.generation), bridge.recoveryReason == nil else { return }
        let serialization: CKSyncEngine.State.Serialization?
        if let data = state.engineState {
            do { serialization = try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data) }
            catch { throw SavyCloudKitTransportError.invalidCheckpoint }
        } else { serialization = nil }
        // A fresh bridge is required after a failed receive. Its gate starts closed and
        // the restored engine refetches from the last durably confirmed serialization.
        if bridge.checkpointBlocked {
            self.bridge = try makeBridge(state: state, adapters: bridge.adapters)
        }
        self.bridge?.resetFetchGate()
        var configuration = CKSyncEngine.Configuration(database: container.privateCloudDatabase,
                                                       stateSerialization: serialization, delegate: self)
        configuration.automaticallySync = true
        configuration.subscriptionID = SavyCloudKitRecordCodec.subscriptionIdentifier
        let created = CKSyncEngine(configuration)
        engine = created
        engineGeneration = state.generation
        engineAccountEpoch = verifiedOwnerEpoch
        // The journal is authoritative. Restored engine queues can contain an older
        // version or a hard-delete intent; rebuild only SAVY saves after the first fetch.
        created.state.remove(pendingRecordZoneChanges: created.state.pendingRecordZoneChanges)
        created.state.remove(pendingDatabaseChanges: created.state.pendingDatabaseChanges)
        setStatus("fetching")
    }

    private func isCurrent(_ candidate: CKSyncEngine, generation: UInt64) -> Bool {
        engine === candidate && engineGeneration == generation
            && engineAccountEpoch == accountEpoch.current()
            && state?.canTransport(generation: generation) == true
    }

    private func discardEngine() {
        let old = engine
        engine = nil
        engineGeneration = nil
        engineAccountEpoch = nil
        verifiedOwnerEpoch = nil
        bridge?.resetFetchGate()
        // Delegate callbacks are serial. Cancellation occurs after the callback returns.
        if let old { Task { await Task.yield(); await old.cancelOperations() } }
    }

    private func enqueuePending(in engine: CKSyncEngine, generation: UInt64) {
        guard isCurrent(engine, generation: generation), let bridge else { return }
        let desired = Set(bridge.pendingReadyToSend(generation: generation).map {
            SavyCloudKitRecordCodec.recordID(for: $0.id)
        })
        let obsolete = engine.state.pendingRecordZoneChanges.filter {
            switch $0 {
            case .saveRecord(let id): !SavyCloudKitRecordCodec.owns(id) || !desired.contains(id)
            case .deleteRecord: true
            @unknown default: true
            }
        }
        engine.state.remove(pendingRecordZoneChanges: obsolete)
        engine.state.add(pendingRecordZoneChanges: desired.map(CKSyncEngine.PendingRecordZoneChange.saveRecord))
        let foreignDatabaseChanges = engine.state.pendingDatabaseChanges.filter {
            switch $0 {
            case .saveZone(let zone): zone.zoneID != SavyCloudKitRecordCodec.zoneID
            case .deleteZone: true
            @unknown default: true
            }
        }
        engine.state.remove(pendingDatabaseChanges: foreignDatabaseChanges)
    }

    func nextFetchChangesOptions(_ context: CKSyncEngine.FetchChangesContext,
                                 syncEngine: CKSyncEngine) async -> CKSyncEngine.FetchChangesOptions {
        var options = context.options
        options.scope = .zoneIDs([])
        options.prioritizedZoneIDs = []
        guard let generation = engineGeneration, isCurrent(syncEngine, generation: generation),
              bridge?.recoveryReason == nil else { return options }
        do {
            guard try await verifyCurrentOwner(expectedEngine: syncEngine),
                  isCurrent(syncEngine, generation: generation) else { return options }
            options.scope = .zoneIDs([SavyCloudKitRecordCodec.zoneID])
            options.prioritizedZoneIDs = [SavyCloudKitRecordCodec.zoneID]
        } catch { reportFailure(error) }
        return options
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                   syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard !isForegroundFetching, let generation = engineGeneration, isCurrent(syncEngine, generation: generation),
              let bridge, bridge.fetchedInitialChanges else { return nil }
        do {
            guard try await verifyCurrentOwner(expectedEngine: syncEngine),
                  isCurrent(syncEngine, generation: generation) else { return nil }
            guard observeLocalChanges() else { return nil }
            return try bridge.pendingBatch(generation: generation, scope: context.options.scope)
        } catch { reportFailure(error); return nil }
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard engine === syncEngine else { return }
        if case .accountChange(let change) = event {
            if let generation = engineGeneration, isCurrent(syncEngine, generation: generation),
               let bridge, bridge.acceptsInitialSignIn(change.changeType, generation: generation) {
                // A fresh engine reports its first known identity as signIn. It is the
                // owner verified before creation, so retain the engine and its next
                // serialization. CloudKit resets pending queues for this event.
                if !bridge.hasConfirmedZone && bridge.recoveryReason == nil {
                    syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: SavyCloudKitRecordCodec.zoneID))])
                }
                Task { @MainActor [weak self] in await Task.yield(); await self?.syncNow() }
                return
            }
            accountEpoch.advance()
            discardEngine()
            do { try state?.accountChanged(to: nil); setStatus("accountUnavailable") }
            catch { reportFailure(error) }
            // Revalidate after returning, without awaiting engine work in its callback.
            Task { @MainActor [weak self] in await Task.yield(); await self?.syncNow() }
            return
        }
        guard let generation = engineGeneration, isCurrent(syncEngine, generation: generation),
              let state, let bridge else { return }
        do {
            switch event {
            case .stateUpdate(let update):
                try bridge.persistCheckpoint(JSONEncoder().encode(update.stateSerialization), generation: generation)
            case .fetchedDatabaseChanges(let changes):
                for deletion in changes.deletions where deletion.zoneID == SavyCloudKitRecordCodec.zoneID {
                    try bridge.zoneWasDeleted(deletion.zoneID, generation: generation)
                }
                if bridge.recoveryReason != nil { discardEngine(); setStatus("recoveryHeld"); return }
                if changes.modifications.contains(where: { $0.zoneID == SavyCloudKitRecordCodec.zoneID }) {
                    try bridge.confirmZone(generation: generation)
                }
            case .fetchedRecordZoneChanges(let changes):
                try bridge.recordsWereHardDeleted(changes.deletions.map(\.recordID), generation: generation)
                if bridge.recoveryReason != nil { discardEngine(); setStatus("recoveryHeld"); return }
                let records = changes.modifications.map(\.record).filter { SavyCloudKitRecordCodec.owns($0.recordID) }
                try bridge.receive(records, generation: generation)
                fetchedRecordCount += records.count
                enqueuePending(in: syncEngine, generation: generation)
            case .sentDatabaseChanges(let changes):
                if changes.savedZones.contains(where: { $0.zoneID == SavyCloudKitRecordCodec.zoneID }) {
                    try bridge.confirmZone(generation: generation)
                }
                for deletion in changes.deletedZoneIDs {
                    try bridge.zoneWasDeleted(deletion, generation: generation)
                }
                for failure in changes.failedZoneSaves where failure.zone.zoneID == SavyCloudKitRecordCodec.zoneID {
                    sendHadError = true
                    handleCloudFailure(failure.error)
                }
            case .sentRecordZoneChanges(let changes):
                let saved = changes.savedRecords.filter { SavyCloudKitRecordCodec.owns($0.recordID) }
                try bridge.acknowledgeSaved(saved, generation: generation)
                if !saved.isEmpty { lastSave = Date(); savedRecordCount += saved.count }
                try bridge.recordsWereHardDeleted(changes.deletedRecordIDs, generation: generation)
                for failure in changes.failedRecordSaves where SavyCloudKitRecordCodec.owns(failure.record.recordID) {
                    if failure.error.code == .serverRecordChanged {
                        try bridge.receiveServerConflict(failure.error, generation: generation)
                    } else {
                        sendHadError = true
                        handleCloudFailure(failure.error)
                    }
                }
                enqueuePending(in: syncEngine, generation: generation)
            case .willFetchChanges:
                fetchError = nil
                fetchedRecordCount = 0
                if !isSyncing { activeSyncTrigger = "automatic" }
            case .didFetchRecordZoneChanges(let change):
                guard change.zoneID == SavyCloudKitRecordCodec.zoneID else { return }
                if let error = change.error { fetchError = error; handleCloudFailure(error) }
                else { try bridge.confirmZone(generation: generation) }
            case .didFetchChanges:
                if !isForegroundFetching && fetchError == nil && !bridge.checkpointBlocked && bridge.hasConfirmedZone {
                    try bridge.receive([], generation: generation)
                    try bridge.fetchedChangesFinished(generation: generation)
                    lastFetch = Date()
                    enqueuePending(in: syncEngine, generation: generation)
                }
            case .willSendChanges:
                sendHadError = false
                savedRecordCount = 0
            case .didSendChanges:
                if !sendHadError { settleStatus() }
            case .willFetchRecordZoneChanges, .accountChange:
                break
            @unknown default:
                break
            }
            if bridge.recoveryReason != nil { discardEngine(); setStatus("recoveryHeld") }
            else { writeDiagnostics() }
            // Keep the state strongly referenced during each synchronous journal operation.
            _ = state
        } catch {
            reportFailure(error)
            if bridge.checkpointBlocked || bridge.recoveryReason != nil { discardEngine() }
        }
    }

    private func handleCloudFailure(_ error: CKError) {
        if let retryAfter = error.retryAfterSeconds {
            foregroundRetryAfter = Date().addingTimeInterval(max(0, retryAfter))
        }
        if let bridge, let generation = engineGeneration,
           (error.code == .userDeletedZone || (error.code == .zoneNotFound && bridge.hasConfirmedZone) || error.code == .unknownItem) {
            // A missing saved record may have been externally deleted. It has no SAVY
            // versioned delete timestamp, so never recreate it by copying a stale cache.
            do { try bridge.zoneWasDeleted(SavyCloudKitRecordCodec.zoneID, generation: generation) }
            catch { reportFailure(error) }
            discardEngine()
            setStatus("recoveryHeld")
            return
        }
        reportFailure(error)
    }

    private func settleStatus() {
        if bridge?.recoveryReason != nil { setStatus("recoveryHeld") }
        else if bridge?.postNumberCollisions.isEmpty == false { setStatus("postReferenceCollision") }
        else if bridge?.checkpointBlocked == true { setStatus("fetchNeedsRecovery") }
        else if state?.incomingRecords.isEmpty == false { setStatus("waitingForLocalWrite") }
        else if bridge?.preparationFailureCount ?? 0 > 0 { setStatus("waitingForRecordPreparation") }
        else if state?.pendingRecords.isEmpty == false { setStatus("pending") }
        else { setStatus("synced") }
    }

    private func reportFailure(_ error: Error) {
        lastError = Self.sanitized(error)
        status = bridge?.recoveryReason != nil ? "recoveryHeld" : "failed"
        writeDiagnostics()
    }

    private func setStatus(_ status: String) { self.status = status; writeDiagnostics() }

    private static func sanitized(_ error: Error) -> String {
        if let error = error as? CKError { return "CloudKit error \(error.code.rawValue)" }
        if let error = error as? SavyCloudSyncStateError {
            switch error {
            case .unreadableSource: return "Local source is unreadable"
            case .staleGeneration: return "Account generation changed"
            case .invalidRecord: return "Invalid portable record"
            case .invalidState: return "Invalid local sync journal"
            }
        }
        if error is SavyCloudKitTransportError { return "CloudKit record or checkpoint requires recovery" }
        let error = error as NSError
        // Deliberately exclude localized descriptions, payloads, URLs and error userInfo.
        return "Persistence error \(error.domain) \(error.code)"
    }

    private func writeDiagnostics() {
        guard enabled else { return }
        let diagnostics = Diagnostics(status: status, error: lastError, recoveryReason: bridge?.recoveryReason,
            ownerIdentifier: state?.originalOwner,
            generation: state?.generation ?? 0, pendingCount: state?.pendingRecords.count ?? 0,
            incomingCount: state?.incomingRecords.count ?? 0, conflictCount: state?.conflicts.count ?? 0,
            localRecordCount: adapters.filter(\.isReady).reduce(0) { $0 + $1.snapshot().count },
            lastFetch: lastFetch,
            lastForegroundFetch: lastForegroundFetch, lastForegroundFetchedRecordCount: foregroundFetchedRecordCount,
            hasForegroundCursor: state?.foregroundChangeToken != nil,
            lastSave: lastSave, lastFetchedRecordCount: fetchedRecordCount,
            lastSavedRecordCount: savedRecordCount, recordPreparationFailureCount: bridge?.preparationFailureCount ?? 0,
            activeSyncTrigger: activeSyncTrigger, postNumberCollisions: bridge?.postNumberCollisions ?? [:])
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let directory = resolvedStateURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try encoder.encode(diagnostics).write(to: directory.appendingPathComponent("status.json"), options: .atomic)
        } catch {
            status = "diagnosticWriteFailed"
            lastError = Self.sanitized(error)
        }
    }
}
