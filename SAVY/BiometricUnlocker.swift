import Foundation
import LocalAuthentication

struct BiometricUnlocker {
    #if targetEnvironment(macCatalyst)
    /// A Mac without Touch ID unlocks with the Mac login password instead.
    static let policy: LAPolicy = .deviceOwnerAuthentication
    static let reason = "Unlock SAVY."
    #else
    static let policy: LAPolicy = .deviceOwnerAuthenticationWithBiometrics
    static let reason = "Unlock SAVY with Face ID."
    #endif

    func canUnlockWithBiometrics() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(Self.policy, error: &error)
    }

    func unlock() async throws {
        let context = LAContext()
        context.localizedCancelTitle = "Use Password"

        try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(
                Self.policy,
                localizedReason: Self.reason
            ) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? LAError(.authenticationFailed))
                }
            }
        }
    }
}
