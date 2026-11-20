import SwiftUI
import WatchKit

/// SAVY on the wrist: capture while moving, process on iPhone or Mac after the run.
@main
struct SAVYWatchApp: App {
    @WKApplicationDelegateAdaptor(SAVYWatchDelegate.self) private var delegate
    @StateObject private var store = WatchCaptureStore.shared

    var body: some Scene {
        WindowGroup {
            CaptureHomeView()
                .environmentObject(store)
        }
    }
}

/// Sends waiting captures whenever SAVY comes to the front or watchOS wakes it to retry.
@MainActor
final class SAVYWatchDelegate: NSObject, WKApplicationDelegate {
    func applicationDidBecomeActive() {
        Task { await WatchCaptureStore.shared.sendPending() }
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            guard let refresh = task as? WKApplicationRefreshBackgroundTask else {
                task.setTaskCompletedWithSnapshot(false)
                continue
            }
            Task {
                await WatchCaptureStore.shared.sendPending()
                refresh.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}

/// SAVY's colors, so the Watch reads as the same app as the iPhone and Mac.
enum WatchTheme {
    static let navy = Color(red: 8 / 255, green: 23 / 255, blue: 45 / 255)
    static let crimson = Color(red: 230 / 255, green: 14 / 255, blue: 68 / 255)
    static let cream = Color(red: 0xF3 / 255, green: 0xEA / 255, blue: 0xD5 / 255)
}
