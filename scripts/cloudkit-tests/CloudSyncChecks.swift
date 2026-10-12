import Combine
import Foundation

// Only external effects are replaced. All stores, adapters, journals, JSON, and numbering
// below are production code using exclusively this process's temporary directory.
@MainActor enum NotificationScheduler {
    static var scheduled: [Reminder] = []
    static var cancelled: [UUID] = []
    static func schedule(_ value: Reminder) { scheduled.append(value) }
    static func cancel(_ value: Reminder) { cancelled.append(value.id) }
    static func reset() { scheduled = []; cancelled = [] }
}
struct NewsChannelPostPreview { init(text: String, additionalDetails: [String]) {} }
struct TechnicalCapture {
    static func from(reminder: Reminder, existing: TechnicalCapture?) -> TechnicalCapture { .init() }
}
@MainActor final class TechnicalCaptureStore {
    var captures: [TechnicalCapture] = []
    static func live() -> TechnicalCaptureStore { .init() }
    func capture(forReminderID: UUID) -> TechnicalCapture? { nil }
    func save(_ value: TechnicalCapture) { captures.append(value) }
    func recentClearSignEntries(limit: Int) -> [TechnicalCapture] { [] }
    func recentCompoundEntries(limit: Int) -> [TechnicalCapture] { [] }
    func recentClearSignOrCompoundEntries(limit: Int) -> [TechnicalCapture] { [] }
}
struct CowboyCandidateOutboxItem { var id: UUID; var payload: String }
@MainActor final class CowboyCandidateOutbox {
    var items: [CowboyCandidateOutboxItem] = []
    static func live() -> CowboyCandidateOutbox { .init() }
    func enqueue(_ value: TechnicalCapture) { items.append(.init(id: UUID(), payload: "isolated capture")) }
    func dueItems(now: Date) -> [CowboyCandidateOutboxItem] { [] }
    func recordReceipt(itemID: UUID, receipt: Bool, now: Date) {}
    func recordFailure(itemID: UUID, message: String, now: Date) {}
}
protocol CowboyCandidateSubmitting: Sendable { func submit(_ payload: String) async throws -> Bool }
struct CowboyCandidateClient: CowboyCandidateSubmitting {
    func submit(_ payload: String) async throws -> Bool { preconditionFailure("No test may submit a candidate") }
}

@main @MainActor
struct CloudSyncChecks {
    struct Failure: Error { var message: String }
    static var checks = 0
    static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else {
            print("FAIL \(message)")
            fflush(nil)
            throw Failure(message: message)
        }
        checks += 1
        print("PASS \(message)")
    }

    static func mustThrow(_ message: String, _ operation: () throws -> Void) throws {
        do { try operation() } catch {
            try check(true, message)
            return
        }
        try check(false, message)
    }

    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("savy-cloud-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try importAndSchedules(directory)
        try tiesAndTombstones(directory)
        try exactPendingAndPersistence(directory)
        try accountBoundary(directory)
        try passthroughAndPins(directory)
        try mixedFailureReplay(directory)
        print("\(checks) Cloud sync checks passed")
    }

    static func state(_ directory: URL, _ name: String) throws -> SavyCloudSyncState {
        let state = try SavyCloudSyncState(fileURL: directory.appendingPathComponent("\(name)-state.json"))
        try state.accountChanged(to: "original-owner")
        return state
    }
    static func reminders(_ file: URL, _ values: [Reminder]) throws -> ReminderStore {
        try JSONEncoder.recall.encode(values).write(to: file, options: .atomic)
        return ReminderStore(cacheURL: file, technicalCaptureStore: .init(), candidateOutbox: .init())
    }
    static func stories(_ file: URL, _ values: [Story]) throws -> StoryStore {
        try JSONEncoder.recall.encode(values).write(to: file, options: .atomic)
        return try StoryStore(fileURL: file)
    }
    static func record(_ document: String, _ key: String, _ value: SyncJSON?, _ date: Double, deleted: Bool = false, fields: Data? = nil) -> SavyCloudRecord {
        .init(id: .init(documentKey: document, key: key), entry: .init(value: value, modifiedAt: date, deleted: deleted), systemFields: fields)
    }

    static func importAndSchedules(_ directory: URL) throws {
        var reminder = Reminder(title: "Newer phone reminder")
        reminder.createdAt = Date(timeIntervalSince1970: 10)
        reminder.updatedAt = Date(timeIntervalSince1970: 200)
        reminder.needsSync = true // Former gateway dirtiness does not outrank a CloudKit version.
        var post = Reminder(kind: .post, title: "Post")
        post.createdAt = Date(timeIntervalSince1970: 20)
        post.updatedAt = Date(timeIntervalSince1970: 100)
        post.postNumber = 7
        post.postAnswers = ["Original phone answer.  \n"]
        var oldReminder = reminder
        oldReminder.title = "Older Mac reminder"
        oldReminder.updatedAt = Date(timeIntervalSince1970: 100)
        var newerPost = post
        newerPost.postAnswers = ["Newer Mac answer.  \n"]
        newerPost.updatedAt = Date(timeIntervalSince1970: 200)
        let phoneFile = directory.appendingPathComponent("phone-reminders.json")
        let macFile = directory.appendingPathComponent("mac-reminders.json")
        let phone = try reminders(phoneFile, [reminder, post])
        let mac = try reminders(macFile, [oldReminder, newerPost])
        let phoneAdapter = RemindersSyncAdapter(store: phone), macAdapter = RemindersSyncAdapter(store: mac)
        let phoneState = try state(directory, "phone"), macState = try state(directory, "mac")
        let phoneRecords = try phoneState.observeLocal(adapter: phoneAdapter, legacyDevice: true, now: 9_000_000_000)
        let macRecords = try macState.observeLocal(adapter: macAdapter, legacyDevice: true, now: 9_000_000_000)
        try check(Set(phoneRecords.map { $0.entry.modifiedAt }) == [100, 200], "first import uses true dates instead of import time")
        try phoneState.retainIncoming(macRecords, generation: phoneState.generation)
        try macState.retainIncoming(phoneRecords, generation: macState.generation)
        try check(try phoneState.replayIncoming(using: ["reminders": phoneAdapter], generation: phoneState.generation) == ["reminders"], "phone confirms its merged store")
        try check(try macState.replayIncoming(using: ["reminders": macAdapter], generation: macState.generation) == ["reminders"], "Mac confirms its merged store")
        try check(Set(phone.reminders.map(\.id)) == [reminder.id, post.id] && Set(mac.reminders.map(\.id)) == [reminder.id, post.id], "opposite newer-device records preserve stable identities")
        try check(phone.reminders == mac.reminders && phone.reminders.first { $0.id == reminder.id }?.title == reminder.title,
                  "both stores converge on newer phone Reminder writing")
        try check(phone.reminders.first { $0.id == post.id }?.postAnswers == newerPost.postAnswers
                  && phone.reminders.first { $0.id == post.id }?.postNumber == 7, "newer Mac Post writing and existing reference survive")
        try check(phone.reminders.first { $0.id == reminder.id }?.createdAt == reminder.createdAt
                  && phone.reminders.first { $0.id == post.id }?.updatedAt == newerPost.updatedAt, "remote apply retains original creation and edit dates")
        try check(phone.technicalCaptures.isEmpty && phone.candidateOutboxItems.isEmpty
                  && mac.technicalCaptures.isEmpty && mac.candidateOutboxItems.isEmpty, "imports create no captures or candidate outbox items")
        try check(phoneState.conflicts.count == 2 && macState.conflicts.count == 2, "both differing original records are archived before resolution")
        try check(try JSONDecoder.recall.decode([Reminder].self, from: Data(contentsOf: phoneFile)) == phone.reminders, "confirmed merged writing is actually on disk")

        var scheduled = reminder
        scheduled.needsSync = true
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        scheduled.schedule = ReminderSchedule(startDate: start, endDate: start.addingTimeInterval(7_200),
            timeZoneIdentifier: "America/Los_Angeles", alert: .hourly, calendarIdentifier: "local-calendar",
            calendarEventIdentifier: "local-event", invitees: ["guest@example.com"])
        scheduled.dueDate = start; scheduled.dueTime = start; scheduled.endTime = scheduled.schedule?.endDate
        let scheduleFile = directory.appendingPathComponent("scheduled.json")
        let scheduleStore = try reminders(scheduleFile, [scheduled])
        let adapter = RemindersSyncAdapter(store: scheduleStore)
        let key = "reminder:\(scheduled.id.uuidString.lowercased())"
        let exported = try adapter.snapshot()[key]!.decode(Reminder.self)
        try check(exported.schedule == scheduled.schedule?.portable && !exported.needsSync,
                  "Reminder transport excludes native identifiers and gateway dirtiness")
        var remote = exported
        remote.title = "Remote schedule update"
        remote.schedule?.calendarIdentifier = "foreign-calendar"
        remote.schedule?.calendarEventIdentifier = "foreign-event"
        remote.schedule?.endDate = start.addingTimeInterval(3_600)
        remote.updatedAt = Date(timeIntervalSince1970: 300)
        NotificationScheduler.reset()
        try check(adapter.applyAndConfirm([key: try SyncJSON.encode(remote)]), "Reminder apply confirms disk persistence")
        let received = scheduleStore.reminders[0]
        try check(received.schedule?.calendarIdentifier == "local-calendar" && received.schedule?.calendarEventIdentifier == "local-event",
                  "incoming Reminder preserves this device's native Calendar IDs")
        try check(received.endTime == remote.schedule?.endDate && NotificationScheduler.scheduled == [received],
                  "confirmed schedule edit reconciles feed mirrors and local notifications")
        try check(scheduleStore.technicalCaptures.isEmpty && scheduleStore.candidateOutboxItems.isEmpty,
                  "schedule receipt bypasses capture and invitation authoring")
        let savedBytes = try Data(contentsOf: scheduleFile)
        try FileManager.default.removeItem(at: scheduleFile)
        try FileManager.default.createDirectory(at: scheduleFile, withIntermediateDirectories: false)
        NotificationScheduler.reset()
        try check(!adapter.applyAndConfirm([:]) && scheduleStore.reminders == [received], "failed Reminder deletion does not publish or acknowledge")
        try check(NotificationScheduler.cancelled.isEmpty && NotificationScheduler.scheduled.isEmpty, "failed Reminder apply leaves notification delivery unchanged")
        try FileManager.default.removeItem(at: scheduleFile)
        try savedBytes.write(to: scheduleFile)
        try check(adapter.applyAndConfirm([:]) && NotificationScheduler.cancelled == [scheduled.id], "confirmed remote deletion cancels local notifications")
    }

    static func tiesAndTombstones(_ directory: URL) throws {
        var a = Story()
        a.body = "a original.  \n"
        a.createdAt = Date(timeIntervalSince1970: 10)
        a.updatedAt = Date(timeIntervalSince1970: 100)
        var z = a; z.body = "z original.  \n"
        let key = "story:\(a.id.uuidString.lowercased())"
        let liveA = record("stories", key, try SyncJSON.encode(a), 100)
        let liveZ = record("stories", key, try SyncJSON.encode(z), 100)
        let deletion = record("stories", key, nil, 100, deleted: true)
        for reverse in [false, true] {
            let local = try stories(directory.appendingPathComponent("ties-\(reverse).json"), reverse ? [z] : [a])
            let adapter = StoriesSyncAdapter(store: local)
            let journal = try state(directory, "ties-\(reverse)")
            _ = try journal.observeLocal(adapter: adapter, legacyDevice: true, now: 999)
            try journal.retainIncoming([reverse ? liveA : liveZ], generation: journal.generation)
            _ = try journal.replayIncoming(using: ["stories": adapter], generation: journal.generation)
            try check(local.stories[0].body == z.body, "equal-date live values converge in receive order \(reverse)")
            try check(journal.conflicts.contains { $0.displaced.value == liveA.entry.value && $0.retained.value == liveZ.entry.value },
                      "equal-date resolution preserves both exact originals in order \(reverse)")
            try journal.retainIncoming(reverse ? [deletion, liveZ] : [liveZ, deletion], generation: journal.generation)
            _ = try journal.replayIncoming(using: ["stories": adapter], generation: journal.generation)
            try check(local.stories.isEmpty && journal.entry(for: deletion.id)?.deleted == true,
                      "deletion wins an exact date tie in receive order \(reverse)")
            try journal.retainIncoming([liveA], generation: journal.generation)
            _ = try journal.replayIncoming(using: ["stories": adapter], generation: journal.generation)
            try check(local.stories.isEmpty, "retained tombstone defeats an older offline copy in order \(reverse)")
            var restore = liveA; restore.entry.modifiedAt = 101
            try journal.retainIncoming([restore], generation: journal.generation)
            _ = try journal.replayIncoming(using: ["stories": adapter], generation: journal.generation)
            try check(local.stories.first?.body == a.body, "a genuinely later version restores a deletion in order \(reverse)")
        }
        var deleted = Reminder(title: "Deleted before first import", status: .deleted)
        deleted.updatedAt = Date(timeIntervalSince1970: 123)
        let store = try reminders(directory.appendingPathComponent("first-tombstone.json"), [deleted])
        let journal = try state(directory, "first-tombstone")
        _ = try journal.observeLocal(adapter: RemindersSyncAdapter(store: store), legacyDevice: true, now: 999_999)
        try check(journal.pendingRecords.count == 1 && journal.pendingRecords[0].entry.deleted
                  && journal.pendingRecords[0].entry.modifiedAt == 123, "first import retains a pre-existing deletion's true date")
        let first = SyncEntry(value: .object(["b": .number(1), "a": .string("same")]), modifiedAt: 100, deleted: false)
        let same = SyncEntry(value: .object(["a": .string("same"), "b": .number(1.0)]), modifiedAt: 100, deleted: false)
        try check(try SavyCloudSyncState.winner(first, same) == first, "JSON object order and equivalent numbers do not create differing versions")
    }

    static func exactPendingAndPersistence(_ directory: URL) throws {
        var original = Story()
        original.body = "Confirmed old writing."
        original.createdAt = Date(timeIntervalSince1970: 10)
        original.updatedAt = Date(timeIntervalSince1970: 100)
        let file = directory.appendingPathComponent("pending-stories.json")
        let local = try stories(file, [original])
        let adapter = StoriesSyncAdapter(store: local)
        let journal = try state(directory, "pending")
        let first = try journal.observeLocal(adapter: adapter, legacyDevice: true, now: 10)[0]
        var edited = original; edited.body = "Second local writing."
        local.save(edited)
        let newest = try journal.observeLocal(adapter: adapter, legacyDevice: true, now: 20)[0]
        try check(newest.entry.modifiedAt > first.entry.modifiedAt, "a slow local clock still advances the portable version")
        try journal.acknowledgeSaved([first], generation: journal.generation)
        try check(journal.pendingRecords.map(\.entry) == [newest.entry], "an old save acknowledgement cannot clear a newer pending edit")
        let reopened = try SavyCloudSyncState(fileURL: journal.fileURL)
        try check(reopened.pendingRecords.map(\.entry) == [newest.entry], "the exact pending edit survives process restart")
        try reopened.accountChanged(to: "original-owner")
        var receipt = newest; receipt.systemFields = Data("new-change-tag".utf8)
        try reopened.acknowledgeSaved([receipt], generation: reopened.generation)
        try check(reopened.pendingRecords.isEmpty && reopened.systemFields(for: receipt.id) == receipt.systemFields,
                  "exact portable acknowledgement accepts differing system-field bytes")

        let savedJournal = try Data(contentsOf: reopened.fileURL)
        let savedEntry = reopened.entry(for: receipt.id)
        try FileManager.default.removeItem(at: reopened.fileURL)
        try FileManager.default.createDirectory(at: reopened.fileURL, withIntermediateDirectories: false)
        var incoming = receipt; incoming.entry.modifiedAt += 10; incoming.entry.value = try SyncJSON.encode(original)
        incoming.systemFields = Data("server-change-tag".utf8)
        try mustThrow("a failed incoming journal write reports failure") { try reopened.retainIncoming([incoming], generation: reopened.generation) }
        try check(reopened.incomingRecords.isEmpty && reopened.entry(for: receipt.id) == savedEntry, "failed journal persistence leaves the confirmed version and pending intent intact")
        try FileManager.default.removeItem(at: reopened.fileURL)
        try savedJournal.write(to: reopened.fileURL)
        try reopened.retainIncoming([incoming], generation: reopened.generation)
        let oldStore = try Data(contentsOf: file)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        try check(try reopened.replayIncoming(using: ["stories": adapter], generation: reopened.generation).isEmpty && reopened.incomingRecords.count == 1,
                  "a failed real-store apply remains durable incoming work")
        let checkpoint = Data("advanced-engine-checkpoint".utf8)
        try reopened.persistEngineState(checkpoint, generation: reopened.generation)
        let afterCheckpoint = try SavyCloudSyncState(fileURL: reopened.fileURL)
        try check(afterCheckpoint.engineState == checkpoint && afterCheckpoint.incomingRecords.map(\.entry) == [incoming.entry],
                  "advanced engine progress cannot erase unapplied incoming records on restart")
        try check(afterCheckpoint.systemFields(for: incoming.id) == incoming.systemFields, "incoming change-tag metadata survives failed application and restart")
        try FileManager.default.removeItem(at: file)
        try oldStore.write(to: file)
        let relaunchedStore = try StoryStore(fileURL: file)
        try mustThrow("restart refuses incoming replay until original-owner verification") {
            _ = try afterCheckpoint.replayIncoming(using: ["stories": StoriesSyncAdapter(store: relaunchedStore)], generation: afterCheckpoint.generation)
        }
        try check(relaunchedStore.stories == (try JSONDecoder.recall.decode([Story].self, from: oldStore))
                  && (try Data(contentsOf: file)) == oldStore && afterCheckpoint.incomingRecords.count == 1,
                  "unverified restart leaves real store and incoming record unchanged")
        try afterCheckpoint.accountChanged(to: "original-owner")
        _ = try afterCheckpoint.replayIncoming(using: ["stories": StoriesSyncAdapter(store: relaunchedStore)], generation: afterCheckpoint.generation)
        try check(afterCheckpoint.incomingRecords.isEmpty && relaunchedStore.stories.first?.body == original.body,
                  "durable incoming writing replays after filesystem recovery")

        // Force the second journal write to fail only after the actual store's atomic write
        // succeeds. The published property triggers this isolated filesystem obstruction.
        let crashState = try state(directory, "apply-crash")
        let crashFile = directory.appendingPathComponent("apply-crash-stories.json")
        let crashStore = try stories(crashFile, [original])
        let crashAdapter = StoriesSyncAdapter(store: crashStore)
        let before = try crashState.observeLocal(adapter: crashAdapter, legacyDevice: true, now: 100)
        var fresh = original; fresh.body = "Durable remote target."; fresh.updatedAt = Date(timeIntervalSince1970: 200)
        let target = record("stories", first.id.key, try SyncJSON.encode(fresh), 200)
        try crashState.retainIncoming([target], generation: crashState.generation)
        var stagedBytes = Data()
        let publication = crashStore.objectWillChange.sink {
            stagedBytes = (try? Data(contentsOf: crashState.fileURL)) ?? Data()
            try? FileManager.default.removeItem(at: crashState.fileURL)
            try? FileManager.default.createDirectory(at: crashState.fileURL, withIntermediateDirectories: false)
        }
        try mustThrow("a journal failure after confirmed store apply is surfaced") {
            _ = try crashState.replayIncoming(using: ["stories": crashAdapter], generation: crashState.generation)
        }
        publication.cancel()
        try check(crashStore.stories.first?.body == fresh.body && crashState.incomingRecords.count == 1,
                  "a successful store apply remains replayable until journal confirmation")
        _ = try crashState.observeLocal(adapter: crashAdapter, legacyDevice: true, now: 1_000_000)
        try check(crashState.pendingRecords.map(\.entry) == before.map(\.entry), "an unconfirmed incoming target is not restamped as a new local edit")
        try FileManager.default.removeItem(at: crashState.fileURL)
        try stagedBytes.write(to: crashState.fileURL)
        let afterCrash = try SavyCloudSyncState(fileURL: crashState.fileURL)
        try afterCrash.accountChanged(to: "original-owner")
        _ = try afterCrash.replayIncoming(using: ["stories": crashAdapter], generation: afterCrash.generation)
        try check(afterCrash.incomingRecords.isEmpty && afterCrash.entry(for: target.id) == target.entry, "restart acknowledges the same confirmed apply target without losing writing")

        // A second fetch must not erase proof of the first already-applied store target.
        var nextIncoming = fresh
        nextIncoming.body = "The next fetched version."
        nextIncoming.updatedAt = Date(timeIntervalSince1970: 300)
        let nextRecord = record("stories", first.id.key, try SyncJSON.encode(nextIncoming), 300)
        try afterCrash.retainIncoming([nextRecord], generation: afterCrash.generation)
        var nextStagedBytes = Data()
        let nextPublication = crashStore.objectWillChange.sink {
            nextStagedBytes = (try? Data(contentsOf: afterCrash.fileURL)) ?? Data()
            try? FileManager.default.removeItem(at: afterCrash.fileURL)
            try? FileManager.default.createDirectory(at: afterCrash.fileURL, withIntermediateDirectories: false)
        }
        try mustThrow("a second confirmed apply can retain its failed journal target") {
            _ = try afterCrash.replayIncoming(using: ["stories": crashAdapter], generation: afterCrash.generation)
        }
        nextPublication.cancel()
        try FileManager.default.removeItem(at: afterCrash.fileURL)
        try nextStagedBytes.write(to: afterCrash.fileURL)
        var evenLater = nextRecord
        evenLater.entry.modifiedAt = 400
        try afterCrash.retainIncoming([evenLater], generation: afterCrash.generation)
        _ = try afterCrash.observeLocal(adapter: crashAdapter, legacyDevice: true, now: 2_000_000)
        try check(afterCrash.pendingRecords.isEmpty && afterCrash.entry(for: target.id) == target.entry,
                  "a subsequent incoming batch preserves recognition of an already-applied target")
        let secondRestart = try SavyCloudSyncState(fileURL: afterCrash.fileURL)
        try secondRestart.accountChanged(to: "original-owner")
        _ = try secondRestart.observeLocal(adapter: crashAdapter, legacyDevice: true, now: 3_000_000)
        try check(secondRestart.pendingRecords.isEmpty, "already-applied target recognition also survives the second fetch and relaunch")
        _ = try secondRestart.replayIncoming(using: ["stories": crashAdapter], generation: secondRestart.generation)
        try check(secondRestart.entry(for: evenLater.id) == evenLater.entry && secondRestart.incomingRecords.isEmpty,
                  "the later received version confirms without inventing a local edit")

        let corruptFile = directory.appendingPathComponent("unreadable-reminders.json")
        let corruptBytes = Data("Original unreadable writing remains here.".utf8)
        try corruptBytes.write(to: corruptFile)
        let corruptStore = ReminderStore(cacheURL: corruptFile, technicalCaptureStore: .init(), candidateOutbox: .init())
        let corruptAdapter = RemindersSyncAdapter(store: corruptStore)
        try mustThrow("an unreadable Reminder source cannot be observed as empty") {
            _ = try afterCrash.observeLocal(adapter: corruptAdapter, legacyDevice: true, now: 300)
        }
        try check(!corruptStore.save(Reminder(title: "Cannot overwrite original"))
                  && !corruptAdapter.applyAndConfirm([:]) && (try Data(contentsOf: corruptFile)) == corruptBytes,
                  "unreadable Reminder bytes are preserved through authoring and incoming apply")
        let corruptJournal = directory.appendingPathComponent("unreadable-state.json")
        try corruptBytes.write(to: corruptJournal)
        try mustThrow("an unreadable journal refuses initialization instead of resetting sync history") {
            _ = try SavyCloudSyncState(fileURL: corruptJournal)
        }
        try check(try Data(contentsOf: corruptJournal) == corruptBytes, "unreadable journal original bytes remain intact")
    }

    static func accountBoundary(_ directory: URL) throws {
        let blocked = directory.appendingPathComponent("account-parent")
        try Data("blocked parent".utf8).write(to: blocked)
        let journal = try SavyCloudSyncState(fileURL: blocked.appendingPathComponent("state.json"))
        try mustThrow("failed original-owner binding is reported") { try journal.accountChanged(to: "original-owner") }
        try check(!journal.canTransport(generation: journal.generation) && journal.originalOwner == nil,
                  "failed original-owner binding cannot authorize transport")
        try FileManager.default.removeItem(at: blocked)
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: false)
        try check(try journal.accountChanged(to: "original-owner") == .authorized,
                  "same-identity retry persists original owner after a failed bind")
        let authorized = journal.generation
        try journal.persistEngineState(Data("original-account-state".utf8), generation: authorized)
        var incomingStory = Story()
        incomingStory.body = "Original account's incoming writing"
        let local = try stories(directory.appendingPathComponent("account-stories.json"), [])
        let adapter = StoriesSyncAdapter(store: local)
        let pendingIncoming = record("stories", "story:\(incomingStory.id.uuidString.lowercased())", try SyncJSON.encode(incomingStory), 100)
        try journal.retainIncoming([pendingIncoming], generation: authorized)
        var publications = 0
        let listener = local.objectWillChange.sink { publications += 1 }
        defer { listener.cancel() }
        try journal.accountChanged(to: nil)
        try check(!journal.canTransport(generation: authorized) && journal.accountStatus == .unavailable,
                  "account sign-out invalidates previously authorized callbacks")
        try mustThrow("signed-out replay refuses the original account's retained incoming") {
            _ = try journal.replayIncoming(using: ["stories": adapter], generation: authorized)
        }
        try journal.accountChanged(to: "different-owner")
        try check(journal.accountStatus == .differentAccount && journal.originalOwner == "original-owner", "another Apple account cannot replace the original owner")
        try mustThrow("old-account engine checkpoints are rejected") { try journal.persistEngineState(Data(), generation: authorized) }
        try mustThrow("other-account fetch callbacks are rejected") { try journal.retainIncoming([], generation: journal.generation) }
        try mustThrow("other-account save callbacks are rejected") { try journal.acknowledgeSaved([], generation: journal.generation) }
        try mustThrow("other-account replay refuses original-owner incoming even with current generation") {
            _ = try journal.replayIncoming(using: ["stories": adapter], generation: journal.generation)
        }
        try check(publications == 0 && local.stories.isEmpty && journal.incomingRecords.count == 1,
                  "invalid account replay performs zero actual-store publication and retains incoming")
        try check(journal.engineState == Data("original-account-state".utf8), "account mismatch preserves original-owner engine progress")
        try journal.accountChanged(to: "original-owner")
        try check(journal.canTransport(generation: journal.generation) && !journal.canTransport(generation: authorized), "returning to original owner resumes with a new generation")
        try mustThrow("returning original owner still rejects prior-generation replay") {
            _ = try journal.replayIncoming(using: ["stories": adapter], generation: authorized)
        }
        try check(publications == 0 && local.stories.isEmpty, "a stale replay cannot apply after the original account returns")
        _ = try journal.replayIncoming(using: ["stories": adapter], generation: journal.generation)
        try check(local.stories.first?.body == incomingStory.body && publications == 1,
                  "authorized original-owner replay resumes the retained incoming version once")
        let restarted = try SavyCloudSyncState(fileURL: journal.fileURL)
        try check(restarted.originalOwner == "original-owner" && !restarted.canTransport(generation: restarted.generation), "restart requires current account verification before using original-owner state")
    }

    static func passthroughAndPins(_ directory: URL) throws {
        let file = directory.appendingPathComponent("unknown-reminders.json")
        let store = try reminders(file, [])
        let adapter = RemindersSyncAdapter(store: store)
        let journal = try state(directory, "unknown")
        let key = "reminder:00000000-0000-0000-0000-000000000001"
        let unknown: SyncJSON = .object(["kind": .string("future-kind"), "exactWriting": .string("Keep every unknown word."),
            "schedule": .object(["calendarIdentifier": .string("foreign"), "alert": .string("hourly")])])
        try journal.retainIncoming([record("reminders", key, unknown, 100)], generation: journal.generation)
        _ = try journal.replayIncoming(using: ["reminders": adapter], generation: journal.generation)
        let reopened = try SavyCloudSyncState(fileURL: journal.fileURL)
        let newAdapter = RemindersSyncAdapter(store: try reminders(file, []))
        _ = try reopened.observeLocal(adapter: newAdapter, legacyDevice: true, now: 200)
        try check(reopened.entry(for: .init(documentKey: "reminders", key: key))?.deleted == false
                  && newAdapter.snapshot()[key] != nil, "unknown incoming writing survives adapter restart without becoming deletion")
        if case .object(let payload) = newAdapter.snapshot()[key], case .object(let schedule) = payload["schedule"] {
            try check(payload["exactWriting"] == .string("Keep every unknown word.") && schedule["calendarIdentifier"] == nil,
                      "unknown passthrough retains writing while excluding native bindings")
        } else { try check(false, "unknown passthrough retains the complete payload") }

        let connectionFile = directory.appendingPathComponent("pin-connections.json")
        let connections = ConnectionStore(fileURL: connectionFile, launchArguments: ["SAVY_UI_TEST_UNLOCKED"])
        var content = Reminder(title: "Pinned authored connection")
        content.createdAt = Date(timeIntervalSince1970: 10)
        try check(connections.save(content), "Connection pin fixture writes its actual store")
        let before = connections.entries[0]
        try check(connections.togglePin(before), "authored Connection pin persists")
        try check(connections.entries[0].metadata.updatedAt == before.metadata.updatedAt
                  && connections.entries[0].metadata.title == before.metadata.title, "Connection pin keeps original writing dates and records its own mutation date")
        try check(connections.setSourcePinned(id: "source", isPinned: true) && connections.deleteSource(id: "hidden-source"), "source pin and source hide persist independently")
        let reloaded = ConnectionStore(fileURL: connectionFile, launchArguments: ["SAVY_UI_TEST_UNLOCKED"])
        let connectionAdapter = ConnectionsSyncAdapter(store: reloaded)
        let values = connectionAdapter.snapshot()
        for key in ["entry:\(content.id.uuidString.lowercased())", "sourcePin:source", "hidden:hidden-source"] {
            let date = reloaded.syncModificationDates[key]
            let stamp = connectionAdapter.stamp(key: key, value: values[key]!, context: .firstRun(legacyDevice: true))
            try check(date != nil && stamp.modifiedAt > 1, "Connection \(key.components(separatedBy: ":")[0]) carries a durable real mutation date")
        }
        let sourcePost = directory.appendingPathComponent("duplicate-number-posts.json")
        var saved = SocialPost(); saved.text = "Keep my reference"; saved.postNumber = 7
        let posts = try SocialPostStore(fileURL: sourcePost)
        let allocator = try PostNumberAllocator(fileURL: directory.appendingPathComponent("isolated-numbering.json"))
        var existing = Reminder(kind: .post); existing.postNumber = 7
        allocator.seed(reminders: [existing], socialPosts: [])
        posts.configurePostNumbering(allocator)
        try check(posts.applySynced([saved]) && posts.posts[0].postNumber == 7, "remote Post apply preserves a stored reference even when a local number is already assigned")
        let emptyFile = directory.appendingPathComponent("empty-posts.json")
        try Data().write(to: emptyFile)
        try mustThrow("an existing empty Post file is unreadable, not an empty collection") { _ = try SocialPostStore(fileURL: emptyFile) }
    }

    static func mixedFailureReplay(_ directory: URL) throws {
        var a = Story()
        a.body = "A confirmed writing."
        a.createdAt = Date(timeIntervalSince1970: 10)
        a.updatedAt = Date(timeIntervalSince1970: 100)
        var b = a; b.body = "B materialized writing."; b.updatedAt = Date(timeIntervalSince1970: 200)
        var c = a; c.body = "C received replacement."; c.updatedAt = Date(timeIntervalSince1970: 300)
        let file = directory.appendingPathComponent("mixed-failure-stories.json")
        let store = try stories(file, [a])
        let adapter = StoriesSyncAdapter(store: store)
        let journal = try state(directory, "mixed-failure")
        let first = try journal.observeLocal(adapter: adapter, legacyDevice: true, now: 100)[0]
        try journal.acknowledgeSaved([first], generation: journal.generation)
        let recordB = record("stories", first.id.key, try SyncJSON.encode(b), 200)
        let recordC = record("stories", first.id.key, try SyncJSON.encode(c), 300)
        try journal.retainIncoming([recordB], generation: journal.generation)
        var preparedB = Data()
        let publication = store.objectWillChange.sink {
            preparedB = (try? Data(contentsOf: journal.fileURL)) ?? Data()
            try? FileManager.default.removeItem(at: journal.fileURL)
            try? FileManager.default.createDirectory(at: journal.fileURL, withIntermediateDirectories: false)
        }
        try mustThrow("mixed failure starts with B applied and final journal confirmation failed") {
            _ = try journal.replayIncoming(using: ["stories": adapter], generation: journal.generation)
        }
        publication.cancel()
        try check(store.stories.first?.body == b.body && journal.entry(for: first.id) == first.entry,
                  "mixed failure retains confirmed A while the real store has materialized B")
        try FileManager.default.removeItem(at: journal.fileURL)
        try preparedB.write(to: journal.fileURL)
        try journal.retainIncoming([recordC], generation: journal.generation)
        let savedB = try Data(contentsOf: file)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        try check(try journal.replayIncoming(using: ["stories": adapter], generation: journal.generation).isEmpty
                  && store.stories.first?.body == b.body, "C replacement fails its real-store write after its journal target is staged")
        _ = try journal.observeLocal(adapter: adapter, legacyDevice: true, now: 9_000_000_000)
        try check(journal.pendingRecords.isEmpty && journal.incomingRecords.map(\.entry) == [recordC.entry],
                  "mixed journal/store failure never restamps materialized B over newer incoming C")
        try FileManager.default.removeItem(at: file)
        try savedB.write(to: file)
        let relaunchedStore = try StoryStore(fileURL: file)
        let restarted = try SavyCloudSyncState(fileURL: journal.fileURL)
        try restarted.accountChanged(to: "original-owner")
        let restartedAdapter = StoriesSyncAdapter(store: relaunchedStore)
        _ = try restarted.observeLocal(adapter: restartedAdapter, legacyDevice: true, now: 10_000_000_000)
        try check(restarted.pendingRecords.isEmpty && restarted.incomingRecords.map(\.entry) == [recordC.entry]
                  && relaunchedStore.stories.first?.body == b.body,
                  "materialized B recognition survives mixed failure, re-observation, and relaunch")
        _ = try restarted.replayIncoming(using: ["stories": restartedAdapter], generation: restarted.generation)
        try check(restarted.incomingRecords.isEmpty && restarted.entry(for: first.id) == recordC.entry
                  && relaunchedStore.stories.first?.body == c.body,
                  "filesystem recovery confirms C without inventing an edit of B")
    }
}
