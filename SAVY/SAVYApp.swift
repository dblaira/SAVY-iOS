import SwiftUI

@main
struct SAVYApp: App {
    init() {
        SavyTypography.performAudit()
        NotificationScheduler.configurePresentation()
        #if !targetEnvironment(macCatalyst)
        do {
            try AmplifyAuthService.configureIfNeeded()
        } catch {
            assertionFailure("Amplify configuration failed: \(error)")
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            #if targetEnvironment(macCatalyst)
            RootView()
                .onAppear { SavyMacWindow.configure() }
            #else
            AuthGateView()
            #endif
        }
    }
}
