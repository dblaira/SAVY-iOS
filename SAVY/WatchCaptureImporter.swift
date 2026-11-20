import CloudKit
import Foundation

/// The Watch captures; the iPhone and Mac process. Adam’s plan: “Your Apple Watch captures the
/// thought while you run or walk; your iPhone and MacBook Pro remain the processing tool after
/// the run is over.” When SAVY opens or refreshes, each Watch capture in iCloud becomes a normal
/// entry through `ReminderStore.save`, the same path the entry form’s Save uses, and then syncs
/// to the other devices like any other entry.
@MainActor
final class WatchCaptureImporter {
    static let shared = WatchCaptureImporter()

    private static let ledgerKey = "SAVYWatchCaptureImporter.importedCaptureIDs"
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
    func importPending(into store: ReminderStore) async -> Int {
        guard !isImporting, store.canSync else { return 0 }
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
            if ledger.contains(key) || store.reminders.contains(where: { $0.id == capture.id }) {
                if !ledger.contains(key) { ledger.append(key) }
                finished.append(recordID)
                continue
            }
            // A failed local write leaves the capture in iCloud for the next refresh.
            guard store.save(Reminder(watchCapture: capture)) else { break }
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

extension Reminder {
    /// One Watch capture as a SAVY entry. The words go where Adam would have typed them:
    /// “What do I want?” for Action, Reminder and Calendar, and the first Generalization question
    /// for Social. Nothing is added that he did not say.
    init(watchCapture capture: WatchCapture) {
        self.init()
        id = capture.id
        kind = ReminderKind(rawValue: capture.kind.rawValue) ?? .action
        createdAt = capture.capturedAt
        updatedAt = capture.capturedAt

        if capture.kind == .post {
            // Generalization doc: “Common scenario is that I am out for a run and have an idea
            // hit me.” He answers only the first question, “What shining example caught my
            // attention?”, and finishes the form after the run.
            let theme = PostThemeCatalog.theme(id: "generalization") ?? PostThemeCatalog.defaultTheme
            var answers = theme.prefilledAnswers
            if let first = theme.questions.first, !answers.isEmpty {
                answers[0] = first.prompt + "\n" + capture.words
            }
            postThemeID = theme.id
            postThemeName = theme.name
            postAnswers = answers
            postAnswersContainQuestions = true
            title = autoTitle() ?? capture.words
        } else {
            title = capture.words
        }

        if let window = capture.proposedWindow {
            schedule = ReminderSchedule(
                startDate: window.start,
                endDate: window.end,
                isAllDay: window.isAllDay,
                timeZoneIdentifier: capture.timeZoneIdentifier,
                alert: window.isAllDay ? .none : .atStart
            )
            scheduleSyncVersion = 1
            dueDate = window.start
            dueTime = window.isAllDay ? nil : window.start
            endTime = window.isAllDay ? nil : window.end
        }
    }
}
