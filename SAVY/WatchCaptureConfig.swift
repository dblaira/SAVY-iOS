import SwiftUI

// Watch capture kit: this app's settings. Written by watchkit.py from watch-capture.json.
// Change the JSON and run `watchkit.py files` again rather than editing this file.

enum WatchCaptureConfig {
    static let appName = "SAVY"
    static let containerIdentifier = "iCloud.com.adamblair.harness"
    static let inboxZoneName = "SAVYWatchInboxV1"
    static let recordType = "SAVYWatchCaptureV1"
    static let storageFolder = "SAVYWatch"
    /// Adam's own words, given to the speech recognizer as hints when it writes out a recording.
    static let vocabulary: [String] = ["Codex", "Claude", "Gemini", "SAVY", "Understood", "Harness", "Cowboy AI", "Generalization", "Xcode", "YouTube", "Dr Plants", "Blue's Clues"]
    /// Words the recognizer keeps mishearing, and what Adam meant. Whole words, any case.
    static let corrections: [String: String] = ["Kodak": "Codex"]
}

/// The doors on the wrist, in order. Raw values are what the iPhone and Mac receive.
enum WatchCaptureKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case action, reminder, event, post

    var id: String { rawValue }

    /// Save on the Watch, without picking a type, uses this one.
    static let saveDefault: WatchCaptureKind = .post

    /// The door's name on the wrist.
    var label: String {
        switch self {
        case .action: "Action"
        case .reminder: "Reminder"
        case .event: "Calendar"
        case .post: "Social"
        }
    }

    /// The door's SF Symbol.
    var symbol: String {
        switch self {
        case .action: "bolt"
        case .reminder: "bell"
        case .event: "calendar"
        case .post: "text.bubble"
        }
    }

    /// Reads a spoken day or hour into a proposed time.
    var readsTimeCue: Bool {
        switch self {
        case .action: false
        case .reminder: true
        case .event: true
        case .post: false
        }
    }

    /// A day heard with no hour: all-day when true, 9:00 when false.
    var dayOnlyIsAllDay: Bool {
        switch self {
        case .action: false
        case .reminder: false
        case .event: true
        case .post: false
        }
    }

    /// Debug-only demo screens show these words.
    var demoWords: String {
        switch self {
        case .action: "Email the gym about Saturday's group lesson"
        case .reminder: "Renew the passport tomorrow at 9 AM"
        case .event: "Lunch with Sam Friday at noon"
        case .post: "Blue's Clues pauses so the kid can answer. That is the group lesson."
        }
    }
}

enum WatchTheme {
    static let background = Color(red: 0xD8 / 255, green: 0xC2 / 255, blue: 0xA0 / 255)
    static let accent = Color(red: 0x7A / 255, green: 0x14 / 255, blue: 0x28 / 255)
    /// The accent on a dark watch face, for the complication.
    static let accentOnDark = Color(red: 0xE6 / 255, green: 0x0E / 255, blue: 0x44 / 255)
    static let door = Color(red: 0xF3 / 255, green: 0xEA / 255, blue: 0xD5 / 255)
    static let doorText = Color(red: 0x08 / 255, green: 0x17 / 255, blue: 0x2D / 255)
    static let text = Color(red: 0x08 / 255, green: 0x17 / 255, blue: 0x2D / 255)
    /// The clock and the written words.
    static let strongText = Color(red: 0x08 / 255, green: 0x17 / 255, blue: 0x2D / 255)
    /// The border around the record and stop buttons.
    static let ring = Color(red: 0x08 / 255, green: 0x17 / 255, blue: 0x2D / 255)
    /// The darker color the background fades into at the screen's edges, with paper grain.
    /// `nil` leaves the background flat.
    static let edge: Color? = Color(red: 0x6B / 255, green: 0x4E / 255, blue: 0x2E / 255)
    /// The app's name as the app icon draws it: one inner list per pen stroke, in the icon's
    /// own grid. Empty shows the name as plain text.
    static let titleStrokes: [[CGPoint]] = [
        [CGPoint(x: 300, y: 408), CGPoint(x: 201, y: 243), CGPoint(x: 118, y: 528), CGPoint(x: 303, y: 476), CGPoint(x: 170, y: 746), CGPoint(x: 85, y: 598)],
        [CGPoint(x: 303, y: 688), CGPoint(x: 415, y: 358), CGPoint(x: 517, y: 688)],
        [CGPoint(x: 497, y: 365), CGPoint(x: 600, y: 690), CGPoint(x: 718, y: 342)],
        [CGPoint(x: 923, y: 320), CGPoint(x: 785, y: 778), CGPoint(x: 716, y: 597), CGPoint(x: 793, y: 593)],
        [CGPoint(x: 740, y: 447), CGPoint(x: 855, y: 542)],
    ]
    /// True when `titleStrokes` are the outlines of a typeset name, to be filled in the text
    /// color, not pen strokes to be drawn.
    static let titleFilled = false
}
