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

    private let lock = NSLock()
    private var incoming: [UUID: Incoming] = [:]

    /// Call once at launch, before the first message can arrive.
    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: (any Error)?) {
        // Ask for Speech Recognition while the app is open, so the first recording from the
        // Watch can be written out even when the phone is in a pocket.
        guard activationState == .activated, session.isWatchAppInstalled else { return }
        Task { _ = await WatchCaptureTranscriber.isAuthorized() }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // A different Watch was paired; connect to it.
        session.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard message[WatchLinkMessage.type] as? String == WatchLinkMessage.recordingPart,
              let idString = message[WatchLinkMessage.captureID] as? String,
              let id = UUID(uuidString: idString),
              let index = message[WatchLinkMessage.index] as? Int,
              let count = message[WatchLinkMessage.count] as? Int, count > 0, (0..<count).contains(index),
              let data = message[WatchLinkMessage.data] as? Data else { return }
        let fileExtension = (message[WatchLinkMessage.fileExtension] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "m4a"
        let complete: Data? = lock.withLock {
            var entry = incoming[id] ?? Incoming(count: count, fileExtension: fileExtension)
            entry.parts[index] = data
            guard entry.parts.count == entry.count else {
                incoming[id] = entry
                return nil
            }
            incoming[id] = nil
            return (0..<entry.count).reduce(into: Data()) { whole, part in whole.append(entry.parts[part] ?? Data()) }
        }
        guard let complete else { return }
        writeOut(id: id, audio: complete, fileExtension: fileExtension)
    }

    private func writeOut(id: UUID, audio: Data, fileExtension: String) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-\(id.uuidString.lowercased()).\(fileExtension)")
        guard (try? audio.write(to: url, options: [.atomic])) != nil else { return }
        Task {
            #if canImport(UIKit)
            let backgroundTask = await MainActor.run {
                UIApplication.shared.beginBackgroundTask(withName: "Watch recording words")
            }
            #endif
            let words = await WatchCaptureTranscriber.words(fromRecordingAt: url)
            try? FileManager.default.removeItem(at: url)
            reply(id: id, words: words ?? "")
            #if canImport(UIKit)
            await MainActor.run { UIApplication.shared.endBackgroundTask(backgroundTask) }
            #endif
        }
    }

    /// Back to the wrist: a live message if the Watch app is open, otherwise queued for it.
    private func reply(id: UUID, words: String) {
        let session = WCSession.default
        let payload = Self.wordsPayload(id: id, words: words)
        guard session.isReachable else {
            session.transferUserInfo(payload)
            return
        }
        session.sendMessage(payload, replyHandler: nil) { _ in
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
