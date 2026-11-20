import CloudKit
import Foundation

// Watch capture kit: the same in every app that uses it.

/// Where Watch captures become entries. Each app conforms its own store, so a capture is saved
/// through the same path the app's own Save uses and then syncs like any other entry.
@MainActor
protocol WatchCaptureDestination: AnyObject {
    /// False while the app's own storage could not be read; nothing is imported then.
    var acceptsWatchCaptures: Bool { get }
    /// True when an entry made from this capture already exists, including a deleted one
    /// the store still remembers.
    func hasEntry(forWatchCapture id: UUID) -> Bool
    /// Saves one capture as an entry. For a recording, `capture.words` already holds the words
    /// this device wrote out (empty if it could not). False when the local write failed.
    func saveEntry(fromWatchCapture capture: WatchCapture) -> Bool
}

/// The Watch captures; the iPhone and Mac process. Adam’s plan: “Your Apple Watch captures the
/// thought while you run or walk; your iPhone and MacBook Pro remain the processing tool after
/// the run is over.” Call `importPending` when the app opens or refreshes, after the app’s own
/// iCloud sync has confirmed the signed-in owner.
///
/// Every device keeps its own copy of each recording. Only one device turns a capture into an
/// entry: it claims the capture in iCloud first, and the others then see the claim. Captures stay
/// in iCloud for two weeks after the claim, so the other devices can fetch the recording, and then
/// the claiming device deletes them.
@MainActor
final class WatchCaptureImporter {
    static let shared = WatchCaptureImporter()

    private static let ledgerKey = "WatchCaptureImporter.importedCaptureIDs"
    private static let claimsKey = "WatchCaptureImporter.claims"
    private static let tokenKey = "WatchCaptureImporter.changeToken"
    private static let ledgerLimit = 2_000
    private static let keepClaimedFor: TimeInterval = 14 * 86_400
    private let defaults: UserDefaults
    private var isImporting = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Captures this device already turned into entries. An entry Adam later deletes is never
    /// recreated from a capture that is still waiting in iCloud.
    private var importedIDs: [String] {
        get { defaults.stringArray(forKey: Self.ledgerKey) ?? [] }
        set { defaults.set(Array(newValue.suffix(Self.ledgerLimit)), forKey: Self.ledgerKey) }
    }

    /// Record names this device claimed, with when, so it can delete them after two weeks.
    private var claims: [String: Date] {
        get { (defaults.dictionary(forKey: Self.claimsKey) as? [String: Date]) ?? [:] }
        set { defaults.set(newValue, forKey: Self.claimsKey) }
    }

    private var changeToken: CKServerChangeToken? {
        get {
            defaults.data(forKey: Self.tokenKey).flatMap {
                try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0)
            }
        }
        set {
            let data = newValue.flatMap { try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true) }
            defaults.set(data, forKey: Self.tokenKey)
        }
    }

    /// Returns how many new entries were saved.
    @discardableResult
    func importPending<Destination: WatchCaptureDestination>(into destination: Destination) async -> Int {
        guard !isImporting, destination.acceptsWatchCaptures else { return 0 }
        isImporting = true
        defer { isImporting = false }

        let container = CKContainer(identifier: WatchCaptureInbox.containerIdentifier)
        let database = container.privateCloudDatabase
        var records: [CKRecord] = []
        var token = changeToken
        do {
            guard try await container.accountStatus() == .available else { return 0 }
            var moreComing = true
            while moreComing {
                do {
                    let page = try await database.recordZoneChanges(
                        inZoneWith: WatchCaptureInbox.zoneID, since: token, desiredKeys: nil, resultsLimit: 100)
                    for result in page.modificationResultsByID.values {
                        if case .success(let modification) = result { records.append(modification.record) }
                    }
                    token = page.changeToken
                    moreComing = page.moreComing
                } catch let error as CKError where error.code == .changeTokenExpired && token != nil {
                    // Start over from the beginning; the ledger keeps entries from repeating.
                    token = nil
                    records = []
                }
            }
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            // No Watch capture yet means no zone yet.
            changeToken = nil
            return 0
        } catch {
            // Any other failure retries on the next refresh.
            return 0
        }

        var ledger = importedIDs
        var saved = 0
        var everythingHandled = true
        let pending = records
            .compactMap { record -> (WatchCapture, CKRecord)? in
                // A capture from a newer Watch app stays in iCloud for a newer iPhone app.
                guard let capture = try? WatchCaptureInbox.capture(from: record) else { return nil }
                return (capture, record)
            }
            .sorted { $0.0.capturedAt < $1.0.capturedAt }

        for (capture, record) in pending {
            // Every device keeps the recording, whoever makes the entry.
            var recordingURL: URL? = nil
            if let downloaded = WatchCaptureInbox.audioURL(in: record) {
                recordingURL = WatchRecordingFiles.keep(downloaded, for: capture)
                if recordingURL == nil { everythingHandled = false }
            }

            let key = capture.id.uuidString.lowercased()
            if record[WatchCaptureInbox.importedAtKey] != nil || ledger.contains(key)
                || destination.hasEntry(forWatchCapture: capture.id) {
                if !ledger.contains(key) { ledger.append(key) }
                continue
            }

            var finished = capture
            if capture.words.isEmpty, let recordingURL,
               let words = await WatchCaptureTranscriber.words(fromRecordingAt: recordingURL) {
                finished = capture.replacingWords(words)
            }

            // Claim it, so the iPhone and the Mac never both make the entry.
            record[WatchCaptureInbox.importedAtKey] = Date() as NSDate
            guard let result = try? await database.modifyRecords(
                    saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true),
                  case .success? = result.saveResults[record.recordID] else {
                // Another device claimed it first, or iCloud is unreachable: the next refresh
                // either sees the claim or tries again.
                everythingHandled = false
                continue
            }
            guard destination.saveEntry(fromWatchCapture: finished) else {
                // The local write failed: release the claim so this capture is tried again.
                record[WatchCaptureInbox.importedAtKey] = nil
                _ = try? await database.modifyRecords(saving: [record], deleting: [],
                                                      savePolicy: .changedKeys, atomically: true)
                everythingHandled = false
                break
            }
            ledger.append(key)
            claims[record.recordID.recordName] = Date()
            saved += 1
        }
        importedIDs = ledger
        // The cursor moves on only when every capture in this batch was handled.
        if everythingHandled { changeToken = token }

        await deleteOldClaims(in: database)
        return saved
    }

    private func deleteOldClaims(in database: CKDatabase) async {
        let cutoff = Date().addingTimeInterval(-Self.keepClaimedFor)
        let old = claims.filter { $0.value < cutoff }.map(\.key)
        guard !old.isEmpty else { return }
        let ids = old.map { CKRecord.ID(recordName: $0, zoneID: WatchCaptureInbox.zoneID) }
        guard let result = try? await database.modifyRecords(
                saving: [], deleting: ids, savePolicy: .ifServerRecordUnchanged, atomically: false) else { return }
        var remaining = claims
        for (id, outcome) in result.deleteResults {
            if case .success = outcome { remaining[id.recordName] = nil }
            if case .failure(let error) = outcome, (error as? CKError)?.code == .unknownItem { remaining[id.recordName] = nil }
        }
        claims = remaining
    }
}
