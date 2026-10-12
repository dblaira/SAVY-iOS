import SwiftUI

@main
struct SAVYApp: App {
    init() {
        SavyTypography.performAudit()
        NotificationScheduler.configurePresentation()
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                initialSection: ProcessInfo.processInfo.arguments.contains("SAVY_UI_TEST_OPEN_REMINDERS")
                    ? .reminders
                    : .now
            )
                #if targetEnvironment(macCatalyst)
                .onAppear { SavyMacWindow.configure() }
                #endif
        }
    }
}
