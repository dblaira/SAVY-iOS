import Foundation

// Host-side seams: execute the real Connection store and sync adapter without registering
// notifications, touching an app container, or contacting the gateway.
@MainActor
enum NotificationScheduler {
    static var scheduled: [Reminder] = []
    static var cancelled: [UUID] = []
    static func schedule(_ reminder: Reminder) { scheduled.append(reminder) }
    static func cancel(_ reminder: Reminder) { cancelled.append(reminder.id) }
    static func reset() { scheduled = []; cancelled = [] }
}

struct NewsChannelPostPreview {
    init(text: String, additionalDetails: [String]) {}
}

@main
struct ConnectionSyncChecks {
    @MainActor
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("connection-schedule-checks-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            checks += 1
            print("PASS \(message)")
        }
        func store(_ name: String) -> ConnectionStore {
            ConnectionStore(fileURL: root.appendingPathComponent("\(name).json"), launchArguments: ["SAVY_UI_TEST_UNLOCKED"])
        }
        let phone = store("phone")
        let mac = store("mac")
        var record = Reminder(title: "Shared connection")
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        record.schedule = ReminderSchedule(startDate: start, endDate: start.addingTimeInterval(10_800),
                                           alert: .hourly, calendarIdentifier: "phone-calendar",
                                           calendarEventIdentifier: "phone-event")
        record.dueDate = start.addingTimeInterval(-60)
        record.dueTime = start
        record.endTime = record.schedule?.endDate
        check(phone.save(record), "scheduled connection saves locally")
        let local = phone.entries[0]
        let key = "entry:\(record.id.uuidString.lowercased())"
        let phoneAdapter = ConnectionsSyncAdapter(store: phone)
        let snapshot = phoneAdapter.snapshot()
        let shared = try snapshot[key]!.decode(ConnectionEntry.self)
        check(shared.metadata.schedule == nil, "shared snapshot omits Schedule and Calendar identifiers")
        check(shared.metadata.dueDate == nil && shared.metadata.dueTime == nil && shared.metadata.endTime == nil,
              "shared snapshot omits Schedule-owned date and time mirrors")
        check(phone.entries[0] == local, "snapshot leaves the local Schedule untouched")
        NotificationScheduler.reset()
        ConnectionsSyncAdapter(store: mac).apply(snapshot)
        check(mac.entries[0].metadata.schedule == nil && mac.entries[0].metadata.dueDate == nil,
              "a fresh Mac receives content without importing phone alerts")
        check(NotificationScheduler.scheduled.isEmpty && NotificationScheduler.cancelled.isEmpty,
              "receiving shared content does not schedule synthetic alerts")

        var edited = shared
        edited.metadata.title = "Edited on Mac"
        edited.metadata.updatedAt = start.addingTimeInterval(1)
        NotificationScheduler.reset()
        phoneAdapter.apply([key: try SyncJSON.encode(edited)])
        let retained = phone.entries[0].metadata
        check(retained.title == "Edited on Mac", "remote content edits reach the existing connection")
        check(retained.schedule == local.metadata.schedule && retained.dueDate == local.metadata.dueDate
              && retained.dueTime == local.metadata.dueTime && retained.endTime == local.metadata.endTime,
              "remote edits preserve this device's Schedule and exact mirrors")
        check(NotificationScheduler.scheduled.count == 1 && NotificationScheduler.scheduled[0].title == "Edited on Mac",
              "saved remote edits refresh local alert content")
        NotificationScheduler.reset()
        phoneAdapter.apply([key: try SyncJSON.encode(edited)])
        check(NotificationScheduler.scheduled.isEmpty && NotificationScheduler.cancelled.isEmpty,
              "an unchanged sync does not replace alerts")

        let direct = store("direct")
        check(direct.applySynced(entries: [local], sourcePins: [:], hiddenSourceIDs: []), "direct sync apply succeeds")
        check(direct.entries[0].metadata.schedule == nil && direct.entries[0].metadata.endTime == nil,
              "the store also rejects foreign Calendar bindings outside the adapter")

        var legacy = Reminder(title: "Legacy date")
        legacy.dueDate = start
        legacy.dueTime = start
        legacy.endTime = start.addingTimeInterval(3_600)
        check(mac.save(legacy), "legacy date fixture saves")
        let legacyKey = "entry:\(legacy.id.uuidString.lowercased())"
        let legacyShared = try ConnectionsSyncAdapter(store: mac).snapshot()[legacyKey]!.decode(ConnectionEntry.self)
        check(legacyShared.metadata.dueDate == legacy.dueDate && legacyShared.metadata.endTime == legacy.endTime,
              "legacy dates still sync when no local Schedule owns them")

        var future = try SyncJSON.encode(local)
        if case .object(var object) = future, case .object(var metadata) = object["metadata"] {
            metadata["kind"] = .string("future-entry-kind")
            metadata["futureField"] = .string("Keep this unknown content")
            object["metadata"] = .object(metadata)
            future = .object(object)
        }
        let futureAdapter = ConnectionsSyncAdapter(store: store("future"))
        futureAdapter.apply([key: future])
        let futureSnapshot = futureAdapter.snapshot()[key]!
        if case .object(let object) = futureSnapshot, case .object(let metadata) = object["metadata"] {
            check(metadata["schedule"] == nil && metadata["dueTime"] == nil && metadata["dueDate"] == nil
                  && metadata["endTime"] == nil, "undecodable passthrough also strips device-local Schedule fields")
            check(metadata["futureField"] == .string("Keep this unknown content"), "unknown shared content is retained")
        } else { preconditionFailure("Expected the future connection payload") }

        NotificationScheduler.reset()
        check(phone.applySynced(entries: [], sourcePins: [:], hiddenSourceIDs: []), "remote deletion persists")
        check(phone.entries.isEmpty && NotificationScheduler.cancelled == [record.id],
              "remote deletion cancels the deleted connection's local hourly alerts")

        let blocked = store("blocked")
        check(blocked.save(record), "write failure fixture saves initially")
        try FileManager.default.removeItem(at: blocked.fileURL)
        try FileManager.default.createDirectory(at: blocked.fileURL, withIntermediateDirectories: false)
        NotificationScheduler.reset()
        check(!blocked.applySynced(entries: [], sourcePins: [:], hiddenSourceIDs: []), "failed deletion reports the storage error")
        check(blocked.entries.count == 1 && NotificationScheduler.cancelled.isEmpty && NotificationScheduler.scheduled.isEmpty,
              "failed persistence leaves the local record and alerts intact")
        print("\(checks) Connection Schedule sync checks passed")
    }
}
