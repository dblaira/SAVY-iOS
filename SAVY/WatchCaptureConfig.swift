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
    static let background = Color(red: 0x08 / 255, green: 0x17 / 255, blue: 0x2D / 255)
    static let accent = Color(red: 0xE6 / 255, green: 0x0E / 255, blue: 0x44 / 255)
    static let door = Color(red: 0xF3 / 255, green: 0xEA / 255, blue: 0xD5 / 255)
    static let doorText = Color(red: 0x08 / 255, green: 0x17 / 255, blue: 0x2D / 255)
    static let text = Color(red: 0xF3 / 255, green: 0xEA / 255, blue: 0xD5 / 255)
}
