import Combine
import Foundation
import UserNotifications

@MainActor
final class ReminderNotificationStatus: ObservableObject {
    @Published var errorMessage: String?
}

/// Kept strongly by NotificationScheduler because UNUserNotificationCenter.delegate is
/// weak. Foreground reminders use the same visible presentation as background reminders.
final class ReminderNotificationPresentationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let presentationOptions: UNNotificationPresentationOptions = [.banner, .list, .sound]

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        Self.presentationOptions
    }
}

/// A delivery seam lets the real scheduler's ordering, cancellation and permission races
/// be exercised without requesting permission or changing the user's pending alerts.
@MainActor
protocol ReminderNotificationDelivering {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func pendingRequests() async -> [UNNotificationRequest]
    func removePendingRequests(withIdentifiers identifiers: [String])
    func add(_ request: UNNotificationRequest) async throws
}

@MainActor
private struct SystemReminderNotificationDelivery: ReminderNotificationDelivering {
    private let center = UNUserNotificationCenter.current()

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }
    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }
    func pendingRequests() async -> [UNNotificationRequest] {
        await center.pendingNotificationRequests()
    }
    func removePendingRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }
}

/// One serialized queue protects the app-wide pending budget. Each entry also carries a
/// generation so an older permission prompt or in-flight add cannot revive an edited,
/// completed, or deleted entry. The next operation waits for the prior add and cleanup.
@MainActor
final class ReminderNotificationCoordinator {
    static let maximumPendingRequests = 64

    private let delivery: any ReminderNotificationDelivering
    private let status: ReminderNotificationStatus
    private let now: () -> Date
    private var generations: [UUID: Int] = [:]
    private var queue: Task<Void, Never>?

    init(
        delivery: any ReminderNotificationDelivering,
        status: ReminderNotificationStatus,
        now: @escaping () -> Date = Date.init
    ) {
        self.delivery = delivery
        self.status = status
        self.now = now
    }

    func schedule(_ reminder: Reminder) { enqueue(reminder, shouldSchedule: true) }
    func cancel(_ reminder: Reminder) { enqueue(reminder, shouldSchedule: false) }

    /// Useful for deterministic tests; saving remains nonblocking in the app.
    func waitForPendingOperations() async { await queue?.value }

    private func enqueue(_ reminder: Reminder, shouldSchedule: Bool) {
        let id = reminder.id
        let generation = (generations[id] ?? 0) + 1
        generations[id] = generation
        let previous = queue
        queue = Task { @MainActor in
            await previous?.value
            guard self.generations[id] == generation else { return }
            let identifiers = ReminderNotificationPlan.cancellationIdentifiers(for: id)
            self.delivery.removePendingRequests(withIdentifiers: identifiers)
            guard shouldSchedule, reminder.status == .active else { return }
            if let validation = reminder.schedule?.validationMessage {
                self.status.errorMessage = validation
                return
            }
            guard !ReminderNotificationPlan.requests(for: reminder, now: self.now()).isEmpty else { return }

            do {
                let authorization = await self.delivery.authorizationStatus()
                guard self.generations[id] == generation else { return }
                switch authorization {
                case .authorized, .provisional, .ephemeral:
                    break
                case .notDetermined:
                    let allowed = try await self.delivery.requestAuthorization()
                    guard self.generations[id] == generation else { return }
                    guard allowed else {
                        self.status.errorMessage = "Allow SAVY notifications in Settings to receive these alerts."
                        return
                    }
                case .denied:
                    self.status.errorMessage = "Allow SAVY notifications in Settings to receive these alerts."
                    return
                @unknown default:
                    self.status.errorMessage = "SAVY could not confirm notification permission."
                    return
                }

                let pending = await self.delivery.pendingRequests()
                guard self.generations[id] == generation else { return }
                // Authorization may have taken long enough for early slots to pass.
                let plans = ReminderNotificationPlan.requests(for: reminder, now: self.now())
                let owned = Set(identifiers)
                let otherCount = pending.filter { !owned.contains($0.identifier) }.count
                guard otherCount + plans.count <= Self.maximumPendingRequests else {
                    self.status.errorMessage = "There is not enough room for all of these alerts. Shorten the hourly period or turn off another entry's alerts."
                    return
                }

                for plan in plans {
                    guard self.generations[id] == generation else {
                        self.delivery.removePendingRequests(withIdentifiers: identifiers)
                        return
                    }
                    let content = UNMutableNotificationContent()
                    content.title = reminder.title.isEmpty ? "Reminder" : reminder.title
                    if !reminder.notes.isEmpty { content.body = reminder.notes }
                    content.sound = .default
                    if reminder.urgent { content.interruptionLevel = .timeSensitive }
                    let trigger = UNCalendarNotificationTrigger(
                        dateMatching: plan.dateComponents, repeats: plan.repeats
                    )
                    try await self.delivery.add(UNNotificationRequest(
                        identifier: plan.identifier, content: content, trigger: trigger
                    ))
                    guard self.generations[id] == generation else {
                        self.delivery.removePendingRequests(withIdentifiers: identifiers)
                        return
                    }
                }
            } catch {
                self.delivery.removePendingRequests(withIdentifiers: identifiers)
                guard self.generations[id] == generation else { return }
                self.status.errorMessage = "The alerts could not be saved: \(error.localizedDescription)"
            }
        }
    }
}

@MainActor
enum NotificationScheduler {
    static let status = ReminderNotificationStatus()
    private static let presentationDelegate = ReminderNotificationPresentationDelegate()
    private static let coordinator = ReminderNotificationCoordinator(
        delivery: SystemReminderNotificationDelivery(), status: status
    )

    static func configurePresentation() {
        guard !ProcessInfo.processInfo.arguments.contains("SAVY_UI_TEST_UNLOCKED") else { return }
        UNUserNotificationCenter.current().delegate = presentationDelegate
    }

    static func schedule(_ reminder: Reminder) {
        guard !ProcessInfo.processInfo.arguments.contains("SAVY_UI_TEST_UNLOCKED") else { return }
        coordinator.schedule(reminder)
    }
    static func cancel(_ reminder: Reminder) {
        guard !ProcessInfo.processInfo.arguments.contains("SAVY_UI_TEST_UNLOCKED") else { return }
        coordinator.cancel(reminder)
    }
}
