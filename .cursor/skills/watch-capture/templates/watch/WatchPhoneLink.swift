import Foundation
import WatchConnectivity
import WatchKit

// Watch capture kit: the same in every app that uses it.
//
// Adam, Nov 20, 2026: “let's just assume that I have my phone with me ... If I do, then the phone
// should be able to intervene or show me the text.” Right after a recording stops, the Watch sends
// it to the iPhone in its pocket. A live message wakes the iPhone app in the background, the
// iPhone writes out the words, and sends them back to the wrist. When the iPhone is out of reach,
// nothing changes: the words are written out on the iPhone later, from iCloud.

@MainActor
final class WatchPhoneLink: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchPhoneLink()

    /// Recordings the iPhone is writing out right now.
    @Published private(set) var waiting: Set<UUID> = []

    /// Live messages are small; a recording travels in parts of this many bytes.
    private static let partSize = 48_000
    /// How long the wrist shows “writing out” before leaving it to the iPhone's later import.
    private static let patience: Duration = .seconds(45)

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    var isPhoneNearby: Bool {
        WCSession.isSupported() && WCSession.default.activationState == .activated && WCSession.default.isReachable
    }

    /// Sends a finished recording to the nearby iPhone. Does nothing when the iPhone is out of reach.
    func askPhoneForWords(_ capture: WatchCapture, audioURL: URL) {
        guard isPhoneNearby, let data = try? Data(contentsOf: audioURL), !data.isEmpty else { return }
        let id = capture.id
        let idString = id.uuidString
        let ext = audioURL.pathExtension
        let count = (data.count + Self.partSize - 1) / Self.partSize
        waiting.insert(id)
        for index in 0..<count {
            let part = data.subdata(in: (index * Self.partSize)..<min(data.count, (index + 1) * Self.partSize))
            let message: [String: Any] = [
                WatchLinkMessage.type: WatchLinkMessage.recordingPart,
                WatchLinkMessage.captureID: idString,
                WatchLinkMessage.index: index,
                WatchLinkMessage.count: count,
                WatchLinkMessage.fileExtension: ext,
                WatchLinkMessage.data: part,
            ]
            WCSession.default.sendMessage(message, replyHandler: nil) { [weak self] _ in
                Task { @MainActor in self?.waiting.remove(id) }
            }
        }
        Task { [weak self] in
            try? await Task.sleep(for: Self.patience)
            self?.waiting.remove(id)
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: (any Error)?) {}

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Self.receive(message)
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Self.receive(userInfo)
    }

    nonisolated private static func receive(_ message: [String: Any]) {
        guard message[WatchLinkMessage.type] as? String == WatchLinkMessage.words,
              let idString = message[WatchLinkMessage.captureID] as? String,
              let id = UUID(uuidString: idString) else { return }
        let words = (message[WatchLinkMessage.words] as? String) ?? ""
        Task { @MainActor in
            WatchPhoneLink.shared.waiting.remove(id)
            if !words.isEmpty { WatchCaptureStore.shared.applyWordsFromPhone(words, to: id) }
        }
    }
}
