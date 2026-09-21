import Foundation

/// Card positions are local presentation preferences, separate from authored entries.
/// Physical-device UI checks use their own defaults domain and reset it once per launch.
@MainActor
enum SavyCardPreferences {
    static let defaults: UserDefaults = {
        guard ProcessInfo.processInfo.arguments.contains("SAVY_UI_TEST_UNLOCKED") else {
            return .standard
        }
        let suite = "com.adamblair.savy.ui-test.card-preferences"
        let defaults = UserDefaults(suiteName: suite)!
        if ProcessInfo.processInfo.arguments.contains("SAVY_UI_TEST_RESET_REMINDERS") {
            defaults.removePersistentDomain(forName: suite)
        }
        return defaults
    }()
}
