import Foundation
import UserNotifications

@MainActor
final class FakeDelivery: ReminderNotificationDelivering {
    var authorization: UNAuthorizationStatus = .authorized
    var pending: [String: UNNotificationRequest] = [:]
    var removals: [[String]] = []
    var added: [UNNotificationRequest] = []
    var permissionContinuation: CheckedContinuation<Bool, Never>?
    var addContinuation: CheckedContinuation<Void, Never>?
    var suspendNextAdd = false
    var failOnAddNumber: Int?

    enum Failure: Error { case rejected }
    func authorizationStatus() async -> UNAuthorizationStatus { authorization }
    func requestAuthorization() async throws -> Bool {
        await withCheckedContinuation { permissionContinuation = $0 }
    }
    func pendingRequests() async -> [UNNotificationRequest] { Array(pending.values) }
    func removePendingRequests(withIdentifiers identifiers: [String]) {
        removals.append(identifiers)
        identifiers.forEach { pending.removeValue(forKey: $0) }
    }
    func add(_ request: UNNotificationRequest) async throws {
        if suspendNextAdd {
            suspendNextAdd = false
            await withCheckedContinuation { addContinuation = $0 }
        }
        if added.count + 1 == failOnAddNumber { throw Failure.rejected }
        added.append(request)
        pending[request.identifier] = request
    }
}

@main
@MainActor
struct DeliveryChecks {
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
        checks += 1
    }
    static func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<10_000 {
            if condition() { return }
            await Task.yield()
        }
        preconditionFailure("Test operation did not reach its suspension point")
    }
    static func fixture() -> Reminder {
        let start = ISO8601DateFormatter().date(from: "2060-09-26T16:00:00Z")!
        var item = Reminder(title: "Synthetic hourly reminder")
        item.schedule = ReminderSchedule(startDate: start, endDate: start.addingTimeInterval(10_800), alert: .hourly)
        return item
    }
    static func setup(_ delivery: FakeDelivery) -> (ReminderNotificationCoordinator, ReminderNotificationStatus) {
        let status = ReminderNotificationStatus()
        let now = fixture().schedule!.startDate.addingTimeInterval(-60)
        return (ReminderNotificationCoordinator(delivery: delivery, status: status, now: { now }), status)
    }
    static func main() async {
        let foreground = ReminderNotificationPresentationDelegate.presentationOptions
        expect(foreground.contains(.banner), "Foreground notifications must present a visible banner")
        expect(foreground.contains(.list), "Foreground notifications must stay in Notification Center")
        expect(foreground.contains(.sound), "Foreground notifications must request their normal sound")
        let item = fixture()
        let actual = FakeDelivery()
        let (coordinator, _) = setup(actual)
        coordinator.schedule(item)
        await coordinator.waitForPendingOperations()
        expect(actual.pending.count == 4, "A complete hourly window must reach the notification delivery boundary")
        let plans = ReminderNotificationPlan.requests(for: item, now: item.schedule!.startDate.addingTimeInterval(-60))
        for plan in plans {
            let trigger = actual.pending[plan.identifier]!.trigger as! UNCalendarNotificationTrigger
            expect(!trigger.repeats, "The actual native hourly trigger must not repeat")
            expect(trigger.dateComponents == plan.dateComponents, "The actual native trigger must contain the planned instant")
            expect(trigger.nextTriggerDate() == plan.fireDate, "The system trigger must resolve to the concrete scheduled instant")
        }
        var shorter = item
        shorter.schedule!.endDate = shorter.schedule!.startDate.addingTimeInterval(3_600)
        coordinator.schedule(shorter)
        await coordinator.waitForPendingOperations()
        expect(actual.pending.count == 2, "Editing the end must remove every obsolete later alert")
        var completed = shorter
        completed.status = .completed
        coordinator.schedule(completed)
        await coordinator.waitForPendingOperations()
        expect(actual.pending.isEmpty, "Completion must remove pending alerts")
        coordinator.schedule(item)
        coordinator.cancel(item)
        await coordinator.waitForPendingOperations()
        expect(actual.pending.isEmpty, "Queued schedule followed by delete must not revive the entry")

        let permission = FakeDelivery()
        permission.authorization = .notDetermined
        let (permissionCoordinator, _) = setup(permission)
        permissionCoordinator.schedule(item)
        await waitUntil { permission.permissionContinuation != nil }
        permissionCoordinator.cancel(item)
        permission.permissionContinuation!.resume(returning: true)
        permission.permissionContinuation = nil
        await permissionCoordinator.waitForPendingOperations()
        expect(permission.pending.isEmpty && permission.added.isEmpty, "Permission completing after cancellation must not enqueue any notification")

        let editRace = FakeDelivery()
        editRace.suspendNextAdd = true
        let (editCoordinator, _) = setup(editRace)
        editCoordinator.schedule(item)
        await waitUntil { editRace.addContinuation != nil }
        editCoordinator.schedule(shorter)
        editRace.addContinuation!.resume()
        editRace.addContinuation = nil
        await editCoordinator.waitForPendingOperations()
        expect(editRace.pending.count == 2, "An old in-flight add must not restore slots removed by an edit")
        let remainingIDs = Set(ReminderNotificationPlan.requests(for: shorter, now: item.schedule!.startDate.addingTimeInterval(-60)).map(\.identifier))
        expect(Set(editRace.pending.keys) == remainingIDs, "Only the latest edit's exact request IDs may remain")

        let deleteRace = FakeDelivery()
        deleteRace.suspendNextAdd = true
        let (deleteCoordinator, _) = setup(deleteRace)
        deleteCoordinator.schedule(item)
        await waitUntil { deleteRace.addContinuation != nil }
        deleteCoordinator.cancel(item)
        deleteRace.addContinuation!.resume()
        deleteRace.addContinuation = nil
        await deleteCoordinator.waitForPendingOperations()
        expect(deleteRace.pending.isEmpty, "Deletion must clean up a request that finishes adding after delete")

        let denied = FakeDelivery()
        denied.authorization = .denied
        let (deniedCoordinator, deniedStatus) = setup(denied)
        deniedCoordinator.schedule(item)
        await deniedCoordinator.waitForPendingOperations()
        expect(denied.added.isEmpty && deniedStatus.errorMessage != nil, "Denied permission must show a failure without scheduling")

        let capacity = FakeDelivery()
        for index in 0..<61 {
            let id = "unrelated.\(index)"
            capacity.pending[id] = UNNotificationRequest(identifier: id, content: UNMutableNotificationContent(), trigger: nil)
        }
        let (capacityCoordinator, capacityStatus) = setup(capacity)
        capacityCoordinator.schedule(item)
        await capacityCoordinator.waitForPendingOperations()
        expect(capacity.pending.count == 61 && capacity.added.isEmpty, "Capacity failure must preserve unrelated alerts and avoid a partial hourly run")
        expect(capacityStatus.errorMessage != nil, "Capacity failure must be surfaced to the form")

        let partial = FakeDelivery()
        partial.failOnAddNumber = 2
        let (partialCoordinator, partialStatus) = setup(partial)
        partialCoordinator.schedule(item)
        await partialCoordinator.waitForPendingOperations()
        expect(partial.pending.isEmpty && partialStatus.errorMessage != nil, "A rejected add must remove the partial run and report failure")

        let parallelEntries = FakeDelivery()
        for index in 0..<59 {
            let id = "unrelated.\(index)"
            parallelEntries.pending[id] = UNNotificationRequest(identifier: id, content: UNMutableNotificationContent(), trigger: nil)
        }
        let (parallelCoordinator, parallelStatus) = setup(parallelEntries)
        var second = item
        second.id = UUID()
        parallelCoordinator.schedule(item)
        parallelCoordinator.schedule(second)
        await parallelCoordinator.waitForPendingOperations()
        expect(parallelEntries.pending.count == 63 && parallelStatus.errorMessage != nil, "Concurrent entry saves must share one serialized capacity check")
        print("PASS: \(checks) native trigger, cancellation, edit, permission, and capacity checks")
    }
}
