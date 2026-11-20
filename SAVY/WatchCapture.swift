import CloudKit
import Foundation

// Watch capture kit: the same in every app that uses it. App-specific values live in
// WatchCaptureConfig.swift. Shared by the Watch app and the iPhone/Mac app. The Watch writes
// captures into their own iCloud zone; the iPhone or Mac turns each one into a normal entry.
// The Watch never writes into the app's main sync zone, so a capture cannot disturb it.

/// A day or hour heard in the words, such as “tomorrow at 3 PM”.
struct WatchTimeCue: Codable, Equatable, Sendable {
    var start: Date
    var duration: TimeInterval?
    /// True when only a day was heard, with no clock time.
    var isDayOnly: Bool
    /// The exact words the date came from, for the confirmation screen.
    var heard: String
}

/// The schedule a capture proposes. The Watch shows it and the iPhone saves it, so both
/// read it from this one place.
struct WatchProposedWindow: Equatable, Sendable {
    var start: Date
    var end: Date
    var isAllDay: Bool
}

enum WatchTimeCueReader {
    static func cue(in words: String, heardAt now: Date, timeZone: TimeZone) -> WatchTimeCue? {
        guard !words.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let range = NSRange(words.startIndex..<words.endIndex, in: words)
        guard let match = detector.firstMatch(in: words, options: [], range: range),
              var start = match.date else { return nil }
        let heard = Range(match.range, in: words).map { String(words[$0]) } ?? ""
        let dayOnly = !namesClockTime(heard)
        // “at 3 PM” said at 5 PM means tomorrow, unless today was said out loud.
        if !dayOnly, start < now, now.timeIntervalSince(start) < 86_400,
           !heard.lowercased().contains("today") {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            start = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        }
        let duration = match.duration > 0 ? match.duration : nil
        return WatchTimeCue(start: start, duration: duration, isDayOnly: dayOnly, heard: heard)
    }

    /// A clock time was spoken: “3 PM”, “3:30”, “at 9”, “noon”, “tonight”.
    static func namesClockTime(_ heard: String) -> Bool {
        let lower = heard.lowercased()
        let words = ["noon", "midnight", "morning", "afternoon", "evening", "tonight", "o'clock", "o’clock"]
        if words.contains(where: { lower.contains($0) }) { return true }
        let patterns = [
            #"\d{1,2}:\d{2}"#,
            #"\d\s*(a\.?m\.?|p\.?m\.?)(\W|$)"#,
            #"\bat\s+\d"#,
        ]
        return patterns.contains { lower.range(of: $0, options: .regularExpression) != nil }
    }
}

struct WatchCapture: Codable, Equatable, Identifiable, Sendable {
    enum Source: String, Codable, Sendable {
        /// A tile on the Watch screen.
        case wrist
        /// Siri, the Action Button, or the Shortcuts app.
        case shortcut
    }

    var id: UUID
    var kind: WatchCaptureKind
    /// The words exactly as dictated, without leading or trailing spaces.
    var words: String
    var capturedAt: Date
    var timeZoneIdentifier: String
    var cue: WatchTimeCue?
    var source: Source

    init(kind: WatchCaptureKind, words: String, source: Source,
         capturedAt: Date = Date(), timeZone: TimeZone = .current, id: UUID = UUID()) {
        self.id = id
        self.kind = kind
        self.words = words.trimmingCharacters(in: .whitespacesAndNewlines)
        self.capturedAt = capturedAt
        self.timeZoneIdentifier = timeZone.identifier
        self.source = source
        self.cue = kind.readsTimeCue
            ? WatchTimeCueReader.cue(in: self.words, heardAt: capturedAt, timeZone: timeZone)
            : nil
    }

    /// Re-recording keeps the same capture, so the iPhone receives one entry, not two.
    func replacingWords(_ newWords: String) -> WatchCapture {
        let zone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return WatchCapture(kind: kind, words: newWords, source: source,
                            capturedAt: capturedAt, timeZone: zone, id: id)
    }

    /// A day with no hour is all-day for kinds that say so, and starts at 9:00 otherwise.
    var proposedWindow: WatchProposedWindow? {
        guard let cue else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        if cue.isDayOnly {
            let day = calendar.startOfDay(for: cue.start)
            if kind.dayOnlyIsAllDay {
                let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
                return WatchProposedWindow(start: day, end: end, isAllDay: true)
            }
            let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
            return WatchProposedWindow(start: start, end: start.addingTimeInterval(3_600), isAllDay: false)
        }
        let length = cue.duration.flatMap { $0 > 0 ? $0 : nil } ?? 3_600
        return WatchProposedWindow(start: cue.start, end: cue.start.addingTimeInterval(length), isAllDay: false)
    }
}

/// The Watch's own iCloud zone in the app's existing container. Payloads use CloudKit's
/// encrypted fields.
enum WatchCaptureInbox {
    static let containerIdentifier = WatchCaptureConfig.containerIdentifier
    static let zoneName = WatchCaptureConfig.inboxZoneName
    static let recordType = WatchCaptureConfig.recordType
    static let formatVersion = 1
    static let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)

    enum CodecError: Error { case invalidRecord }

    private struct Payload: Codable {
        var formatVersion: Int
        var capture: WatchCapture
    }

    static func recordID(for id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: "capture-\(id.uuidString.lowercased())", zoneID: zoneID)
    }

    static func record(for capture: WatchCapture) throws -> CKRecord {
        let record = CKRecord(recordType: recordType, recordID: recordID(for: capture.id))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Payload(formatVersion: formatVersion, capture: capture))
        record["schemaVersion"] = NSNumber(value: formatVersion)
        record.encryptedValues["payload"] = data as NSData
        return record
    }

    static func capture(from record: CKRecord) throws -> WatchCapture {
        guard record.recordID.zoneID == zoneID, record.recordType == recordType,
              (record["schemaVersion"] as? NSNumber)?.intValue == formatVersion,
              let data = record.encryptedValues["payload"] as? Data else { throw CodecError.invalidRecord }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(Payload.self, from: data)
        guard payload.formatVersion == formatVersion,
              recordID(for: payload.capture.id) == record.recordID,
              !payload.capture.words.isEmpty else { throw CodecError.invalidRecord }
        return payload.capture
    }
}
