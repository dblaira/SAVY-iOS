import Foundation

// Watch capture kit, iPhone route: the same in every app that uses it. Shared by the Watch app
// and the iPhone app. For an app that makes no iCloud calls ("route": "iphone" in
// watch-capture.json).
//
// The Watch hands each saved capture to the iPhone over the link between them, and the iPhone
// makes the entry. The Watch keeps the capture in its queue until the iPhone says the entry is
// saved. A capture made with the iPhone out of reach waits on the Watch until the iPhone is close.
// One capture makes one entry, however many times it is sent: the entry's id is the capture's id.

/// A capture as it travels from the Watch to the iPhone, and the iPhone's answer.
enum WatchCaptureDelivery {
    static let formatVersion = 1

    enum CodecError: Error { case invalid }

    private struct Payload: Codable {
        var formatVersion: Int
        var capture: WatchCapture
    }

    /// The capture's id, type, time, words, and the name and length of its recording. The
    /// recording itself travels beside it. Times travel exactly, to the fraction of a second,
    /// so the iPhone gets the capture the Watch has.
    static func payload(for capture: WatchCapture) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Payload(formatVersion: formatVersion, capture: capture))
    }

    /// Throws for a payload from a newer app, and for a capture with neither words nor a recording.
    static func capture(from payload: Data) throws -> WatchCapture {
        let decoded = try JSONDecoder().decode(Payload.self, from: payload)
        guard decoded.formatVersion == formatVersion,
              !decoded.capture.words.isEmpty || decoded.capture.hasRecording else { throw CodecError.invalid }
        return decoded.capture
    }

    /// What the iPhone says back.
    enum Outcome: String, Sendable {
        /// The entry is saved on the iPhone: now, or by an earlier arrival of this same capture.
        case saved
        /// The iPhone does not have the recording. Send it, then send the capture again.
        case needsRecording
        /// The iPhone could not save the entry. The Watch keeps the capture and sends it again.
        case failed
    }

    struct Answer: Equatable, Sendable {
        var id: UUID
        var outcome: Outcome
        /// A short reason for the trail. Never the words.
        var detail: String?
    }

    /// The message that carries a capture, live or left with the system.
    static func message(for capture: WatchCapture) throws -> [String: Any] {
        [
            WatchLinkMessage.type: WatchLinkMessage.capture,
            WatchLinkMessage.captureID: capture.id.uuidString,
            WatchLinkMessage.payload: try payload(for: capture),
        ]
    }

    /// The capture in a message. Nil when the message is not a capture, or cannot be read.
    static func capture(in message: [String: Any]) -> WatchCapture? {
        guard message[WatchLinkMessage.type] as? String == WatchLinkMessage.capture,
              let payload = message[WatchLinkMessage.payload] as? Data,
              let capture = try? capture(from: payload),
              message[WatchLinkMessage.captureID] as? String == capture.id.uuidString else { return nil }
        return capture
    }

    static func message(for answer: Answer) -> [String: Any] {
        var message: [String: Any] = [
            WatchLinkMessage.type: WatchLinkMessage.captureAnswer,
            WatchLinkMessage.captureID: answer.id.uuidString,
            WatchLinkMessage.outcome: answer.outcome.rawValue,
        ]
        if let detail = answer.detail { message[WatchLinkMessage.detail] = detail }
        return message
    }

    /// The iPhone's answer in a message. Nil when the message is not one.
    static func answer(in message: [String: Any]) -> Answer? {
        guard message[WatchLinkMessage.type] as? String == WatchLinkMessage.captureAnswer,
              let id = (message[WatchLinkMessage.captureID] as? String).flatMap(UUID.init(uuidString:)),
              let outcome = (message[WatchLinkMessage.outcome] as? String).flatMap(Outcome.init(rawValue:))
        else { return nil }
        return Answer(id: id, outcome: outcome, detail: message[WatchLinkMessage.detail] as? String)
    }
}

extension WatchLinkMessage {
    /// A saved capture on its way to the iPhone.
    static let capture = "capture"
    static let payload = "payload"
    /// The iPhone saying whether the capture's entry is saved.
    static let captureAnswer = "captureAnswer"
    static let outcome = "outcome"
    static let detail = "detail"
}

/// One capture in the Watch's queue.
struct WatchQueuedCapture: Codable, Equatable, Identifiable, Sendable {
    var capture: WatchCapture
    /// When the iPhone said the entry is saved. Nil while the capture waits on the Watch.
    var sentAt: Date?
    /// True from the moment a recording stops until Save, or until it is saved for you.
    var isDraft: Bool = false
    var id: UUID { capture.id }
}

/// The rules of the Watch's queue, as values, so they can be tested without a Watch.
enum WatchCaptureQueue {
    /// What still has to reach the iPhone, oldest first. A draft waits for Save; a capture the
    /// iPhone has confirmed is done.
    static func waiting(in items: [WatchQueuedCapture]) -> [WatchQueuedCapture] {
        items.filter { $0.sentAt == nil && !$0.isDraft }
            .sorted { $0.capture.capturedAt < $1.capture.capturedAt }
    }

    /// The iPhone said this capture's entry is saved. False, with nothing changed, when the
    /// capture is not in the queue, is still a draft, or was confirmed before.
    @discardableResult
    static func confirm(_ id: UUID, in items: inout [WatchQueuedCapture], at date: Date = Date()) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }),
              !items[index].isDraft, items[index].sentAt == nil else { return false }
        items[index].sentAt = date
        return true
    }
}
