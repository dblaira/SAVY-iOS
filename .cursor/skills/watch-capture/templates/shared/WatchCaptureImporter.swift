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
    /// Saves one capture as an entry. False when the local write failed.
    func saveEntry(fromWatchCapture capture: WatchCapture) -> Bool
}

/// The Watch captures; the iPhone and Mac process. Adam’s plan: “Your Apple Watch captures the
/// thought while you run or walk; your iPhone and MacBook Pro remain the processing tool after
/// the run is over.” Call `importPending` when the app opens or refreshes, after the app’s own
/// iCloud sync has confirmed the signed-in owner.
@MainActor
final class WatchCaptureImporter {
    static let shared = WatchCaptureImporter()

    private static let ledgerKey = "WatchCaptureImporter.importedCaptureIDs"
    private static let ledgerLimit = 2_000
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

    /// Returns how many new entries were saved.
    @discardableResult
    func importPending<Destination: WatchCaptureDestination>(into destination: Destination) async -> Int {
        guard !isImporting, destination.acceptsWatchCaptures else { return 0 }
        isImporting = true
        defer { isImporting = false }

        let container = CKContainer(identifier: WatchCaptureInbox.containerIdentifier)
        let database = container.privateCloudDatabase
        var records: [CKRecord] = []
        do {
            guard try await container.accountStatus() == .available else { return 0 }
            var token: CKServerChangeToken? = nil
            while true {
                let page = try await database.recordZoneChanges(
                    inZoneWith: WatchCaptureInbox.zoneID, since: token, desiredKeys: nil, resultsLimit: 200)
                for result in page.modificationResultsByID.values {
                    if case .success(let modification) = result { records.append(modification.record) }
                }
                token = page.changeToken
                if !page.moreComing { break }
            }
        } catch {
            // No Watch capture yet means no zone yet. Any other failure retries on the next refresh.
            return 0
        }

        let captures = records
            .compactMap { record -> (WatchCapture, CKRecord.ID)? in
                // A capture from a newer Watch app stays in iCloud for a newer iPhone app.
                guard let capture = try? WatchCaptureInbox.capture(from: record) else { return nil }
                return (capture, record.recordID)
            }
            .sorted { $0.0.capturedAt < $1.0.capturedAt }

        var ledger = importedIDs
        var finished: [CKRecord.ID] = []
        var saved = 0
        for (capture, recordID) in captures {
            let key = capture.id.uuidString.lowercased()
            if ledger.contains(key) || destination.hasEntry(forWatchCapture: capture.id) {
                if !ledger.contains(key) { ledger.append(key) }
                finished.append(recordID)
                continue
            }
            // A failed local write leaves the capture in iCloud for the next refresh.
            guard destination.saveEntry(fromWatchCapture: capture) else { break }
            ledger.append(key)
            finished.append(recordID)
            saved += 1
        }
        importedIDs = ledger

        if !finished.isEmpty {
            // The entry is saved locally first. If this removal fails, the ledger and the
            // entry's id keep the next refresh from importing the capture again.
            _ = try? await database.modifyRecords(saving: [], deleting: finished,
                                                  savePolicy: .ifServerRecordUnchanged, atomically: false)
        }
        return saved
    }
}
