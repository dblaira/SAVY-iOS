import Foundation

/// Card positions sync separately from authored entries.
/// Physical-device UI checks use their own defaults domain and reset it once per launch.
@MainActor
enum SavyCardPreferences {
    /// Posted after document sync writes arrangements from another device into `defaults`.
    static let didApplySync = Notification.Name("SavyCardPreferencesDidApplySync")

    static let defaults: UserDefaults = {
        guard !SavyRuntime.isTesting else {
            let suite = "com.adamblair.savy.ui-test.card-preferences"
            let defaults = UserDefaults(suiteName: suite)!
            if ProcessInfo.processInfo.arguments.contains("SAVY_UI_TEST_RESET_REMINDERS") {
                defaults.removePersistentDomain(forName: suite)
            }
            return defaults
        }
        return .standard
    }()
}
