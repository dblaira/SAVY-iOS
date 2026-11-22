import Foundation
import WatchConnectivity
import WatchKit

// Watch capture kit: the same in every app that uses it.
//
// Adam, Nov 20, 2026: “let's just assume that I have my phone with me ... If I do, then the phone
// should be able to intervene or show me the text.” Right after a recording stops, the Watch sends
// it to the iPhone in its pocket. A live message wakes the iPhone app in the background, the
// iPhone writes out the words, and sends them back to the wrist. When the iPhone is out of reach,
// [route icloud]
// nothing changes: the words are written out on the iPhone later, from iCloud.
// [route iphone]
// the capture waits on the Watch, and the iPhone writes out the words when the capture reaches it.
//
// On this route the link also hands each saved capture to the iPhone, which makes the entry and
// answers once it is saved. See `deliver`, at the end of this file.
// [route end]

@MainActor
final class WatchPhoneLink: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchPhoneLink()

    /// Recordings the iPhone is writing out right now.
    @Published private(set) var waiting: Set<UUID> = []
    /// When each recording was sent, to say how long the iPhone took.
    private var askedAt: [UUID: Date] = [:]
    /// Recordings the iPhone has already answered, so a second copy of the answer is ignored.
    private var answered: Set<UUID> = []

    /// Live messages are small; a recording travels in parts of this many bytes.
    private static let partSize = 48_000
    /// How long the wrist shows “writing out” before leaving it to the iPhone's later import.
    private static var patience: Duration {
        #if DEBUG && targetEnvironment(simulator)
        // The simulator link test only. On a build machine a message between the two simulators
        // can take twenty seconds each way, where real devices take about one, so the test
        // waits longer than the wrist does.
        if WatchCaptureLinkTest.fileName != nil { return .seconds(150) }
        #endif
        return .seconds(45)
    }

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
        // Then ask for the words as the answer to a message of the Watch's own. An answer comes
        // back on that message, so it reaches the wrist even when the iPhone has not yet noticed
        // that the Watch app is open, which is common right after an install. An iPhone app from
        // before this request existed does not answer it, and sends the words the older way.
        let request: [String: Any] = [
            WatchLinkMessage.type: WatchLinkMessage.wordsRequest,
            WatchLinkMessage.captureID: idString,
        ]
        WCSession.default.sendMessage(request, replyHandler: { @Sendable answer in
            Self.receive(answer)
        }, errorHandler: { @Sendable error in
            WatchCaptureTrail.fail("link.answer", capture: id, once: true, WatchCaptureTrail.reason(error))
        })
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
// [route iphone]
        // The iPhone is close again: hand it what has been waiting.
        guard session.isReachable else { return }
        Task { @MainActor in await WatchCaptureStore.shared.sendPending() }
// [route end]
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
// [route iphone]
        // The iPhone's answer to a capture the system delivered for the Watch.
        if let answer = WatchCaptureDelivery.answer(in: message) {
            Task { @MainActor in WatchPhoneLink.shared.heard(answer) }
            return
        }
// [route end]
        guard message[WatchLinkMessage.type] as? String == WatchLinkMessage.words,
              let idString = message[WatchLinkMessage.captureID] as? String,
              let id = UUID(uuidString: idString) else { return }
        let words = (message[WatchLinkMessage.words] as? String) ?? ""
        Task { @MainActor in
            let link = WatchPhoneLink.shared
            // The same words can arrive twice: as the answer to the request, and the older way.
            guard link.answered.insert(id).inserted else { return }
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
// [route iphone]

// MARK: - Handing saved captures to the iPhone

extension WatchPhoneLink {
    enum Delivery: Equatable {
        /// The iPhone has saved the entry.
        case saved
        /// The iPhone could not be reached. The system holds the capture and sends it when the
        /// iPhone is close.
        case outOfReach
        /// The iPhone answered, and could not save the entry.
        case couldNotSave
    }

    /// Hands one saved capture to the iPhone and waits for it to say the entry is saved. The
    /// iPhone usually has the recording already, from writing out its words; when it does not,
    /// it asks, and the recording goes first.
    func deliver(_ capture: WatchCapture, audioURL: URL?) async -> Delivery {
        guard WCSession.isSupported() else { return .outOfReach }
        let id = capture.id
        guard let message = try? WatchCaptureDelivery.message(for: capture) else {
            WatchCaptureTrail.fail("phone.send", capture: id, once: true, "the Watch could not prepare it")
            return .couldNotSave
        }
        guard isPhoneNearby else {
            WatchCaptureTrail.note("phone.wait", capture: id, once: true, "the iPhone is out of reach: " + stateText)
            leaveWithSystem(capture, message: message, audioURL: audioURL)
            return .outOfReach
        }
        // Twice at most: once to hand it over, and once more after a recording the iPhone asked for.
        for attempt in 1...2 {
            guard let answer = await ask(message, capture: id) else {
                leaveWithSystem(capture, message: message, audioURL: audioURL)
                return .outOfReach
            }
            switch answer.outcome {
            case .saved:
                WatchCaptureTrail.note("phone.send", capture: id, once: true,
                                       capture.hasRecording ? "on the iPhone, with its recording" : "on the iPhone")
                return .saved
            case .failed:
                WatchCaptureTrail.fail("phone.send", capture: id, once: true,
                                       "the iPhone could not save it: " + (answer.detail ?? "no reason given"))
                return .couldNotSave
            case .needsRecording:
                guard attempt == 1, let audioURL, let data = try? Data(contentsOf: audioURL), !data.isEmpty else {
                    WatchCaptureTrail.fail("phone.send", capture: id, once: true,
                                           attempt == 1 ? "the iPhone asked for the recording, and it is no longer on the Watch"
                                               : "the iPhone asked for the recording a second time")
                    return .couldNotSave
                }
                guard await sendRecording(data, fileExtension: audioURL.pathExtension, for: id) else {
                    leaveWithSystem(capture, message: message, audioURL: audioURL)
                    return .outOfReach
                }
            }
        }
        return .couldNotSave
    }

    /// Sends one message and waits for the iPhone's answer to it. Nil when it did not get through,
    /// or when the iPhone app is one from before captures travelled this way.
    private func ask(_ message: [String: Any], capture id: UUID) async -> WatchCaptureDelivery.Answer? {
        await withCheckedContinuation { (continuation: CheckedContinuation<WatchCaptureDelivery.Answer?, Never>) in
            // The system calls these off the main thread; `@Sendable` keeps them from being tied to it.
            WCSession.default.sendMessage(message, replyHandler: { @Sendable reply in
                let answer = WatchCaptureDelivery.answer(in: reply)
                if answer == nil {
                    WatchCaptureTrail.fail("phone.send", capture: id, once: true, "the iPhone app did not answer as expected")
                }
                continuation.resume(returning: answer)
            }, errorHandler: { @Sendable error in
                WatchCaptureTrail.fail("phone.send", capture: id, once: true, WatchCaptureTrail.reason(error))
                continuation.resume(returning: nil)
            })
        }
    }

    /// Sends a recording in parts, as live messages. True once the iPhone has taken the last part.
    private func sendRecording(_ data: Data, fileExtension: String, for id: UUID) async -> Bool {
        let count = (data.count + Self.partSize - 1) / Self.partSize
        WatchCaptureTrail.note("phone.recording", capture: id,
                               "the iPhone asked for the recording: parts=\(count) \(data.count / 1_000)KB")
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            for index in 0..<count {
                let part = data.subdata(in: (index * Self.partSize)..<min(data.count, (index + 1) * Self.partSize))
                let message: [String: Any] = [
                    WatchLinkMessage.type: WatchLinkMessage.recordingPart,
                    WatchLinkMessage.captureID: id.uuidString,
                    WatchLinkMessage.index: index,
                    WatchLinkMessage.count: count,
                    WatchLinkMessage.fileExtension: fileExtension,
                    WatchLinkMessage.data: part,
                ]
                guard index == count - 1 else {
                    WCSession.default.sendMessage(message, replyHandler: nil) { @Sendable error in
                        WatchCaptureTrail.fail("link.part", capture: id, once: true, WatchCaptureTrail.reason(error))
                    }
                    continue
                }
                // The iPhone answers the last part once it has taken it, and all those before it.
                WCSession.default.sendMessage(message, replyHandler: { @Sendable _ in
                    continuation.resume(returning: true)
                }, errorHandler: { @Sendable error in
                    WatchCaptureTrail.fail("link.part", capture: id, once: true, WatchCaptureTrail.reason(error))
                    continuation.resume(returning: false)
                })
            }
        }
    }

    /// Leaves a capture with the system, which sends it when the iPhone is close again, even when
    /// this app is not open then. The iPhone's answer comes back the same way (`heard`).
    private func leaveWithSystem(_ capture: WatchCapture, message: [String: Any], audioURL: URL?) {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        let key = capture.id.uuidString
        if let audioURL {
            guard !session.outstandingFileTransfers.contains(where: {
                $0.file.metadata?[WatchLinkMessage.captureID] as? String == key
            }) else { return }
            session.transferFile(audioURL, metadata: message)
        } else {
            guard !session.outstandingUserInfoTransfers.contains(where: {
                $0.userInfo[WatchLinkMessage.captureID] as? String == key
            }) else { return }
            session.transferUserInfo(message)
        }
        WatchCaptureTrail.note("phone.queue", capture: capture.id, once: true,
                               "left with the system, to send when the iPhone is close")
    }

    /// The iPhone has the entry, so nothing more of this capture needs to travel.
    func withdraw(_ id: UUID) {
        guard WCSession.isSupported() else { return }
        let key = id.uuidString
        for transfer in WCSession.default.outstandingFileTransfers
        where transfer.file.metadata?[WatchLinkMessage.captureID] as? String == key {
            transfer.cancel()
        }
        for transfer in WCSession.default.outstandingUserInfoTransfers
        where transfer.userInfo[WatchLinkMessage.captureID] as? String == key {
            transfer.cancel()
        }
    }

    /// The iPhone's answer to a capture the system delivered for the Watch.
    fileprivate func heard(_ answer: WatchCaptureDelivery.Answer) {
        guard answer.outcome == .saved else {
            // It stays in the queue, and goes again when this app is open with the iPhone close.
            WatchCaptureTrail.fail("phone.send", capture: answer.id, once: true,
                                   "the iPhone could not save what the system delivered: "
                                       + (answer.detail ?? answer.outcome.rawValue))
            return
        }
        WatchCaptureTrail.note("phone.send", capture: answer.id, once: true, "on the iPhone; it answered later")
        WatchCaptureStore.shared.confirmDelivered(answer.id)
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: (any Error)?) {
        guard let error,
              let id = (fileTransfer.file.metadata?[WatchLinkMessage.captureID] as? String).flatMap(UUID.init(uuidString:))
        else { return }
        WatchCaptureTrail.fail("phone.queue", capture: id, once: true, WatchCaptureTrail.reason(error))
    }
}
// [route end]
