import AppIntents

// Watch capture kit: this app's Siri phrases and Action Button shortcuts. Written by
// watchkit.py from watch-capture.json. App Shortcut phrases must be literals, so this
// file is generated per app instead of reading WatchCaptureConfig.

enum ShortcutCapture {
    @MainActor
    static func save(_ kind: WatchCaptureKind, words: String) -> String {
        let store = WatchCaptureStore.shared
        guard let capture = store.capture(kind, words: words, source: .shortcut) else {
            return "Nothing was saved. Try again."
        }
        // A shortcut can end before the send finishes; watchOS wakes the app later to retry.
        store.scheduleRetry()
        if let window = capture.proposedWindow {
            return "Saved to \(kind.label) for \(CaptureProofContent.describe(window, timeZoneIdentifier: capture.timeZoneIdentifier)): \(capture.words)"
        }
        return "Saved to \(kind.label): \(capture.words)"
    }
}

struct LogActionIntent: AppIntent {
    static let title: LocalizedStringResource = "Log an Action"

    @Parameter(title: "Action", requestValueDialog: "What's the action?")
    var words: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: ShortcutCapture.save(.action, words: words)))
    }
}

struct AddReminderIntent: AppIntent {
    static let title: LocalizedStringResource = "Add a Reminder"

    @Parameter(title: "Reminder", requestValueDialog: "What's the reminder?")
    var words: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: ShortcutCapture.save(.reminder, words: words)))
    }
}

struct CreateCalendarEventIntent: AppIntent {
    static let title: LocalizedStringResource = "Create a Calendar Event"

    @Parameter(title: "Event", requestValueDialog: "What's the event?")
    var words: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: ShortcutCapture.save(.event, words: words)))
    }
}

struct StageSocialPostIntent: AppIntent {
    static let title: LocalizedStringResource = "Stage a Social Post"

    @Parameter(title: "Post", requestValueDialog: "What shining example caught your attention?")
    var words: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: ShortcutCapture.save(.post, words: words)))
    }
}

/// For the Action Button: one press opens the app already recording.
struct OpenCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture in SAVY"
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        WatchCaptureLaunch.shared.requestRecording()
        return .result()
    }
}

struct WatchCaptureShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogActionIntent(),
            phrases: ["Log an action in \(.applicationName)"],
            shortTitle: "Log an Action",
            systemImageName: "bolt"
        )
        AppShortcut(
            intent: AddReminderIntent(),
            phrases: ["Add a reminder in \(.applicationName)"],
            shortTitle: "Add a Reminder",
            systemImageName: "bell"
        )
        AppShortcut(
            intent: CreateCalendarEventIntent(),
            phrases: ["Create a calendar event in \(.applicationName)"],
            shortTitle: "Create a Calendar Event",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: StageSocialPostIntent(),
            phrases: ["Stage a social post in \(.applicationName)"],
            shortTitle: "Stage a Social Post",
            systemImageName: "text.bubble"
        )
        AppShortcut(
            intent: OpenCaptureIntent(),
            phrases: ["Capture in \(.applicationName)"],
            shortTitle: "Capture",
            systemImageName: "mic"
        )
    }
}
