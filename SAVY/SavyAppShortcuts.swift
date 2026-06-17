import AppIntents

struct CaptureLeverageSignalIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture Leverage Signal"
    static let description = IntentDescription("Open SAVY to capture a native leverage signal.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct SavyAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureLeverageSignalIntent(),
            phrases: [
                "Capture in \(.applicationName)",
                "Save leverage in \(.applicationName)"
            ],
            shortTitle: "Capture",
            systemImageName: "bolt.fill"
        )
    }
}
