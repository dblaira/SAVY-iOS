import SwiftUI
import UIKit

enum SavyRuntime {
    static var isTesting: Bool {
        ProcessInfo.processInfo.arguments.contains("SAVY_UI_TEST_UNLOCKED")
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
            || NSClassFromString("XCTest.XCTestCase") != nil
    }
}

final class SavyAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if !SavyRuntime.isTesting { application.registerForRemoteNotifications() }
        return true
    }
}

@main
struct SAVYApp: App {
    @UIApplicationDelegateAdaptor(SavyAppDelegate.self) private var appDelegate
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
