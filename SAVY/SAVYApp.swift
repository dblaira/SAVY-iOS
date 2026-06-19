import SwiftUI

@main
struct SAVYApp: App {
    init() {
        do {
            try AmplifyAuthService.configureIfNeeded()
        } catch {
            assertionFailure("Amplify configuration failed: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AuthGateView()
        }
    }
}
