import CloudKit
import Combine
import Foundation

/// This isolated adapter has a real atomic file boundary. Failure checks obstruct that file,
/// so the transport must preserve incoming work instead of accepting a simulated success.
@MainActor
private final class TransportFileAdapter: SavySyncAdapter {
    let documentKey: String
    let fileURL: URL
    private(set) var values: [String: SyncJSON]
    var isReady = true
    let changes = PassthroughSubject<Void, Never>()
    var localChanges: AnyPublisher<Void, Never> { changes.eraseToAnyPublisher() }
    var applyCount = 0

    init(documentKey: String = "stories", fileURL: URL, values: [String: SyncJSON]) throws {
        self.documentKey = documentKey
        self.fileURL = fileURL
        self.values = values
        try JSONEncoder().encode(values).write(to: fileURL, options: .atomic)
    }
    func snapshot() -> [String: SyncJSON] { values }
    func stamp(key: String, value: SyncJSON, context: SyncChangeContext) -> SyncStamp {
        switch context {
        case .firstRun: .init(modifiedAt: 100, uploads: true)
        case let .change(previous, now): .init(modifiedAt: SyncChangeContext.stampAfter(previous, now: now), uploads: true)
        }
    }
    func save(_ values: [String: SyncJSON]) throws {
        try JSONEncoder().encode(values).write(to: fileURL, options: .atomic)
        self.values = values
        changes.send()
    }
    func apply(_ values: [String: SyncJSON]) { _ = applyAndConfirm(values) }
    func applyAndConfirm(_ values: [String: SyncJSON]) -> Bool {
        do {
            try JSONEncoder().encode(values).write(to: fileURL, options: .atomic)
            self.values = values
            applyCount += 1
            changes.send()
            return true
        } catch { return false }
    }
}

@main @MainActor
struct TransportChecks {
    struct Failure: Error { var message: String }
    static var checks = 0
    static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw Failure(message: message) }
        checks += 1
        print("PASS \(message)")
    }
    static func mustThrow(_ message: String, _ body: () throws -> Void) throws {
        do { try body() } catch { try check(true, message); return }
        try check(false, message)
    }
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("savy-transport-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try codecAndScopes()
        try conflictAndExactSave(directory)
        try incomingFailureAndCorruptFetch(directory)
        try emptyFetchReplaysRetainedIncoming(directory)
        try localEditWhileFetchIsInFlight(directory)
        try independentPreparationFailures(directory)
        try accountAndRestart(directory)
        try durableRecoveryHolds(directory)
        try postReferenceCollisions(directory)
        try initialSignIn(directory)
        try foregroundPageDurability(directory)
        try await disabledHasNoEffects(directory)
        print("\(checks) CloudKit transport checks passed; no container or engine created, no network API invoked")
    }
    static func portable(_ value: String, date: Double = 100, document: String = "stories", key: String = "story:one") -> SavyCloudRecord {
        .init(id: .init(documentKey: document, key: key), entry: .init(value: .string(value), modifiedAt: date, deleted: false))
    }
    static func foregroundPageDurability(_ directory: URL) throws {
        let (state, adapter, bridge) = try fixture(directory, "foreground-page")
        let original = try Data(contentsOf: adapter.fileURL)
        let oldCursor = Data("previous-opaque-cursor".utf8)
        let nextCursor = Data("next-opaque-cursor".utf8)
        try state.persistForegroundChangeToken(oldCursor, generation: state.generation)
        let remote = try SavyCloudKitRecordCodec.encode(portable("Foreground incoming original.  \n", date: 300))
        try FileManager.default.removeItem(at: adapter.fileURL)
        try FileManager.default.createDirectory(at: adapter.fileURL, withIntermediateDirectories: false)
        try bridge.receiveForegroundPage([remote], deletedIDs: [], token: nextCursor, generation: state.generation)
        let reopened = try SavyCloudSyncState(fileURL: state.fileURL)
        try check(reopened.foregroundChangeToken == nextCursor && reopened.incomingRecords.count == 1,
                  "foreground cursor advances past a blocked store only with its incoming original durable on restart")
        try reopened.accountChanged(to: "original-owner")
        let restored = try SavyCloudKitTransportBridge(state: reopened, adapters: ["stories": adapter],
            safetyURL: directory.appendingPathComponent("foreground-page-safety.json"))
        try FileManager.default.removeItem(at: adapter.fileURL)
        try original.write(to: adapter.fileURL)
        try restored.receiveForegroundPage([], deletedIDs: [], token: nextCursor, generation: reopened.generation)
        try check(reopened.incomingRecords.isEmpty && adapter.values["story:one"] == .string("Foreground incoming original.  \n"),
                  "empty foreground delta replays retained writing after an actual store repair")
        let (failedState, _, failedBridge) = try fixture(directory, "foreground-asset-failure")
        try failedState.persistForegroundChangeToken(oldCursor, generation: failedState.generation)
        failedBridge.prepareIncomingRecord = { _, _ in _ = try Data(contentsOf: directory.appendingPathComponent("missing-asset.jpg")) }
        try mustThrow("missing foreground asset rejects cursor advancement") {
            try failedBridge.receiveForegroundPage([remote], deletedIDs: [], token: nextCursor, generation: failedState.generation)
        }
        try check(failedState.foregroundChangeToken == oldCursor && failedState.incomingRecords.isEmpty,
                  "asset failure retains the exact previous foreground cursor and no half-retained reference")
        try mustThrow("empty page cannot bypass an earlier failed foreground retention") {
            try failedBridge.receiveForegroundPage([], deletedIDs: [], token: nextCursor, generation: failedState.generation)
        }
        let (deletedState, deletedAdapter, deletedBridge) = try fixture(directory, "foreground-hard-delete")
        try deletedState.persistForegroundChangeToken(oldCursor, generation: deletedState.generation)
        let before = try Data(contentsOf: deletedAdapter.fileURL)
        try mustThrow("foreground external hard deletion enters recovery before advancing the cursor") {
            try deletedBridge.receiveForegroundPage([], deletedIDs: [remote.recordID], token: nextCursor, generation: deletedState.generation)
        }
        try check(deletedState.foregroundChangeToken == oldCursor && deletedBridge.recoveryReason != nil
                  && (try Data(contentsOf: deletedAdapter.fileURL)) == before,
                  "foreground deletion retains all source bytes and previous cursor")
        let foreign = CKRecord(recordType: "Harness", recordID: .init(recordName: "outside", zoneID: .init(zoneName: "Harness", ownerName: CKCurrentUserDefaultName)))
        try mustThrow("foreign records cannot advance a SAVY foreground cursor") {
            try restored.receiveForegroundPage([foreign], deletedIDs: [], token: Data("foreign".utf8), generation: reopened.generation)
        }
        let generation = reopened.generation
        try reopened.accountChanged(to: nil)
        try mustThrow("stale foreground response cannot advance cursor after sign-out") {
            try restored.receiveForegroundPage([remote], deletedIDs: [], token: Data("stale".utf8), generation: generation)
        }
        try check(reopened.foregroundChangeToken == nextCursor, "foreign and stale responses leave the last confirmed cursor intact")
        try check(try SavyCloudKitRecordCodec.foregroundToken(from: nil) == nil, "first foreground fetch has no cursor")
        try mustThrow("secure token decoder rejects an unrelated archive") {
            _ = try SavyCloudKitRecordCodec.foregroundToken(from: NSKeyedArchiver.archivedData(withRootObject: NSString(string: "unrelated"), requiringSecureCoding: true))
        }
    }
    static func initialSignIn(_ directory: URL) throws {
        let (state, _, bridge) = try fixture(directory, "initial-sign-in")
        let owner = CKRecord.ID(recordName: "original-owner")
        let other = CKRecord.ID(recordName: "different-owner")
        let generation = state.generation
        try check(bridge.acceptsInitialSignIn(.signIn(currentUser: owner), generation: generation),
                  "initial sign-in for the verified original owner preserves its authorized engine")
        try check(!bridge.acceptsInitialSignIn(.signIn(currentUser: other), generation: generation), "a mismatched sign-in cannot retain an engine")
        try check(!bridge.acceptsInitialSignIn(.signOut(previousUser: owner), generation: generation), "sign-out still invalidates transport")
        try check(!bridge.acceptsInitialSignIn(.switchAccounts(previousUser: other, currentUser: owner), generation: generation),
                  "a real account switch still requires a fresh verified engine")
        try state.accountChanged(to: nil)
        try check(!bridge.acceptsInitialSignIn(.signIn(currentUser: owner), generation: generation), "stale sign-in cannot bypass generation invalidation")
    }
    static func postReferenceCollisions(_ directory: URL) throws {
        let reminders = try TransportFileAdapter(documentKey: "reminders", fileURL: directory.appendingPathComponent("collision-reminders.json"), values: [
            "reminder:first": .object(["kind": .string("post"), "postNumber": .number(7)]),
            "reminder:unrelated": .object(["kind": .string("reminder"), "postNumber": .number(7)]),
            "reminder:deleted": .object(["kind": .string("post"), "status": .string("deleted"), "postNumber": .number(7)])
        ])
        let posts = try TransportFileAdapter(documentKey: "social-posts", fileURL: directory.appendingPathComponent("collision-posts.json"), values: [
            "post:second": .object(["postNumber": .number(7)])
        ])
        let state = try SavyCloudSyncState(fileURL: directory.appendingPathComponent("collision-state.json"))
        let bridge = try SavyCloudKitTransportBridge(state: state, adapters: ["reminders": reminders, "social-posts": posts],
            safetyURL: directory.appendingPathComponent("collision-safety.json"))
        try check(bridge.postNumberCollisions.keys.sorted() == [7], "actual duplicate Post reference is reported")
        let expected: Set<SavyCloudRecordID> = [.init(documentKey: "reminders", key: "reminder:first"),
            .init(documentKey: "social-posts", key: "post:second")]
        try check(Set(bridge.postNumberCollisions[7]!) == expected, "collision excludes deleted and non-Post entries while preserving both references")
        try check(reminders.values["reminder:first"] == .object(["kind": .string("post"), "postNumber": .number(7)])
                  && posts.values["post:second"] == .object(["postNumber": .number(7)]), "collision detection never renumbers or changes either record")
    }
    private static func fixture(_ directory: URL, _ name: String) throws -> (SavyCloudSyncState, TransportFileAdapter, SavyCloudKitTransportBridge) {
        let adapter = try TransportFileAdapter(fileURL: directory.appendingPathComponent("\(name)-store.json"), values: ["story:one": .string("Local original.  \n")])
        let state = try SavyCloudSyncState(fileURL: directory.appendingPathComponent("\(name)-state.json"))
        try state.accountChanged(to: "original-owner")
        _ = try state.observeLocal(adapter: adapter, legacyDevice: true, now: 100)
        let bridge = try SavyCloudKitTransportBridge(state: state, adapters: ["stories": adapter], safetyURL: directory.appendingPathComponent("\(name)-safety.json"))
        return (state, adapter, bridge)
    }
    static func codecAndScopes() throws {
        let input = portable("Exact writing.  \n", key: "story:" + String(repeating: "private source ", count: 100))
        let record = try SavyCloudKitRecordCodec.encode(input)
        let decoded = try SavyCloudKitRecordCodec.decode(record, documents: ["stories"])
        try check(decoded.id == input.id && decoded.entry == input.entry, "encrypted payload preserves exact writing and long source identity")
        try check(record["payload"] == nil && record.encryptedValues["payload"] is Data, "authored JSON is assigned only to the encrypted CloudKit field")
        try check(record.recordID.recordName.count < 255 && !record.recordID.recordName.contains("private source"), "stable namespaced hash bounds record names without exposing source keys")
        try check(record.recordID == SavyCloudKitRecordCodec.recordID(for: input.id), "record identity is stable across encoding")
        let sameKeyOtherDocument = SavyCloudRecordID(documentKey: "connections", key: input.id.key)
        try check(record.recordID != SavyCloudKitRecordCodec.recordID(for: sameKeyOtherDocument), "different documents cannot collide on the same entry key")
        var tombstone = input
        tombstone.entry = .init(value: nil, modifiedAt: 101, deleted: true)
        let encodedDeletion = try SavyCloudKitRecordCodec.encode(tombstone)
        try check(try SavyCloudKitRecordCodec.decode(encodedDeletion, documents: ["stories"]).entry == tombstone.entry, "deletion is a saved versioned tombstone record")
        let fields = try SavyCloudKitRecordCodec.systemFields(of: record)
        let restored = try SavyCloudKitRecordCodec.restoreSystemFields(fields)
        try check(restored.recordID == record.recordID && restored.recordType == record.recordType, "real secure-coded CKRecord system fields round trip")
        let foreign = CKRecord(recordType: "Harness", recordID: .init(recordName: "private", zoneID: .init(zoneName: "Harness", ownerName: CKCurrentUserDefaultName)))
        try check(try SavyCloudKitRecordCodec.decodeIfOwned(foreign, documents: ["stories"]) == nil, "foreign Harness zone is ignored before decoding")
        let fetch = SavyCloudKitRecordCodec.fetchOptions()
        try check(fetch.scope.contains(SavyCloudKitRecordCodec.zoneID) && !fetch.scope.contains(foreign.recordID.zoneID), "fetch scope contains only SAVYEntriesV1")
        let send = SavyCloudKitRecordCodec.sendOptions()
        try check(send.scope.contains(record.recordID) && !send.scope.contains(foreign.recordID), "send scope excludes every foreign zone")
    }
    static func conflictAndExactSave(_ directory: URL) throws {
        let (state, adapter, bridge) = try fixture(directory, "conflict")
        let first = state.pendingRecords[0]
        try check(try bridge.pendingBatch(generation: state.generation) == nil, "initial local import cannot send before scoped fetch finishes")
        try bridge.fetchedChangesFinished(generation: state.generation)
        try adapter.save(["story:one": .string("Later local writing.  \n")])
        _ = try state.observeLocal(adapter: adapter, legacyDevice: true, now: 200)
        let later = state.pendingRecords[0]
        let server = try SavyCloudKitRecordCodec.encode(first)
        // Parent is real CKRecord system metadata; no private change-tag setter or cloud
        // response is faked. This proves retry reconstructs the actual server metadata.
        server.parent = .init(recordID: .init(recordName: "server-parent", zoneID: SavyCloudKitRecordCodec.zoneID), action: .none)
        let error = CKError(_nsError: NSError(domain: CKErrorDomain, code: CKError.Code.serverRecordChanged.rawValue,
            userInfo: [CKRecordChangedErrorServerRecordKey: server]))
        try bridge.receiveServerConflict(error, generation: state.generation)
        let retry = try bridge.pendingBatch(generation: state.generation)!.recordsToSave[0]
        try check(try SavyCloudKitRecordCodec.decode(retry, documents: ["stories"]).entry == later.entry, "serverRecordChanged retries the deterministic latest local winner")
        try check(retry.parent?.recordID == server.parent?.recordID, "conflict retry rebuilds fresh server system fields")
        try check(state.conflicts.contains { $0.displaced == first.entry && $0.retained == later.entry }, "conflict resolution archives the displaced exact original")
        try bridge.acknowledgeSaved([server], generation: state.generation)
        try check(state.pendingRecords.map(\.entry) == [later.entry], "old saved response cannot acknowledge a newer pending version")
        try bridge.acknowledgeSaved([retry], generation: state.generation)
        try check(state.pendingRecords.isEmpty && !state.systemFields(for: later.id)!.isEmpty, "the exact saved version confirms and retains real metadata")
        try check(adapter.values == (try JSONDecoder().decode([String: SyncJSON].self, from: Data(contentsOf: adapter.fileURL))), "resolved writing is confirmed in the actual temporary file")
    }
    static func incomingFailureAndCorruptFetch(_ directory: URL) throws {
        let (state, adapter, bridge) = try fixture(directory, "incoming")
        try bridge.fetchedChangesFinished(generation: state.generation)
        let original = try Data(contentsOf: adapter.fileURL)
        let remote = try SavyCloudKitRecordCodec.encode(portable("New remote writing.  \n", date: 300))
        try FileManager.default.removeItem(at: adapter.fileURL)
        try FileManager.default.createDirectory(at: adapter.fileURL, withIntermediateDirectories: false)
        try bridge.receive([remote], generation: state.generation)
        try check(state.incomingRecords.count == 1 && adapter.applyCount == 0, "failed actual file apply retains durable incoming writing")
        try check(try bridge.pendingBatch(generation: state.generation) == nil, "unapplied incoming document prevents sending its older pending value")
        try bridge.persistCheckpoint(Data("confirmed-fetch".utf8), generation: state.generation)
        let reopened = try SavyCloudSyncState(fileURL: state.fileURL)
        try check(reopened.incomingRecords.count == 1 && reopened.engineState == Data("confirmed-fetch".utf8), "incoming survives advanced checkpoint and relaunch")
        let corrupt = CKRecord(recordType: SavyCloudKitRecordCodec.recordType, recordID: SavyCloudKitRecordCodec.recordID(for: portable("x").id))
        corrupt["schemaVersion"] = NSNumber(value: 1)
        corrupt.encryptedValues["payload"] = Data("unreadable original".utf8) as NSData
        try mustThrow("corrupt owned CloudKit record is reported") { try bridge.receive([corrupt], generation: state.generation) }
        try mustThrow("corrupt owned record prevents accepting advanced serialization") { try bridge.persistCheckpoint(Data("must-not-advance".utf8), generation: state.generation) }
        try check(state.engineState == Data("confirmed-fetch".utf8), "last confirmed fetch progress remains unchanged after corruption")
        try FileManager.default.removeItem(at: adapter.fileURL)
        try original.write(to: adapter.fileURL)
        try state.accountChanged(to: nil)
        try state.accountChanged(to: "original-owner")
        let restoredBridge = try SavyCloudKitTransportBridge(state: state, adapters: ["stories": adapter], safetyURL: directory.appendingPathComponent("incoming-safety.json"))
        try restoredBridge.receive([remote], generation: state.generation)
        try restoredBridge.fetchedChangesFinished(generation: state.generation)
        try check(state.incomingRecords.isEmpty && adapter.values["story:one"] == .string("New remote writing.  \n"), "scoped refetch recovers retained work after source repair")
    }
    static func accountAndRestart(_ directory: URL) throws {
        let (state, adapter, bridge) = try fixture(directory, "account")
        try bridge.fetchedChangesFinished(generation: state.generation)
        let oldGeneration = state.generation
        try state.accountChanged(to: nil)
        try adapter.save(["story:one": .string("Offline saved writing")])
        _ = try state.observeLocal(adapter: adapter, legacyDevice: true, now: 400)
        let pending = state.pendingRecords
        try check(try bridge.pendingBatch(generation: oldGeneration) == nil, "sign-out blocks the previously authorized send generation")
        let remote = try SavyCloudKitRecordCodec.encode(portable("Other-account writing", date: 500))
        try mustThrow("stale original engine cannot apply an account-switch response") { try bridge.receive([remote], generation: oldGeneration) }
        try state.accountChanged(to: "different-owner")
        try check(try bridge.pendingBatch(generation: state.generation) == nil && adapter.applyCount == 0, "different owner produces no transport batch or local apply")
        let restarted = try SavyCloudSyncState(fileURL: state.fileURL)
        let restoredBridge = try SavyCloudKitTransportBridge(state: restarted, adapters: ["stories": adapter], safetyURL: directory.appendingPathComponent("account-safety.json"))
        try check(restarted.pendingRecords == pending && (try restoredBridge.pendingBatch(generation: restarted.generation)) == nil, "offline pending work survives relaunch and requires current owner verification")
        try restarted.accountChanged(to: "original-owner")
        try restoredBridge.fetchedChangesFinished(generation: restarted.generation)
        let batch = try restoredBridge.pendingBatch(generation: restarted.generation)
        try check(batch?.recordsToSave.count == 1 && batch?.recordIDsToDelete.isEmpty == true, "returning original owner resumes its exact saved work without hard deletes")
        try check(try SavyCloudKitRecordCodec.decode(batch!.recordsToSave[0], documents: ["stories"]).entry == pending[0].entry, "restored send contains the original owner's durable offline version")
    }
    static func emptyFetchReplaysRetainedIncoming(_ directory: URL) throws {
        let (state, adapter, bridge) = try fixture(directory, "empty-refetch")
        try bridge.fetchedChangesFinished(generation: state.generation)
        let originalBytes = try Data(contentsOf: adapter.fileURL)
        try FileManager.default.removeItem(at: adapter.fileURL)
        try FileManager.default.createDirectory(at: adapter.fileURL, withIntermediateDirectories: false)
        let remote = try SavyCloudKitRecordCodec.encode(portable("Retained incoming after relaunch.  \n", date: 300))
        try bridge.receive([remote], generation: state.generation)
        try bridge.persistCheckpoint(Data("advanced-before-source-repair".utf8), generation: state.generation)
        let reopened = try SavyCloudSyncState(fileURL: state.fileURL)
        try reopened.accountChanged(to: "original-owner")
        let relaunched = try SavyCloudKitTransportBridge(state: reopened, adapters: ["stories": adapter],
            safetyURL: directory.appendingPathComponent("empty-refetch-safety.json"))
        try FileManager.default.removeItem(at: adapter.fileURL)
        try originalBytes.write(to: adapter.fileURL, options: .atomic)
        try relaunched.receive([], generation: reopened.generation)
        try check(adapter.values["story:one"] == .string("Retained incoming after relaunch.  \n") && reopened.incomingRecords.isEmpty,
                  "empty scoped fetch after relaunch replays durable incoming into a repaired source")
        try check(reopened.pendingRecords.isEmpty && adapter.applyCount == 1,
                  "empty fetch confirms incoming once and removes the displaced older pending value")
        try check(try JSONDecoder().decode([String: SyncJSON].self, from: Data(contentsOf: adapter.fileURL)) == adapter.values,
                  "empty-fetch recovery writing is actually durable on disk")
    }
    static func durableRecoveryHolds(_ directory: URL) throws {
        let (state, adapter, bridge) = try fixture(directory, "hard-delete")
        try bridge.fetchedChangesFinished(generation: state.generation)
        let before = try Data(contentsOf: adapter.fileURL)
        let foreign = CKRecord.ID(recordName: "foreign", zoneID: .init(zoneName: "Harness", ownerName: CKCurrentUserDefaultName))
        try bridge.recordsWereHardDeleted([foreign], generation: state.generation)
        try check(try bridge.pendingBatch(generation: state.generation)?.recordsToSave.count == 1, "foreign hard deletion has no effect on SAVY work")
        try bridge.recordsWereHardDeleted([SavyCloudKitRecordCodec.recordID(for: state.pendingRecords[0].id)], generation: state.generation)
        try check(try bridge.pendingBatch(generation: state.generation) == nil && (try Data(contentsOf: adapter.fileURL)) == before, "unexpected own hard deletion holds writes and preserves the source")
        let reopened = try SavyCloudKitTransportBridge(state: state, adapters: ["stories": adapter], safetyURL: directory.appendingPathComponent("hard-delete-safety.json"))
        try check(reopened.recoveryReason != nil && (try reopened.pendingBatch(generation: state.generation)) == nil, "hard-delete recovery hold survives transport relaunch")
        let (zoneState, zoneAdapter, zoneBridge) = try fixture(directory, "zone-purge")
        try zoneBridge.zoneWasDeleted(SavyCloudKitRecordCodec.zoneID, generation: zoneState.generation)
        let zoneReopened = try SavyCloudKitTransportBridge(state: zoneState, adapters: ["stories": zoneAdapter], safetyURL: directory.appendingPathComponent("zone-purge-safety.json"))
        try check(zoneReopened.recoveryReason != nil && zoneState.pendingRecords.count == 1, "own zone purge retains pending work in a durable recovery hold")
    }
    static func localEditWhileFetchIsInFlight(_ directory: URL) throws {
        for remoteIsLater in [false, true] {
            let (state, adapter, bridge) = try fixture(directory, "inflight-\(remoteIsLater)")
            try bridge.fetchedChangesFinished(generation: state.generation)
            let localWriting = "Local save B while fetch is awaiting.  \n"
            try adapter.save(["story:one": .string(localWriting)])
            // Deliberately do not observe the publisher or update the journal here.
            // Receive must notice the real file-backed store's newer save itself.
            let remoteDate = remoteIsLater ? Date().timeIntervalSince1970 + 1_000 : 300
            let remoteWriting = "Remote C fetched after the local save.  \n"
            let remote = try SavyCloudKitRecordCodec.encode(portable(remoteWriting, date: remoteDate))
            try bridge.receive([remote], generation: state.generation)
            let expected = remoteIsLater ? remoteWriting : localWriting
            try check(adapter.values["story:one"] == .string(expected),
                      "receive observes the actual in-flight local save before date comparison \(remoteIsLater)")
            try check(state.conflicts.contains {
                Set([$0.displaced.value?.stringValue, $0.retained.value?.stringValue]) == Set([localWriting, remoteWriting])
            }, "in-flight local B and fetched C are both preserved before replacement \(remoteIsLater)")
            try check(try JSONDecoder().decode([String: SyncJSON].self, from: Data(contentsOf: adapter.fileURL))["story:one"] == .string(expected),
                      "in-flight conflict winner is actually written to disk \(remoteIsLater)")
        }
    }
    static func disabledHasNoEffects(_ directory: URL) async throws {
        let disabledDirectory = directory.appendingPathComponent("disabled")
        let service = CloudKitDocumentSync(adapters: [], legacyDevice: true, enabled: false,
                                          stateURL: disabledDirectory.appendingPathComponent("state.json"))
        await service.start()
        await service.syncNow()
        try check(!FileManager.default.fileExists(atPath: disabledDirectory.path), "disabled init, start and sync create no state, diagnostics, cache or cloud resources")
    }
    static func independentPreparationFailures(_ directory: URL) throws {
        let (state, adapter, bridge) = try fixture(directory, "record-preparation")
        var values: [String: SyncJSON] = [:]
        for index in 0..<201 { values[String(format: "story:blocked-%03d", index)] = .string("Pending image reference") }
        values["story:z-healthy"] = .string("Healthy writing")
        try adapter.save(values)
        _ = try state.observeLocal(adapter: adapter, legacyDevice: true, now: 200)
        try bridge.fetchedChangesFinished(generation: state.generation)
        var failures = 0
        let missingFile = directory.appendingPathComponent("absent-upload-image.jpg")
        bridge.prepareOutgoingRecord = { _, source in
            if source.id.key.hasPrefix("story:blocked-") { _ = try Data(contentsOf: missingFile) }
        }
        bridge.recordPreparationFailed = { _, _ in failures += 1 }
        let batch = try bridge.pendingBatch(generation: state.generation)
        let ids = try batch!.recordsToSave.map { try SavyCloudKitRecordCodec.decode($0, documents: ["stories"]).id.key }
        try check(ids.contains("story:z-healthy") && !ids.contains(where: { $0.hasPrefix("story:blocked-") }),
                  "more than 200 missing-file references cannot starve a healthy later record")
        try check(failures == 201 && bridge.preparationFailureCount == 201,
                  "every blocked record preparation is reported independently")
        try bridge.acknowledgeSaved(batch!.recordsToSave, generation: state.generation)
        try check(state.pendingRecords.count == 201 && state.pendingRecords.allSatisfy { $0.id.key.hasPrefix("story:blocked-") },
                  "healthy save confirms while every unavailable image reference remains durable pending")
    }
}
