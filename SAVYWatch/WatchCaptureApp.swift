import SwiftUI
import WatchKit

// Watch capture kit: the same in every app that uses it.

/// Capture on the wrist while moving; process on iPhone or Mac afterwards.
@main
struct WatchCaptureApp: App {
    @WKApplicationDelegateAdaptor(WatchCaptureAppDelegate.self) private var delegate
    @StateObject private var store = WatchCaptureStore.shared

    var body: some Scene {
        WindowGroup {
            CaptureHomeView()
                .environmentObject(store)
        }
    }
}

/// Sends waiting captures whenever the app comes to the front or watchOS wakes it to retry.
@MainActor
final class WatchCaptureAppDelegate: NSObject, WKApplicationDelegate {
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

#if DEBUG
/// Simulator screenshots only: `-WatchCaptureDemo home|proof|calendar` fills a temporary store
/// with each kind's demo words, so the screens can be seen without dictating. Debug builds only;
/// it never touches the real capture file.
enum WatchCaptureDemo {
    static var screen: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-WatchCaptureDemo"),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    static var fileURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("WatchCaptureDemo/captures.json")
    }
}
#endif
