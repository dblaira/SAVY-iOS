import Foundation

// Real production storage and sync code, isolated from app data, gateway, and notifications.
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
        func legacyJSON(_ entry: ConnectionEntry) throws -> SyncJSON {
            guard case .object(var object) = try SyncJSON.encode(entry),
                  case .object(var metadata) = object["metadata"] else { preconditionFailure("Expected metadata") }
            ["schedule", "scheduleSyncVersion", "dueDate", "dueTime", "endTime"].forEach { metadata.removeValue(forKey: $0) }
            object["metadata"] = .object(metadata)
            return .object(object)
        }
        let phone = store("phone"), mac = store("mac")
        var record = Reminder(title: "Shared connection")
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        record.schedule = ReminderSchedule(startDate: start, endDate: start.addingTimeInterval(10_800),
                                           timeZoneIdentifier: "America/Los_Angeles", alert: .hourly,
                                           travelTimeMinutes: 20, calendarIdentifier: "phone-calendar",
                                           calendarEventIdentifier: "phone-event", invitees: ["guest@example.com"],
                                           organizerEmail: "organizer@example.com")
        record.repeatRule = .weekly
        record.locationName = "Shared location"
        record.url = "https://example.com/call"
        record.notes = "Shared schedule notes"
        record.dueDate = start
        record.dueTime = start
        record.endTime = record.schedule?.endDate
        check(phone.save(record), "scheduled connection saves locally")
        let local = phone.entries[0]
        let key = "entry:\(record.id.uuidString.lowercased())"
        let phoneAdapter = ConnectionsSyncAdapter(store: phone), macAdapter = ConnectionsSyncAdapter(store: mac)
        let snapshot = phoneAdapter.snapshot()
        let shared = try snapshot[key]!.decode(ConnectionEntry.self)
        check(shared.metadata.schedule == record.schedule?.portable && shared.metadata.scheduleSyncVersion == 1,
              "snapshot publishes portable Schedule with a sync version")
        check(shared.metadata.dueDate == start && shared.metadata.dueTime == start && shared.metadata.endTime == record.endTime,
              "shared snapshot retains Schedule date mirrors")
        check(phone.entries[0] == local, "snapshot leaves local Calendar bindings untouched")
        NotificationScheduler.reset()
        macAdapter.apply(snapshot)
        let received = mac.entries[0].metadata
        check(received.schedule == record.schedule?.portable, "fresh Mac receives all portable Schedule choices")
        check(received.schedule?.calendarIdentifier == nil && received.schedule?.calendarEventIdentifier == nil,
              "fresh Mac never adopts foreign native Calendar identifiers")
        check(received.repeatRule == record.repeatRule && received.locationName == record.locationName
              && received.url == record.url && received.notes == record.notes,
              "Repeat, location, URL, and notes travel with Schedule")
        check(NotificationScheduler.scheduled == [received] && NotificationScheduler.cancelled.isEmpty,
              "received Schedule refreshes local notification plans after saving")
        check(store("mac").entries == mac.entries, "received Schedule survives relaunch")

        var edited = mac.entries[0].metadata
        edited.title = "Edited on Mac"
        edited.schedule?.endDate = start.addingTimeInterval(7_200)
        edited.schedule?.travelTimeMinutes = 40
        edited.schedule?.invitees = ["second@example.com"]
        edited.schedule?.calendarIdentifier = "mac-calendar"
        edited.schedule?.calendarEventIdentifier = "mac-event"
        edited.endTime = edited.schedule?.endDate
        check(mac.save(edited), "Mac Schedule edits save")
        NotificationScheduler.reset()
        phoneAdapter.apply(macAdapter.snapshot())
        let updated = phone.entries[0].metadata
        check(updated.title == edited.title && updated.schedule?.portable == edited.schedule?.portable,
              "Mac Schedule edits and Hourly end time reach phone")
        check(updated.schedule?.calendarIdentifier == "phone-calendar" && updated.schedule?.calendarEventIdentifier == "phone-event",
              "remote edits preserve the phone Calendar binding")
        check(updated.dueDate == start && updated.dueTime == start && updated.endTime == edited.schedule?.endDate,
              "remote Schedule edits refresh feed mirrors")
        check(NotificationScheduler.scheduled == [updated] && NotificationScheduler.cancelled.isEmpty,
              "saved remote edits replace local notification plans")
        NotificationScheduler.reset()
        phoneAdapter.apply(macAdapter.snapshot())
        check(NotificationScheduler.scheduled.isEmpty && NotificationScheduler.cancelled.isEmpty,
              "unchanged sync does not replace alerts")
        macAdapter.apply(phoneAdapter.snapshot())
        check(mac.entries[0].metadata.schedule?.calendarIdentifier == "mac-calendar"
              && mac.entries[0].metadata.schedule?.calendarEventIdentifier == "mac-event",
              "round trip retains each device's own Calendar binding")

        var oldEdit = phone.entries[0]
        oldEdit.metadata.title = "Writing from older app"
        phoneAdapter.apply([key: try legacyJSON(oldEdit)])
        check(phone.entries[0].metadata.title == oldEdit.metadata.title && phone.entries[0].metadata.schedule == updated.schedule,
              "legacy writing updates preserve local Schedule")
        check(phone.entries[0].metadata.scheduleSyncVersion == 1 && !phone.entries[0].metadata.needsSync,
              "Connection migration uses document dirty tracking")
        let direct = store("direct")
        check(direct.applySynced(entries: [local], sourcePins: [:], hiddenSourceIDs: []), "direct sync apply succeeds")
        check(direct.entries[0].metadata.schedule == local.metadata.schedule?.portable,
              "store rejects foreign Calendar bindings without relying on adapter")

        var legacy = Reminder(title: "Legacy date")
        legacy.dueDate = start
        legacy.dueTime = start
        legacy.endTime = start.addingTimeInterval(3_600)
        let legacyStore = store("legacy")
        check(legacyStore.save(legacy), "legacy date fixture saves")
        let legacyKey = "entry:\(legacy.id.uuidString.lowercased())"
        let legacyAdapter = ConnectionsSyncAdapter(store: legacyStore)
        var legacyShared = try legacyAdapter.snapshot()[legacyKey]!.decode(ConnectionEntry.self)
        check(legacyShared.metadata.scheduleSyncVersion == nil && legacyShared.metadata.dueDate == legacy.dueDate
              && legacyShared.metadata.endTime == legacy.endTime,
              "legacy dates survive without declaring Schedule removal")
        legacyShared.metadata.title = "Only the writing changed"
        check(legacyStore.save(legacyShared.metadata), "legacy content edit saves")
        check(legacyStore.entries[0].metadata.scheduleSyncVersion == nil,
              "editing legacy writing alone does not erase a remote Schedule")

        let migrationStore = store("migration")
        check(migrationStore.save(record), "migration fixture saves")
        let migration = SavySyncDocument(adapter: ConnectionsSyncAdapter(store: migrationStore), directory: root.appendingPathComponent("shadow"))
        var newerWriting = migrationStore.entries[0]
        newerWriting.metadata.title = "Newer shared writing"
        let legacyStamp = start.timeIntervalSince1970 + 100
        let oldValue = try legacyJSON(newerWriting)
        check(migration.absorb([key: SyncEntry(value: oldValue, modifiedAt: legacyStamp, deleted: false)]),
              "real sync engine absorbs legacy document")
        check(migrationStore.entries[0].metadata.title == newerWriting.metadata.title
              && migrationStore.entries[0].metadata.schedule == record.schedule,
              "migration combines newer writing with existing local Schedule")
        check(migration.recordLocalChanges(now: legacyStamp - 500, legacyDevice: true),
              "retained Schedule becomes a pending document change")
        check(migration.shadow.pendingEntries[key]!.modifiedAt > legacyStamp,
              "migration stamps after server document despite a slower local clock")
        let pending = try migration.shadow.pendingEntries[key]!.value!.decode(ConnectionEntry.self)
        check(pending.metadata.schedule == record.schedule?.portable, "migration upload contains no native identifiers")

        var future = try SyncJSON.encode(local)
        if case .object(var object) = future, case .object(var metadata) = object["metadata"] {
            metadata["kind"] = .string("future-entry-kind")
            metadata["futureField"] = .string("Keep this unknown content")
            object["metadata"] = .object(metadata)
            future = .object(object)
        }
        let futureAdapter = ConnectionsSyncAdapter(store: store("future"))
        futureAdapter.apply([key: future])
        if case .object(let object) = futureAdapter.snapshot()[key]!, case .object(let metadata) = object["metadata"],
           case .object(let schedule) = metadata["schedule"] {
            check(schedule["calendarIdentifier"] == nil && schedule["calendarEventIdentifier"] == nil,
                  "undecodable passthrough strips native Calendar identifiers")
            check(schedule["alert"] == .string("hourly") && metadata["scheduleSyncVersion"] == .number(1),
                  "undecodable passthrough retains portable Schedule")
            check(metadata["futureField"] == .string("Keep this unknown content"), "unknown content is retained")
        } else { preconditionFailure("Expected future connection payload") }

        var removed = mac.entries[0].metadata
        removed.schedule = nil
        removed.dueDate = nil
        removed.dueTime = nil
        removed.endTime = nil
        check(mac.save(removed), "explicit Schedule removal saves")
        let removal = try macAdapter.snapshot()[key]!.decode(ConnectionEntry.self)
        check(removal.metadata.schedule == nil && removal.metadata.scheduleSyncVersion == 1,
              "removal snapshot retains version marker")
        NotificationScheduler.reset()
        phoneAdapter.apply(macAdapter.snapshot())
        check(phone.entries[0].metadata.schedule == nil && phone.entries[0].metadata.dueDate == nil
              && phone.entries[0].metadata.dueTime == nil && phone.entries[0].metadata.endTime == nil,
              "remote removal clears Schedule and feed mirrors")
        check(NotificationScheduler.cancelled == [record.id] && NotificationScheduler.scheduled.isEmpty,
              "saved remote removal cancels local hourly alerts")
        phoneAdapter.apply([key: try legacyJSON(local)])
        check(phone.entries[0].metadata.schedule == nil && phone.entries[0].metadata.scheduleSyncVersion == 1,
              "legacy document cannot undo known Schedule removal")
        check(phone.save(record), "deletion fixture restores Schedule")
        NotificationScheduler.reset()
        check(phone.applySynced(entries: [], sourcePins: [:], hiddenSourceIDs: []), "remote deletion persists")
        check(phone.entries.isEmpty && NotificationScheduler.cancelled == [record.id], "remote deletion cancels local alerts")

        let blocked = store("blocked")
        check(blocked.save(record), "write failure fixture saves initially")
        let beforeFailure = blocked.entries
        try FileManager.default.removeItem(at: blocked.fileURL)
        try FileManager.default.createDirectory(at: blocked.fileURL, withIntermediateDirectories: false)
        NotificationScheduler.reset()
        for (label, entries) in [("update", [ConnectionEntry(metadata: edited)]), ("removal", [removal]), ("deletion", [])] {
            check(!blocked.applySynced(entries: entries, sourcePins: [:], hiddenSourceIDs: []), "failed \(label) reports storage error")
            check(blocked.entries == beforeFailure && NotificationScheduler.cancelled.isEmpty && NotificationScheduler.scheduled.isEmpty,
                  "failed \(label) leaves local record and alerts intact")
        }

        let blockedAdapter = ConnectionsSyncAdapter(store: blocked)
        let blockedDocument = SavySyncDocument(adapter: blockedAdapter, directory: root.appendingPathComponent("blocked-shadow"))
        _ = blockedDocument.recordLocalChanges(now: legacyStamp - 100, legacyDevice: true)
        _ = blockedDocument.absorb(blockedDocument.shadow.entries)
        let confirmedShadow = blockedDocument.shadow
        check(confirmedShadow.pending.isEmpty, "write failure regression starts from acknowledged content")
        var authoritative = shared
        authoritative.metadata.title = "Authoritative remote update"
        authoritative.metadata.schedule?.endDate = start.addingTimeInterval(3_600)
        let incoming = [key: SyncEntry(value: try SyncJSON.encode(authoritative), modifiedAt: legacyStamp, deleted: false)]
        check(!blockedDocument.absorb(incoming), "document engine refuses failed local persistence")
        check(blockedDocument.shadow == confirmedShadow && blocked.entries == beforeFailure,
              "failed apply retains both confirmed shadow and original local content")
        check(!blockedDocument.recordLocalChanges(now: legacyStamp + 1, legacyDevice: true)
              && blockedDocument.shadow.pending.isEmpty,
              "failed apply never becomes an upload of stale content")
        let failedFutureSnapshot = blockedAdapter.snapshot()
        check(!blockedAdapter.applyAndConfirm([key: future]) && blockedAdapter.snapshot() == failedFutureSnapshot,
              "failed apply does not change undecodable passthrough state")
        try FileManager.default.removeItem(at: blocked.fileURL)
        NotificationScheduler.reset()
        check(blockedDocument.absorb(incoming), "the same server update retries after storage recovers")
        check(blocked.entries[0].metadata.title == authoritative.metadata.title
              && blocked.entries[0].metadata.schedule?.portable == authoritative.metadata.schedule,
              "recovered write applies authoritative Schedule choices")
        check(blockedDocument.shadow.entries[key] == incoming[key] && blockedDocument.shadow.pending.isEmpty,
              "successful retry acknowledges the server version")
        check(NotificationScheduler.scheduled.count == 1 && NotificationScheduler.cancelled.isEmpty,
              "successful retry updates notifications exactly once")
        let restoredShadow = SavySyncDocument(adapter: blockedAdapter, directory: root.appendingPathComponent("blocked-shadow"))
        check(restoredShadow.shadow == blockedDocument.shadow, "confirmed retry shadow survives relaunch")
        print("\(checks) Connection Schedule sync checks passed")
    }
}
