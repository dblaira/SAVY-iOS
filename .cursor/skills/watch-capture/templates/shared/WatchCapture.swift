import CloudKit
import Foundation
import os
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

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
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        // The detector counts “tomorrow” and “Friday” from the moment it runs. Words written
        // out a day or more after they were said are counted from the day they were said.
        let saidDay = calendar.startOfDay(for: now)
        let writtenDay = calendar.startOfDay(for: Date())
        let daysLate = calendar.dateComponents([.day], from: saidDay, to: writtenDay).day ?? 0
        if daysLate > 0 {
            let lower = heard.lowercased()
            if namesWeekday(lower) {
                // A matching weekday between the saying and the writing out was skipped; use it.
                while let earlier = calendar.date(byAdding: .day, value: -7, to: start),
                      calendar.startOfDay(for: earlier) > saidDay, calendar.startOfDay(for: earlier) <= writtenDay {
                    start = earlier
                }
            } else if !namesCalendarDate(lower) {
                start = calendar.date(byAdding: .day, value: -daysLate, to: start) ?? start
            }
        }
        // “at 3 PM” said at 5 PM means tomorrow, unless today was said out loud.
        if !dayOnly, start < now, now.timeIntervalSince(start) < 86_400,
           !heard.lowercased().contains("today") {
            start = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        }
        let duration = match.duration > 0 ? match.duration : nil
        return WatchTimeCue(start: start, duration: duration, isDayOnly: dayOnly, heard: heard)
    }

    /// A day of the week was spoken: “Friday”, “next Tuesday”.
    static func namesWeekday(_ lower: String) -> Bool {
        lower.range(of: #"\b(mon|tues|wednes|thurs|fri|satur|sun)day\b"#, options: .regularExpression) != nil
    }

    /// A fixed date was spoken: “December 3”, “the 3rd”, “12/3”. It means the same day whenever it is read.
    static func namesCalendarDate(_ lower: String) -> Bool {
        let patterns = [
            #"\b(january|february|march|april|may|june|july|august|september|october|november|december)\b"#,
            #"\b(jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)\b"#,
            #"\d{1,2}/\d{1,2}"#,
            #"\b\d{1,2}(st|nd|rd|th)\b"#,
        ]
        return patterns.contains { lower.range(of: $0, options: .regularExpression) != nil }
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
        /// The big button on the Watch: a recording.
        case wrist
        /// Siri, the Action Button, or the Shortcuts app: words Siri heard.
        case shortcut
    }

    var id: UUID
    var kind: WatchCaptureKind
    /// The words exactly as heard, without leading or trailing spaces. Empty for a recording
    /// until the iPhone or Mac writes it out.
    var words: String
    var capturedAt: Date
    var timeZoneIdentifier: String
    var cue: WatchTimeCue?
    var source: Source
    /// The recording's file name on the device that holds it. Nil for a capture made of words.
    var audioFileName: String?
    var audioDuration: TimeInterval?

    init(kind: WatchCaptureKind, words: String, source: Source,
         capturedAt: Date = Date(), timeZone: TimeZone = .current, id: UUID = UUID(),
         audioFileName: String? = nil, audioDuration: TimeInterval? = nil) {
        self.id = id
        self.kind = kind
        self.words = words.trimmingCharacters(in: .whitespacesAndNewlines)
        self.capturedAt = capturedAt
        self.timeZoneIdentifier = timeZone.identifier
        self.source = source
        self.audioFileName = audioFileName
        self.audioDuration = audioDuration
        self.cue = kind.readsTimeCue
            ? WatchTimeCueReader.cue(in: self.words, heardAt: capturedAt, timeZone: timeZone)
            : nil
    }

    var hasRecording: Bool { audioFileName != nil }

    /// Words written later, or re-recorded, keep the same capture and its recording, so the
    /// iPhone receives one entry, not two. A spoken day or hour is read again from the new words.
    func replacingWords(_ newWords: String) -> WatchCapture {
        let zone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return WatchCapture(kind: kind, words: newWords, source: source, capturedAt: capturedAt,
                            timeZone: zone, id: id, audioFileName: audioFileName, audioDuration: audioDuration)
    }

    /// The type chosen after recording.
    func withKind(_ newKind: WatchCaptureKind) -> WatchCapture {
        let zone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return WatchCapture(kind: newKind, words: words, source: source, capturedAt: capturedAt,
                            timeZone: zone, id: id, audioFileName: audioFileName, audioDuration: audioDuration)
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

    /// The recording travels as a CloudKit asset named "audio" beside the encrypted payload.
    static let audioKey = "audio"
    /// Set by the first iPhone or Mac that turns the capture into an entry.
    static let importedAtKey = "importedAt"
    /// Which device set it, so that device can finish an import it was stopped in the middle of.
    static let importedByKey = "importedBy"

    static func record(for capture: WatchCapture, audioURL: URL? = nil) throws -> CKRecord {
        let record = CKRecord(recordType: recordType, recordID: recordID(for: capture.id))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Payload(formatVersion: formatVersion, capture: capture))
        record["schemaVersion"] = NSNumber(value: formatVersion)
        record.encryptedValues["payload"] = data as NSData
        if let audioURL { record[audioKey] = CKAsset(fileURL: audioURL) }
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
              !payload.capture.words.isEmpty || payload.capture.hasRecording else { throw CodecError.invalidRecord }
        return payload.capture
    }

    /// The downloaded recording of a fetched record, if it has one.
    static func audioURL(in record: CKRecord) -> URL? {
        (record[audioKey] as? CKAsset)?.fileURL
    }
}

/// The live messages between the Watch and the nearby iPhone: the recording in parts one way,
/// the written-out words the other. Kept here so both sides agree.
enum WatchLinkMessage {
    static let type = "type"
    static let recordingPart = "recordingPart"
    static let words = "words"
    static let captureID = "captureID"
    static let index = "index"
    static let count = "count"
    static let fileExtension = "ext"
    static let data = "data"
}

// MARK: - Trail

/// What happened to each capture, step by step, on this device. A capture that stops on its way
/// from the wrist to an entry says where it stopped and why, so it can be fixed instead of guessed.
///
/// Each line holds a time, the step, whether it worked, the capture's id and a short reason: a
/// state, a count, or an error's code. It never holds the words, the recording or an account
/// name. The Watch and the iPhone or Mac each keep their own file; `watchkit.py trail` reads
/// them together. The same lines go to the system log under the category "WatchCaptureTrail".
enum WatchCaptureTrail {
    struct Event: Codable, Equatable, Sendable {
        var at: Date
        /// "watch", "iphone" or "mac".
        var side: String
        var step: String
        var ok: Bool
        var capture: String?
        var detail: String?
    }

    #if os(watchOS)
    static let side = "watch"
    #elseif targetEnvironment(macCatalyst)
    static let side = "mac"
    #else
    static let side = "iphone"
    #endif

    static let file = WatchCaptureTrailFile(
        folder: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(WatchCaptureConfig.storageFolder, isDirectory: true))

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "WatchCapture", category: "WatchCaptureTrail")

    /// Records one step. `once` skips a line that repeats the last one for the same step and
    /// capture, so a retry every minute does not fill the file.
    static func note(_ step: String, capture: UUID? = nil, ok: Bool = true, once: Bool = false, _ detail: String? = nil) {
        let event = Event(at: Date(), side: side, step: step, ok: ok,
                          capture: capture?.uuidString.lowercased(), detail: detail)
        guard file.append(event, once: once) else { return }
        log.log("\(step, privacy: .public) \(ok ? "ok" : "FAILED", privacy: .public) \(event.capture ?? "-", privacy: .public) \(detail ?? "", privacy: .public)")
    }

    static func fail(_ step: String, capture: UUID? = nil, once: Bool = false, _ detail: String?) {
        note(step, capture: capture, ok: false, once: once, detail)
    }

    /// This app's version and build, for the line written at launch.
    static var build: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "v\(version) (\(build))"
    }

    /// An error as its framework, code and name. No description, which could hold a name or a path.
    static func reason(_ error: any Error) -> String {
        if let error = error as? CKError {
            var text = "CloudKit \(error.code.rawValue) \(name(error.code))"
            if error.code == .partialFailure, let first = error.partialErrorsByItemID?.values.first {
                text += " (first: \(reason(first)))"
            }
            return text
        }
        #if canImport(WatchConnectivity)
        if let error = error as? WCError {
            return "WatchConnectivity \(error.code.rawValue) \(name(error.code))"
        }
        #endif
        let error = error as NSError
        return "\(error.domain) \(error.code)"
    }

    private static func name(_ code: CKError.Code) -> String {
        switch code {
        case .internalError: return "internalError"
        case .partialFailure: return "partialFailure"
        case .networkUnavailable: return "networkUnavailable"
        case .networkFailure: return "networkFailure"
        case .badContainer: return "badContainer"
        case .serviceUnavailable: return "serviceUnavailable"
        case .requestRateLimited: return "requestRateLimited"
        case .missingEntitlement: return "missingEntitlement"
        case .notAuthenticated: return "notAuthenticated"
        case .permissionFailure: return "permissionFailure"
        case .unknownItem: return "unknownItem"
        case .invalidArguments: return "invalidArguments"
        case .serverRecordChanged: return "serverRecordChanged"
        case .serverRejectedRequest: return "serverRejectedRequest"
        case .assetFileNotFound: return "assetFileNotFound"
        case .incompatibleVersion: return "incompatibleVersion"
        case .operationCancelled: return "operationCancelled"
        case .changeTokenExpired: return "changeTokenExpired"
        case .batchRequestFailed: return "batchRequestFailed"
        case .zoneBusy: return "zoneBusy"
        case .quotaExceeded: return "quotaExceeded"
        case .zoneNotFound: return "zoneNotFound"
        case .limitExceeded: return "limitExceeded"
        case .userDeletedZone: return "userDeletedZone"
        case .serverResponseLost: return "serverResponseLost"
        case .accountTemporarilyUnavailable: return "accountTemporarilyUnavailable"
        default: return "other"
        }
    }

    #if canImport(WatchConnectivity)
    private static func name(_ code: WCError.Code) -> String {
        switch code {
        case .genericError: return "genericError"
        case .sessionMissingDelegate: return "sessionMissingDelegate"
        case .sessionNotActivated: return "sessionNotActivated"
        case .deviceNotPaired: return "deviceNotPaired"
        case .watchAppNotInstalled: return "watchAppNotInstalled"
        case .notReachable: return "notReachable"
        case .payloadTooLarge: return "payloadTooLarge"
        case .payloadUnsupportedTypes: return "payloadUnsupportedTypes"
        case .messageReplyFailed: return "messageReplyFailed"
        case .messageReplyTimedOut: return "messageReplyTimedOut"
        case .deliveryFailed: return "deliveryFailed"
        case .insufficientSpace: return "insufficientSpace"
        case .sessionInactive: return "sessionInactive"
        case .transferTimedOut: return "transferTimedOut"
        case .companionAppNotInstalled: return "companionAppNotInstalled"
        default: return "other"
        }
    }
    #endif
}

/// The trail's file: one JSON line per step, newest last, kept to the last few hundred lines.
final class WatchCaptureTrailFile: @unchecked Sendable {
    static let fileName = "trail.jsonl"
    /// The file is cut back to `keptLines` once it passes `lineLimit`.
    static let lineLimit = 600
    static let keptLines = 400

    let fileURL: URL
    private let lock = NSLock()
    private var lineCount: Int?
    private var lastOnce: [String: String] = [:]

    init(folder: URL) {
        fileURL = folder.appendingPathComponent(Self.fileName)
    }

    /// Adds one line. Returns false when `once` found it repeats the last line for its step and capture.
    @discardableResult
    func append(_ event: WatchCaptureTrail.Event, once: Bool = false) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard var line = try? encoder.encode(event) else { return false }
        line.append(0x0A)
        return lock.withLock { () -> Bool in
            let key = event.step + "|" + (event.capture ?? "")
            let value = (event.ok ? "ok|" : "failed|") + (event.detail ?? "")
            if once, lastOnce[key] == value { return false }
            lastOnce[key] = value
            let manager = FileManager.default
            try? manager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if lineCount == nil { lineCount = Self.lines(in: fileURL).count }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: line)
            } else {
                try? line.write(to: fileURL, options: [.atomic])
            }
            lineCount = (lineCount ?? 0) + 1
            if (lineCount ?? 0) > Self.lineLimit {
                let kept = Self.lines(in: fileURL).suffix(Self.keptLines)
                var data = Data()
                for line in kept {
                    data.append(line)
                    data.append(0x0A)
                }
                try? data.write(to: fileURL, options: [.atomic])
                lineCount = kept.count
            }
            return true
        }
    }

    /// Every step still in the file, oldest first.
    func events() -> [WatchCaptureTrail.Event] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return lock.withLock { Self.lines(in: fileURL) }.compactMap { try? decoder.decode(WatchCaptureTrail.Event.self, from: $0) }
    }

    private static func lines(in url: URL) -> [Data] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return data.split(separator: 0x0A).map { Data($0) }
    }
}
