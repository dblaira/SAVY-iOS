import SwiftUI

@main
struct SAVYApp: App {
    init() {
        SavyTypography.auditBundledFonts()
        do {
            try AmplifyAuthService.configureIfNeeded()
        } catch {
            assertionFailure("Amplify configuration failed: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-PreviewConnection") {
                RootView(
                    session: AuthSession(
                        accessToken: "preview",
                        refreshToken: "preview",
                        tokenType: "bearer",
                        expiresIn: 3600,
                        user: AuthUser(id: "preview-user", email: "adam@example.com")
                    ),
                    initialSection: .beliefs
                )
            } else {
                AuthGateView()
            }
            #else
            AuthGateView()
            #endif
        }
    }
}
