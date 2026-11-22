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
    func applicationDidFinishLaunching() {
        WatchCaptureTrail.note("app.launch", WatchCaptureTrail.build)
        WatchPhoneLink.shared.activate()
        #if DEBUG && targetEnvironment(simulator)
        Task { await WatchCaptureLinkTest.runIfRequested() }
        #endif
    }

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

#if DEBUG && targetEnvironment(simulator)
/// Simulator link test only. `-WatchCaptureLinkTest <file>` takes a recording the test placed in
/// the app's Audio folder, keeps it as a draft, and sends it to the paired iPhone simulator for
/// its words, exactly as a finished recording is sent. The draft is thrown away afterwards, so
/// nothing is saved or sent to iCloud. Compiled for the simulator only: it cannot exist on a
/// real Watch. Adam, Nov 21, 2026: “Do 1000% of your tests on a fucking simulator.”
enum WatchCaptureLinkTest {
    static var fileName: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-WatchCaptureLinkTest"),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    @MainActor
    static func runIfRequested() async {
        guard let fileName else { return }
        WatchCaptureTrail.note("linktest.start", fileName)
        let link = WatchPhoneLink.shared
        // Give the two simulators up to two minutes to reach each other and to see each other
        // as a pair; the pairing can settle a little after both apps are installed.
        for _ in 0..<120 where !(link.isPhoneNearby && link.seesPhoneApp) {
            try? await Task.sleep(for: .seconds(1))
        }
        WatchCaptureTrail.note("linktest.ready", ok: link.isPhoneNearby && link.seesPhoneApp, link.stateText)
        let store = WatchCaptureStore.shared
        let url = store.linkTestRecordingURL(named: fileName)
        guard FileManager.default.fileExists(atPath: url.path),
              let capture = store.keepRecording(at: url, duration: 5) else {
            WatchCaptureTrail.fail("linktest.done", "the test recording was not found in the Audio folder")
            return
        }
        link.askPhoneForWords(capture, audioURL: url)
        // Longer than the link's own wait under this test (150 seconds), so the link's own line
        // in the trail says how it ended.
        for _ in 0..<170 where link.waiting.contains(capture.id) {
            try? await Task.sleep(for: .seconds(1))
        }
        let words = store.item(id: capture.id)?.capture.words ?? ""
        WatchCaptureTrail.note("linktest.done", capture: capture.id, ok: !words.isEmpty,
                               words.isEmpty ? "no words came back" : "words came back: chars=\(words.count)")
        store.discardDraft(capture.id)
    }
}
#endif

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
