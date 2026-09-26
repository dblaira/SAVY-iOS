import Foundation

// No notification center, Calendar store, real app cache, auth, or candidate endpoint
// is linked into this host-side check. Production ReminderStore and wire types run as-is.
@MainActor enum NotificationScheduler {
    static var scheduled: [Reminder] = []
    static var cancelled: [UUID] = []
    static func schedule(_ value: Reminder) { scheduled.append(value) }
    static func cancel(_ value: Reminder) { cancelled.append(value.id) }
    static func reset() { scheduled = []; cancelled = [] }
}

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
    func enqueue(_ value: TechnicalCapture) {}
    func dueItems(now: Date) -> [CowboyCandidateOutboxItem] { [] }
    func recordReceipt(itemID: UUID, receipt: Bool, now: Date) {}
    func recordFailure(itemID: UUID, message: String, now: Date) {}
}
protocol CowboyCandidateSubmitting: Sendable { func submit(_ payload: String) async throws -> Bool }
struct CowboyCandidateClient: CowboyCandidateSubmitting {
    func submit(_ payload: String) async throws -> Bool { preconditionFailure("Tests must not submit candidates") }
}
@MainActor final class PostNumberAllocator {
    enum Source { case reminder }
    func seed(reminders: [Reminder], socialPosts: [String]) {}
    func number(for: Source, id: UUID, savedNumber: Int?) -> Int { savedNumber ?? 1 }
}
private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }

private actor FakeReminderGateway: ReminderRepository {
    var rows: [Reminder]
    var uploads: [Reminder] = []
    var acceptingWrites = true
    var ready = true
    enum Failure: Error { case offline }
    init(_ rows: [Reminder] = []) { self.rows = rows }
    func ensureReady() async -> Bool { ready }
    func fetchAll() async throws -> [Reminder] { rows }
    func setRows(_ values: [Reminder]) { rows = values }
    func setAcceptingWrites(_ value: Bool) { acceptingWrites = value }
    func setReady(_ value: Bool) { ready = value }
    func uploaded() -> [Reminder] { uploads }
    func upsert(_ reminder: Reminder) async throws {
        guard acceptingWrites else { throw Failure.offline }
        // Exercise the real client payload/row boundary in each direction. Fake the
        // backend's preservation of an omitted legacy Schedule field.
        let payload = try JSONEncoder().encode(GatewayReminderPayload(reminder: reminder, email: nil))
        var object = try JSONSerialization.jsonObject(with: payload) as! [String: Any]
        if object["schedule_version"] == nil, let saved = rows.first(where: { $0.id == reminder.id }) {
            let old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(GatewayReminderPayload(reminder: saved, email: nil))) as! [String: Any]
            object["schedule"] = old["schedule"]
            object["schedule_version"] = old["schedule_version"]
        }
        object["created_at"] = GatewayReminderDates.timestamp(reminder.createdAt)
        object["updated_at"] = GatewayReminderDates.timestamp(reminder.updatedAt)
        let decoded = try JSONDecoder().decode(GatewayReminderRow.self, from: JSONSerialization.data(withJSONObject: object)).reminder
        rows.removeAll { $0.id == decoded.id }
        rows.append(decoded)
        uploads.append(reminder)
    }
    func delete(id: UUID) async throws { rows.removeAll { $0.id == id } }
}

@main @MainActor
struct ReminderSyncChecks {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("reminder-sync-checks-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            checks += 1
            print("PASS \(message)")
        }
        func store(_ name: String, _ repository: FakeReminderGateway, cached: [Reminder] = []) throws -> ReminderStore {
            let cache = root.appendingPathComponent("\(name).json")
            try JSONEncoder.recall.encode(cached).write(to: cache)
            return ReminderStore(repo: repository, cacheURL: cache,
                                 technicalCaptureStore: .init(), candidateOutbox: .init())
        }
        func payload(_ reminder: Reminder) throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(GatewayReminderPayload(reminder: reminder, email: nil))) as! [String: Any]
        }
        func row(_ object: [String: Any]) throws -> Reminder {
            try JSONDecoder().decode(GatewayReminderRow.self, from: JSONSerialization.data(withJSONObject: object)).reminder
        }
        func waitForUpload(_ repository: FakeReminderGateway, count: Int) async {
            for _ in 0..<1_000 {
                if await repository.uploaded().count >= count { return }
                await Task.yield()
            }
            preconditionFailure("Expected the store to upload its saved edit")
        }

        let start = Date(timeIntervalSince1970: 2_000_000_000)
        var phoneEntry = Reminder(title: "Phone entry", notes: "Schedule notes", url: "https://example.com/call")
        phoneEntry.locationName = "Studio"
        phoneEntry.repeatRule = .weekly
        phoneEntry.schedule = ReminderSchedule(startDate: start, endDate: start.addingTimeInterval(10_800),
            timeZoneIdentifier: "America/Los_Angeles", alert: .hourly, travelTimeMinutes: 30,
            calendarIdentifier: "phone-calendar", calendarEventIdentifier: "phone-event",
            invitees: ["guest@example.com"], organizerEmail: "host@example.com")
        phoneEntry.dueDate = start
        phoneEntry.dueTime = start
        phoneEntry.endTime = phoneEntry.schedule!.endDate
        phoneEntry.createdAt = start
        phoneEntry.updatedAt = start
        let object = try payload(phoneEntry)
        let scheduleJSON = object["schedule"] as! [String: Any]
        check(object["schedule_version"] as? Int == 1, "configured old-cache Schedule uploads with version 1")
        check(scheduleJSON["startDate"] as? String == "2033-05-18T03:33:20Z", "wire dates use ISO 8601 instants")
        check(scheduleJSON["calendarIdentifier"] == nil && scheduleJSON["calendarEventIdentifier"] == nil,
              "device Calendar identifiers never enter the gateway payload")
        let wireRoundTrip = try row(object)
        check(wireRoundTrip.schedule == phoneEntry.schedule!.portable, "every portable Schedule field survives the gateway round trip")
        check(wireRoundTrip.notes == phoneEntry.notes && wireRoundTrip.url == phoneEntry.url
              && wireRoundTrip.locationName == phoneEntry.locationName && wireRoundTrip.repeatRule == .weekly,
              "location, notes, URL, and repeat travel with Schedule through existing fields")
        var legacy = phoneEntry
        legacy.schedule = nil
        let legacyPayload = try payload(legacy)
        check(legacyPayload["schedule"] == nil && legacyPayload["schedule_version"] == nil,
              "legacy unscheduled uploads omit both Schedule fields")
        let legacyRow = try row(legacyPayload)
        check(legacyRow.schedule == nil && legacyRow.scheduleSyncVersion == nil, "older gateway rows still decode")
        var cleared = legacy
        cleared.scheduleSyncVersion = 1
        let clearPayload = try payload(cleared)
        check(clearPayload["schedule"] is NSNull && clearPayload["schedule_version"] as? Int == 1,
              "explicit removal sends JSON null and version 1")
        let clearRow = try row(clearPayload)
        check(clearRow.schedule == nil && clearRow.scheduleSyncVersion == 1, "explicit removal survives the row decoder")
        var hostile = object
        var foreignSchedule = scheduleJSON
        foreignSchedule["calendarIdentifier"] = "foreign-calendar"
        foreignSchedule["calendarEventIdentifier"] = "foreign-event"
        hostile["schedule"] = foreignSchedule
        let hostileRow = try row(hostile)
        check(hostileRow.schedule == phoneEntry.schedule!.portable, "row decoder ignores foreign device bindings")
        foreignSchedule["startDate"] = "2033-05-18T03:33:20.125Z"
        hostile["schedule"] = foreignSchedule
        let fractionalRow = try row(hostile)
        check(fractionalRow.schedule?.startDate == start.addingTimeInterval(0.125),
              "ISO 8601 fractional schedule instants from other clients decode")
        foreignSchedule["startDate"] = "invalid"
        hostile["schedule"] = foreignSchedule
        do { _ = try row(hostile); preconditionFailure("Malformed Schedule dates must fail the fetch") }
        catch { check(true, "invalid Schedule data cannot silently become an explicit removal") }

        // A clean phone upgrades its old local settings without rolling back a newer title.
        var remoteLegacy = legacy
        remoteLegacy.title = "Newer cloud title"
        let gateway = FakeReminderGateway([remoteLegacy])
        let phone = try store("phone", gateway, cached: [phoneEntry])
        NotificationScheduler.reset()
        await phone.refresh()
        check(phone.reminders[0].title == remoteLegacy.title, "migration preserves newer server content")
        check(phone.reminders[0].schedule == phoneEntry.schedule && phone.reminders[0].scheduleSyncVersion == 1,
              "migration keeps phone Calendar bindings while marking Schedule for sync")
        let migrated = await gateway.uploaded()
        check(migrated.count == 1 && migrated[0].scheduleSyncVersion == 1, "clean old-cache settings upload automatically after refresh")
        check(phone.pendingSyncCount == 0 && phone.technicalCaptures.isEmpty, "migration finishes without authoring/candidate side effects")

        // A fresh Mac receives actual wire-decoded data and schedules its local alerts.
        let mac = try store("mac", gateway)
        NotificationScheduler.reset()
        await mac.refresh()
        check(mac.reminders[0].schedule == phoneEntry.schedule!.portable, "a fresh Mac receives all portable phone settings")
        check(mac.reminders[0].dueDate == start && mac.reminders[0].dueTime == start
              && mac.reminders[0].endTime == phoneEntry.schedule!.endDate,
              "remote Schedule supplies exact date/time mirrors")
        check(NotificationScheduler.scheduled.count == 1
              && ReminderNotificationPlan.requests(for: NotificationScheduler.scheduled[0], now: start.addingTimeInterval(-60)).count == 4,
              "receiving Hourly settings feeds the four expected bounded local alerts")

        // Save on Mac, upload through the wire, and fetch back onto the phone.
        var edited = mac.reminders[0]
        edited.title = "Edited on Mac"
        edited.schedule!.endDate = start.addingTimeInterval(7_200)
        mac.save(edited)
        await waitForUpload(gateway, count: 2)
        await phone.refresh()
        check(phone.reminders[0].title == edited.title && phone.reminders[0].schedule?.endDate == edited.schedule?.endDate,
              "a saved Mac edit returns to the phone through the gateway")
        check(phone.reminders[0].schedule?.calendarIdentifier == "phone-calendar"
              && phone.reminders[0].schedule?.calendarEventIdentifier == "phone-event",
              "incoming Schedule edits preserve this device's native Calendar link")

        var removed = mac.reminders[0]
        removed.schedule = nil
        removed.dueDate = nil
        removed.dueTime = nil
        removed.endTime = nil
        mac.save(removed)
        await waitForUpload(gateway, count: 3)
        await phone.refresh()
        check(phone.reminders[0].schedule == nil && phone.reminders[0].scheduleSyncVersion == 1,
              "Mac Schedule removal reaches the phone instead of reviving local settings")
        check(phone.reminders[0].dueDate == nil && phone.reminders[0].dueTime == nil && phone.reminders[0].endTime == nil,
              "remote removal also clears stale Schedule date mirrors")
        check(ReminderNotificationPlan.requests(for: phone.reminders[0], now: start.addingTimeInterval(-60)).isEmpty,
              "cleared Schedule yields no replacement alerts")

        await gateway.setRows([])
        NotificationScheduler.reset()
        await phone.refresh()
        check(phone.reminders.isEmpty && NotificationScheduler.cancelled == [phoneEntry.id],
              "remote entry deletion cancels its remaining local notification identifiers")

        // Failed uploads retain an offline edit and retry through the normal store path.
        var pending = phoneEntry
        pending.title = "Offline edit"
        pending.needsSync = true
        pending.scheduleSyncVersion = 1
        let offlineGateway = FakeReminderGateway([wireRoundTrip])
        await offlineGateway.setAcceptingWrites(false)
        let offline = try store("offline", offlineGateway, cached: [pending])
        await offline.refresh()
        check(offline.reminders[0].title == pending.title && offline.reminders[0].schedule == pending.schedule,
              "remote refresh cannot overwrite a pending offline Schedule edit")
        check(offline.pendingSyncCount == 1 && offline.lastSyncFailed, "failed upload remains pending for retry")
        await offlineGateway.setAcceptingWrites(true)
        await offline.refresh()
        check(offline.pendingSyncCount == 0 && !offline.lastSyncFailed, "retry uploads and clears the pending edit")
        let restored = try store("offline", offlineGateway, cached: offline.reminders)
        check(restored.reminders[0].schedule == pending.schedule && restored.reminders[0].scheduleSyncVersion == 1,
              "synced Schedule and local Calendar bindings survive cache reload")

        // Saving an unrelated old entry must not claim an unknown Schedule was removed.
        let unscheduledGateway = FakeReminderGateway()
        await unscheduledGateway.setReady(false)
        let unscheduled = try store("unscheduled", unscheduledGateway)
        unscheduled.save(Reminder(title: "Unrelated legacy edit"))
        check(unscheduled.reminders[0].scheduleSyncVersion == nil, "unrelated legacy save does not fabricate a Schedule removal")
        let removeLegacy = try store("remove-legacy", unscheduledGateway, cached: [phoneEntry])
        var removedLegacy = phoneEntry
        removedLegacy.schedule = nil
        removedLegacy.dueDate = nil
        removedLegacy.dueTime = nil
        removedLegacy.endTime = nil
        removeLegacy.save(removedLegacy)
        check(removeLegacy.reminders[0].scheduleSyncVersion == 1, "removing a configured pre-sync Schedule marks explicit removal")
        let removeAgain = try store("remove-again", unscheduledGateway, cached: [cleared])
        removeAgain.save(legacy)
        check(removeAgain.reminders[0].scheduleSyncVersion == 1, "saving a known Schedule removal retains its sync marker")
        print("\(checks) Reminder Schedule sync checks passed")
    }
}
