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

/// The Action Button's “Capture” shortcut opens the app and asks it to start recording at once,
/// so one press of the orange button is one press to record.
@MainActor
final class WatchCaptureLaunch: ObservableObject {
    static let shared = WatchCaptureLaunch()
    @Published private(set) var recordingRequested = false

    func requestRecording() { recordingRequested = true }

    /// True once per request.
    func takeRecordingRequest() -> Bool {
        guard recordingRequested else { return false }
        recordingRequested = false
        return true
    }
}

#if DEBUG
/// Simulator screenshots only: `-WatchCaptureDemo home|recording|review|saved` fills a temporary
/// store with each kind's demo words and one silent recording, so the screens can be seen
/// without a microphone. Debug builds only; it never touches the real capture files.
enum WatchCaptureDemo {
    static var screen: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-WatchCaptureDemo"),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    static var folder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("WatchCaptureDemo", isDirectory: true)
    }

    /// A silent mono 8 kHz WAV, so the play button has something real to play.
    static func silentWAV(seconds: Int) -> Data {
        let sampleRate: UInt32 = 8_000
        let dataSize = UInt32(seconds) * sampleRate * 2
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36) + dataSize)
        data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(sampleRate); append(sampleRate * 2); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(dataSize)
        data.append(Data(count: Int(dataSize)))
        return data
    }
}
#endif
