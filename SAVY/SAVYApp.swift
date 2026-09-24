import SwiftUI

@main
struct SAVYApp: App {
    init() {
        SavyTypography.performAudit()
        do {
            try AmplifyAuthService.configureIfNeeded()
        } catch {
            assertionFailure("Amplify configuration failed: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AuthGateView()
                #if targetEnvironment(macCatalyst)
                .onAppear { SavyMacWindow.configure() }
                #endif
        }
    }
}
