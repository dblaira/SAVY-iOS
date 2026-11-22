import Foundation
import WatchConnectivity
#if canImport(UIKit)
import UIKit
#endif

// Watch capture kit: the same in every app that uses it. iPhone only (the Mac has no Watch link).
//
// Adam, Nov 20, 2026: “If I do [have my phone with me], then the phone should be able to intervene
// or show me the text.” The Watch's live message wakes this app in the background. It collects the
// recording's parts, writes out the words and sends them back to the wrist. It never makes the
// entry: that still happens once, through WatchCaptureImporter, so nothing is ever doubled.

final class WatchCapturePhoneLink: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchCapturePhoneLink()

    private struct Incoming {
        var count: Int
        var fileExtension: String
        var parts: [Int: Data] = [:]
    }

    /// The Watch's request for a capture's words, held until the words are written out.
    private struct Asked {
        let answer: ([String: Any]) -> Void
        let at: Date
    }

    private let lock = NSLock()
    private var incoming: [UUID: Incoming] = [:]
    private var asked: [UUID: Asked] = [:]
    /// Words written out before the Watch's request for them arrived.
    private var ready: [UUID: String] = [:]
    /// An answer older than this may have missed the Watch's wait, so it also goes the older way.
    private static let answerWindow: TimeInterval = 20

    /// Call once at launch, before the first message can arrive.
    func activate() {
        WatchCaptureTrail.note("app.launch", WatchCaptureTrail.build + " " + WatchCaptureTranscriber.authorizationSummary)
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// The link as this iPhone sees it right now, for the trail.
    private static func state(of session: WCSession) -> String {
        let activation: String
        switch session.activationState {
        case .activated: activation = "activated"
        case .inactive: activation = "inactive"
        case .notActivated: activation = "notActivated"
        @unknown default: activation = "unknown"
        }
        return "link=\(activation) watchPaired=\(session.isPaired ? "yes" : "no") "
            + "watchAppInstalled=\(session.isWatchAppInstalled ? "yes" : "no")"
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: (any Error)?) {
        WatchCaptureTrail.note("link.activate", ok: activationState == .activated && error == nil,
                               Self.state(of: session) + (error.map { " " + WatchCaptureTrail.reason($0) } ?? ""))
        // Ask for Speech Recognition while the app is open, so the first recording from the
        // Watch can be written out even when the phone is in a pocket.
        guard activationState == .activated, session.isWatchAppInstalled else { return }
        Task { _ = await WatchCaptureTranscriber.isAuthorized() }
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        WatchCaptureTrail.note("link.state", once: true, Self.state(of: session))
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // A different Watch was paired; connect to it.
        session.activate()
    }

    /// The Watch asks for a capture's words and waits for the answer to this very message. The
    /// answer travels back on the Watch's own message, so it does not depend on this iPhone
    /// having noticed that the Watch app is open. Right after an install it often has not.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        guard message[WatchLinkMessage.type] as? String == WatchLinkMessage.wordsRequest,
              let idString = message[WatchLinkMessage.captureID] as? String,
              let id = UUID(uuidString: idString) else {
            // Anything else is handled as a plain message; its sender is not left waiting.
            self.session(session, didReceiveMessage: message)
            replyHandler([:])
            return
        }
        let words: String? = lock.withLock {
            if let words = ready.removeValue(forKey: id) { return words }
            asked[id] = Asked(answer: replyHandler, at: Date())
            return nil
        }
        guard let words else { return }
        replyHandler(Self.wordsPayload(id: id, words: words))
        WatchCaptureTrail.note("link.reply", capture: id, "chars=\(words.count) sent as the answer to the Watch's request")
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard message[WatchLinkMessage.type] as? String == WatchLinkMessage.recordingPart,
              let idString = message[WatchLinkMessage.captureID] as? String,
              let id = UUID(uuidString: idString),
              let index = message[WatchLinkMessage.index] as? Int,
              let count = message[WatchLinkMessage.count] as? Int, count > 0, (0..<count).contains(index),
              let data = message[WatchLinkMessage.data] as? Data else { return }
        let fileExtension = (message[WatchLinkMessage.fileExtension] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "m4a"
        let (isFirst, complete): (Bool, Data?) = lock.withLock {
            let isFirst = incoming[id] == nil
            var entry = incoming[id] ?? Incoming(count: count, fileExtension: fileExtension)
            entry.parts[index] = data
            guard entry.parts.count == entry.count else {
                incoming[id] = entry
                return (isFirst, nil)
            }
            incoming[id] = nil
            return (isFirst, (0..<entry.count).reduce(into: Data()) { whole, part in whole.append(entry.parts[part] ?? Data()) })
        }
        if isFirst {
            WatchCaptureTrail.note("link.wake", capture: id, "first of \(count) parts arrived from the Watch")
        }
        guard let complete else { return }
        writeOut(id: id, audio: complete, fileExtension: fileExtension, parts: count)
    }

    #if DEBUG && targetEnvironment(simulator)
    /// Simulator link test only: `-WatchCaptureLinkTestWords "<words>"` makes this iPhone answer a
    /// received recording with these words. A simulator on a build machine has no one to allow
    /// Speech Recognition, and the writing out itself is proven on the real iPhone. When the
    /// system opens the app by itself for the Watch's message, as it does with the iPhone in a
    /// pocket, no one can pass that argument, so the test may place the words in a file beside
    /// the trail instead. Compiled for the simulator only.
    private static var linkTestWords: String? {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-WatchCaptureLinkTestWords"),
           arguments.indices.contains(index + 1) {
            return arguments[index + 1]
        }
        let placed = WatchCaptureTrail.file.fileURL.deletingLastPathComponent()
            .appendingPathComponent(linkTestWordsFileName)
        guard let words = try? String(contentsOf: placed, encoding: .utf8) else { return nil }
        let trimmed = words.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static let linkTestWordsFileName = "linktest-words.txt"
    #endif

    private func writeOut(id: UUID, audio: Data, fileExtension: String, parts: Int) {
        let size = "parts=\(parts) \(audio.count / 1_000)KB"
        #if DEBUG && targetEnvironment(simulator)
        if let words = Self.linkTestWords {
            WatchCaptureTrail.note("link.receive", capture: id, size + " simulator link test: answering with set words")
            reply(id: id, words: words)
            return
        }
        #endif
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-\(id.uuidString.lowercased()).\(fileExtension)")
        guard (try? audio.write(to: url, options: [.atomic])) != nil else {
            WatchCaptureTrail.fail("link.receive", capture: id, size + " could not be written to a temporary file")
            reply(id: id, words: "")
            return
        }
        Task {
            #if canImport(UIKit)
            let (backgroundTask, appState): (UIBackgroundTaskIdentifier, String) = await MainActor.run {
                let application = UIApplication.shared
                let state: String
                switch application.applicationState {
                case .active: state = "active"
                case .inactive: state = "inactive"
                case .background: state = "background"
                @unknown default: state = "unknown"
                }
                return (application.beginBackgroundTask(withName: "Watch recording words"),
                        "app=\(state) unlocked=\(application.isProtectedDataAvailable ? "yes" : "no")")
            }
            WatchCaptureTrail.note("link.receive", capture: id, size + " " + appState)
            #else
            WatchCaptureTrail.note("link.receive", capture: id, size)
            #endif
            let words = await WatchCaptureTranscriber.words(fromRecordingAt: url, capture: id)
            try? FileManager.default.removeItem(at: url)
            reply(id: id, words: words ?? "")
            #if canImport(UIKit)
            await MainActor.run { UIApplication.shared.endBackgroundTask(backgroundTask) }
            #endif
        }
    }

    /// Back to the wrist. First as the answer to the Watch's own request, when it is waiting for
    /// one. Otherwise a live message if the Watch app is open, or queued for it.
    private func reply(id: UUID, words: String) {
        let session = WCSession.default
        let payload = Self.wordsPayload(id: id, words: words)
        let waiting: Asked? = lock.withLock {
            if let waiting = asked.removeValue(forKey: id) { return waiting }
            // The request has not arrived yet: keep the words to answer it when it does.
            if ready.count >= 8 { ready.removeAll() }
            ready[id] = words
            return nil
        }
        if let waiting {
            waiting.answer(payload)
            WatchCaptureTrail.note("link.reply", capture: id, "chars=\(words.count) sent as the answer to the Watch's request")
            guard Date().timeIntervalSince(waiting.at) > Self.answerWindow else { return }
        }
        guard session.isReachable else {
            session.transferUserInfo(payload)
            WatchCaptureTrail.note("link.reply", capture: id, "chars=\(words.count) queued: the Watch app is not open")
            return
        }
        WatchCaptureTrail.note("link.reply", capture: id, "chars=\(words.count) sent live")
        session.sendMessage(payload, replyHandler: nil) { error in
            WatchCaptureTrail.fail("link.reply", capture: id,
                                   "the live reply failed (\(WatchCaptureTrail.reason(error))); queued instead")
            WCSession.default.transferUserInfo(Self.wordsPayload(id: id, words: words))
        }
    }

    private static func wordsPayload(id: UUID, words: String) -> [String: Any] {
        [
            WatchLinkMessage.type: WatchLinkMessage.words,
            WatchLinkMessage.captureID: id.uuidString,
            WatchLinkMessage.words: words,
        ]
    }
}
