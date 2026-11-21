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
    /// When each recording was sent, to say how long the iPhone took.
    private var askedAt: [UUID: Date] = [:]

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

    /// The link as the Watch sees it right now, for the trail.
    nonisolated static func state(of session: WCSession) -> String {
        let activation: String
        switch session.activationState {
        case .activated: activation = "activated"
        case .inactive: activation = "inactive"
        case .notActivated: activation = "notActivated"
        @unknown default: activation = "unknown"
        }
        return "link=\(activation) iPhoneReachable=\(session.isReachable ? "yes" : "no") "
            + "iPhoneAppInstalled=\(session.isCompanionAppInstalled ? "yes" : "no")"
    }

    /// Sends a finished recording to the nearby iPhone. Does nothing when the iPhone is out of reach.
    func askPhoneForWords(_ capture: WatchCapture, audioURL: URL) {
        guard WCSession.isSupported() else { return }
        guard isPhoneNearby else {
            WatchCaptureTrail.fail("link.ask", capture: capture.id, "not sent to the iPhone: " + Self.state(of: WCSession.default))
            return
        }
        guard let data = try? Data(contentsOf: audioURL), !data.isEmpty else {
            WatchCaptureTrail.fail("link.ask", capture: capture.id, "not sent to the iPhone: the recording file is empty")
            return
        }
        let id = capture.id
        let idString = id.uuidString
        let ext = audioURL.pathExtension
        let count = (data.count + Self.partSize - 1) / Self.partSize
        waiting.insert(id)
        askedAt[id] = Date()
        WatchCaptureTrail.note("link.ask", capture: id, "sent to the iPhone: parts=\(count) \(data.count / 1_000)KB")
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
            // The system calls this off the main thread; `@Sendable` keeps it from being tied to it.
            WCSession.default.sendMessage(message, replyHandler: nil) { @Sendable [weak self] error in
                // One line for the capture, however many of its parts fail.
                WatchCaptureTrail.fail("link.part", capture: id, once: true, WatchCaptureTrail.reason(error))
                Task { @MainActor in self?.waiting.remove(id) }
            }
        }
        Task { [weak self] in
            try? await Task.sleep(for: Self.patience)
            guard let self, self.askedAt[id] != nil else { return }
            self.askedAt[id] = nil
            self.waiting.remove(id)
            WatchCaptureTrail.fail("link.words", capture: id, "no answer from the iPhone in \(Int(Self.patience.components.seconds))s")
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: (any Error)?) {
        WatchCaptureTrail.note("link.activate", ok: activationState == .activated && error == nil,
                               Self.state(of: session) + (error.map { " " + WatchCaptureTrail.reason($0) } ?? ""))
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        WatchCaptureTrail.note("link.reach", once: true, Self.state(of: session))
    }

    /// The moment the Watch starts, or stops, seeing the iPhone app as its partner.
    nonisolated func sessionCompanionAppInstalledDidChange(_ session: WCSession) {
        WatchCaptureTrail.note("link.state", once: true, Self.state(of: session))
    }

    /// True once the Watch sees the iPhone app as its partner. Without it, a recording sent to
    /// the iPhone fails with WatchConnectivity 7018.
    var seesPhoneApp: Bool {
        WCSession.isSupported() && WCSession.default.isCompanionAppInstalled
    }

    /// The link as the Watch sees it right now, in the trail's words.
    var stateText: String { Self.state(of: WCSession.default) }

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
            let link = WatchPhoneLink.shared
            let took = link.askedAt[id].map { String(format: " after %.1fs", Date().timeIntervalSince($0)) } ?? ""
            link.askedAt[id] = nil
            link.waiting.remove(id)
            if words.isEmpty {
                WatchCaptureTrail.fail("link.words", capture: id, "the iPhone answered with no words" + took)
            } else {
                WatchCaptureTrail.note("link.words", capture: id, "chars=\(words.count)" + took)
                WatchCaptureStore.shared.applyWordsFromPhone(words, to: id)
            }
        }
    }
}
