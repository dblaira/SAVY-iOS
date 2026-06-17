import Foundation
import UserNotifications

struct NativeNotificationScheduler {
    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    func scheduleFollowUp(for entry: CaptureEntry, after interval: TimeInterval = 3600) async throws {
        let content = UNMutableNotificationContent()
        content.title = entry.title.isEmpty ? "SAVY" : entry.title
        content.body = entry.meaning.isEmpty ? "Return to the leverage signal." : entry.meaning
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(60, interval), repeats: false)
        let request = UNNotificationRequest(
            identifier: "savy.capture.\(entry.id.uuidString)",
            content: content,
            trigger: trigger
        )

        try await UNUserNotificationCenter.current().add(request)
    }
}
