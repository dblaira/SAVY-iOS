import Foundation
import WatchConnectivity
#if canImport(UIKit)
import UIKit
#endif

// Watch capture kit, iPhone route: the same in every app that uses it. iPhone only. For an app
// that makes no iCloud calls ("route": "iphone" in watch-capture.json).

/// Where Watch captures become entries. Each app conforms its own store, so a capture is saved
/// through the same path the app's own Save uses and then syncs like any other entry.
@MainActor
protocol WatchCaptureDestination: AnyObject {
    /// False while the app's own storage could not be read; nothing is saved then.
    var acceptsWatchCaptures: Bool { get }
    /// True when an entry made from this capture already exists, including a deleted one
    /// the store still remembers.
    func hasEntry(forWatchCapture id: UUID) -> Bool
    /// Saves one capture as an entry. For a recording, `capture.words` already holds the words
    /// this device wrote out (empty if it could not). False when the local write failed.
    func saveEntry(fromWatchCapture capture: WatchCapture) -> Bool
}

/// Turns each capture the Watch hands over into one entry, and tells the Watch once it is saved.
///
/// The Watch sends a capture again until it hears that. An entry's id is its capture's id, so a
/// capture that arrives a second time, or after its entry was deleted, never makes a second entry.
@MainActor
final class WatchCaptureReceiver {
    static let shared = WatchCaptureReceiver()

    /// The app's own store. Asked for each capture, because the Watch's message can launch the
    /// app in the background before the store is open.
    var destination: @MainActor () -> (any WatchCaptureDestination)? = { nil }

    /// What the receiver does outside the store. Tests give their own, so they write nothing
    /// into the app's folders and never start the speech recognizer.
    struct Tools: Sendable {
        /// The recording already kept beside an entry, if this device has it.
        var keptRecording: @Sendable (UUID) -> URL?
        /// Keeps a recording beside its entry. Nil when it could not be written.
        var keepRecording: @Sendable (URL, WatchCapture) -> URL?
        /// Writes out a recording's words. Nil when it could not.
        var writeOut: @Sendable (URL, UUID) async -> String?
        /// Recordings and words that arrived before their capture.
        var incoming: WatchIncomingRecordings

        static var live: Tools {
            Tools(keptRecording: { WatchRecordingFiles.url(for: $0) },
                  keepRecording: { WatchRecordingFiles.keep($0, for: $1) },
                  writeOut: { await WatchCaptureTranscriber.words(fromRecordingAt: $0, capture: $1) },
                  incoming: .shared)
        }
    }

    /// Makes the entry for one capture, unless it exists already, and answers for the Watch.
    func receive(_ capture: WatchCapture, tools: Tools = .live) async -> WatchCaptureDelivery.Answer {
        func answer(_ outcome: WatchCaptureDelivery.Outcome, _ detail: String? = nil) -> WatchCaptureDelivery.Answer {
            WatchCaptureDelivery.Answer(id: capture.id, outcome: outcome, detail: detail)
        }
        guard let destination = destination(), destination.acceptsWatchCaptures else {
            WatchCaptureTrail.fail("phone.entry", capture: capture.id, once: true,
                                   "this app's own entries could not be read")
            return answer(.failed, "this app's own entries could not be read")
        }
        if destination.hasEntry(forWatchCapture: capture.id) {
            // Sent again: the Watch did not hear the first answer. Still one entry.
            WatchCaptureTrail.note("phone.seen", capture: capture.id, once: true,
                                   "its entry is already here; the Watch was told again")
            tools.incoming.forget(capture.id)
            return answer(.saved)
        }
        var recording = tools.keptRecording(capture.id)
        if capture.hasRecording, recording == nil {
            guard let held = tools.incoming.recording(for: capture.id) else {
                WatchCaptureTrail.note("phone.ask", capture: capture.id, once: true,
                                       "its recording is not on this iPhone; asked the Watch for it")
                return answer(.needsRecording)
            }
            recording = tools.keepRecording(held, capture)
            guard recording != nil else {
                // Without the recording there are no words to write out. Leave it with the Watch
                // and try again, so it never becomes an empty entry.
                WatchCaptureTrail.fail("phone.entry", capture: capture.id, once: true,
                                       "this iPhone could not keep the recording; the Watch will send it again")
                return answer(.failed, "the recording could not be kept")
            }
        }
        var finished = capture
        if capture.words.isEmpty, let recording {
            var words = tools.incoming.words(for: capture.id)
            if words == nil { words = await tools.writeOut(recording, capture.id) }
            if let words, !words.isEmpty { finished = capture.replacingWords(words) }
        }
        // Writing out the words can take a while, and the same capture can arrive again meanwhile.
        if destination.hasEntry(forWatchCapture: capture.id) {
            tools.incoming.forget(capture.id)
            return answer(.saved)
        }
        guard destination.acceptsWatchCaptures, destination.saveEntry(fromWatchCapture: finished) else {
            WatchCaptureTrail.fail("phone.entry", capture: capture.id,
                                   "this iPhone could not save the entry; the Watch will send it again")
            return answer(.failed, "the entry could not be saved")
        }
        WatchCaptureTrail.note("phone.entry", capture: capture.id,
                               "entry saved as \(finished.kind.rawValue) chars=\(finished.words.count) "
                                   + "recording=\(recording != nil ? "yes" : "no")")
        tools.incoming.forget(capture.id)
        return answer(.saved)
    }

    // MARK: From the link (called on the link's own thread)

    /// The Watch's own message, held until its answer is ready.
    private struct Reply: @unchecked Sendable {
        let send: ([String: Any]) -> Void
    }

    /// A capture sent as a live message: the answer goes back on that message. False when the
    /// message is not a capture.
    nonisolated static func take(_ message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) -> Bool {
        guard message[WatchLinkMessage.type] as? String == WatchLinkMessage.capture else { return false }
        let reply = Reply(send: replyHandler)
        guard let capture = WatchCaptureDelivery.capture(in: message) else {
            reply.send(WatchCaptureDelivery.message(for: unreadable(message)))
            return true
        }
        Task { @MainActor in
            let answer = await shared.receiveKeepingAwake(capture)
            reply.send(WatchCaptureDelivery.message(for: answer))
        }
        return true
    }

    /// A capture the system held until the iPhone was close again. The recording file is only
    /// there until this returns, so it is copied first. The answer travels back the same way.
    nonisolated static func take(queued message: [String: Any], recordingAt url: URL?) {
        guard message[WatchLinkMessage.type] as? String == WatchLinkMessage.capture else { return }
        guard let capture = WatchCaptureDelivery.capture(in: message) else {
            send(unreadable(message))
            return
        }
        if let url { WatchIncomingRecordings.shared.hold(fileAt: url, for: capture.id) }
        WatchCaptureTrail.note("phone.arrive", capture: capture.id,
                               "delivered by the system" + (url == nil ? "" : ", with its recording"))
        Task { @MainActor in
            send(await shared.receiveKeepingAwake(capture))
        }
    }

    /// iOS gives a background launch little time; ask for enough to write out the words and save.
    private func receiveKeepingAwake(_ capture: WatchCapture) async -> WatchCaptureDelivery.Answer {
        #if canImport(UIKit)
        let task = UIApplication.shared.beginBackgroundTask(withName: "Watch capture entry")
        defer { UIApplication.shared.endBackgroundTask(task) }
        #endif
        return await receive(capture)
    }

    nonisolated private static func unreadable(_ message: [String: Any]) -> WatchCaptureDelivery.Answer {
        let id = (message[WatchLinkMessage.captureID] as? String).flatMap(UUID.init(uuidString:))
        WatchCaptureTrail.fail("phone.read", capture: id, once: true,
                               "this capture could not be read (made by a newer Watch app?)")
        return WatchCaptureDelivery.Answer(id: id ?? UUID(), outcome: .failed,
                                           detail: "the iPhone app could not read the capture")
    }

    /// An answer that is not the reply to a live message: live when the Watch app is open, and
    /// left with the system for it either way.
    nonisolated private static func send(_ answer: WatchCaptureDelivery.Answer) {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        session.transferUserInfo(WatchCaptureDelivery.message(for: answer))
        if session.isReachable {
            session.sendMessage(WatchCaptureDelivery.message(for: answer), replyHandler: nil, errorHandler: nil)
        }
    }
}

/// Recordings, and words written out for them, that reached this iPhone before their capture
/// did. Used from the link's own thread and from the main thread.
final class WatchIncomingRecordings: @unchecked Sendable {
    static let shared = WatchIncomingRecordings(
        folder: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(WatchCaptureConfig.storageFolder, isDirectory: true)
            .appendingPathComponent("Incoming", isDirectory: true))

    /// A recording whose capture never came is removed after this long. The Watch still has it,
    /// and sends it again when the iPhone asks.
    static let keepFor: TimeInterval = 3 * 86_400

    let folder: URL
    private let lock = NSLock()
    private var words: [UUID: String] = [:]

    init(folder: URL) {
        self.folder = folder
    }

    /// Keeps a recording until its capture arrives. False when it could not be written.
    @discardableResult
    func hold(_ data: Data, for id: UUID, fileExtension: String) -> Bool {
        guard prepare(for: id) else { return false }
        return (try? data.write(to: url(for: id, fileExtension: fileExtension), options: [.atomic])) != nil
    }

    @discardableResult
    func hold(fileAt source: URL, for id: UUID) -> Bool {
        guard prepare(for: id) else { return false }
        return (try? FileManager.default.copyItem(at: source, to: url(for: id, fileExtension: source.pathExtension))) != nil
    }

    func recording(for id: UUID) -> URL? {
        let prefix = id.uuidString.lowercased() + "."
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return nil }
        return names.first { $0.hasPrefix(prefix) }.map { folder.appendingPathComponent($0) }
    }

    /// The words the live path wrote out, so the capture that follows does not write them out again.
    func remember(words: String, for id: UUID) {
        lock.withLock {
            if self.words.count >= 16 { self.words.removeAll() }
            self.words[id] = words
        }
    }

    func words(for id: UUID) -> String? {
        lock.withLock { words[id] }.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The capture has its entry: nothing of it needs holding any more.
    func forget(_ id: UUID) {
        if let url = recording(for: id) { try? FileManager.default.removeItem(at: url) }
        _ = lock.withLock { words.removeValue(forKey: id) }
    }

    func removeOld(now: Date = Date()) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        for name in names {
            let url = folder.appendingPathComponent(name)
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, now.timeIntervalSince(modified) > Self.keepFor { try? FileManager.default.removeItem(at: url) }
        }
    }

    private func url(for id: UUID, fileExtension: String) -> URL {
        folder.appendingPathComponent(id.uuidString.lowercased() + "." + (fileExtension.isEmpty ? "m4a" : fileExtension))
    }

    /// Makes the folder, kept out of device backups, and clears an earlier copy of this recording.
    private func prepare(for id: UUID) -> Bool {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var folder = folder
            try? folder.setResourceValues(values)
            if let earlier = recording(for: id) { try FileManager.default.removeItem(at: earlier) }
            return true
        } catch {
            return false
        }
    }
}
