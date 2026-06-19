import Foundation

@MainActor
final class AuthenticationStore: ObservableObject {
    @Published private(set) var state: AuthenticationState = .checking
    @Published private(set) var isWorking = false
    @Published var message: String?
    @Published var diagnostic: AWSGraphDiagnostic?

    private let client: AWSGraphClient?
    private let biometricUnlocker: BiometricUnlocker

    var hasBackendConfiguration: Bool {
        client != nil
    }

    var canUseFaceID: Bool {
        biometricUnlocker.canUnlockWithBiometrics()
    }

    init(
        client: AWSGraphClient? = AWSGraphClient.fromBundleConfiguration(),
        biometricUnlocker: BiometricUnlocker = BiometricUnlocker()
    ) {
        self.client = client
        self.biometricUnlocker = biometricUnlocker
    }

    func bootstrap() {
        guard case .checking = state else { return }

        Task {
            do {
                if let session = try await AmplifyAuthService.bootstrapSession() {
                    try? KeychainSessionStore.save(session)
                    state = .locked(session)
                } else if let legacySession = KeychainSessionStore.load() {
                    KeychainSessionStore.clear()
                    state = .signedOut
                    message = legacySession.user.email == nil
                        ? nil
                        : "Sign in again to refresh your session."
                } else {
                    state = .signedOut
                }
            } catch {
                KeychainSessionStore.clear()
                state = .signedOut
            }
        }
    }

    func enter(email: String, password: String) async {
        await authenticate(email: email, password: password, action: AmplifyAuthService.enter)
    }

    func signIn(email: String, password: String) async {
        await authenticate(email: email, password: password, action: AmplifyAuthService.signIn)
    }

    func signUp(email: String, password: String) async {
        await authenticate(email: email, password: password, action: AmplifyAuthService.signUp)
    }

    func confirmSignUp(email: String, code: String) async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !trimmedCode.isEmpty else {
            message = "Enter the confirmation code from your email."
            return
        }

        isWorking = true
        message = nil
        diagnostic = nil

        do {
            try await AmplifyAuthService.confirmSignUp(email: trimmedEmail, code: trimmedCode)
            message = "Account confirmed. Continue to sign in."
            state = .signedOut
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        isWorking = false
    }

    func startPasswordReset(email: String) async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else {
            message = "Enter the email for your account."
            return
        }

        isWorking = true
        message = nil
        diagnostic = nil

        do {
            let guidance = try await AmplifyAuthService.resetPassword(email: trimmedEmail)
            state = .awaitingPasswordReset(email: trimmedEmail, message: guidance)
            message = guidance
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        isWorking = false
    }

    func confirmPasswordReset(email: String, code: String, newPassword: String) async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !trimmedCode.isEmpty, !newPassword.isEmpty else {
            message = "Enter the code and your new password."
            return
        }

        isWorking = true
        message = nil
        diagnostic = nil

        do {
            try await AmplifyAuthService.confirmResetPassword(
                email: trimmedEmail,
                newPassword: newPassword,
                confirmationCode: trimmedCode
            )
            state = .signedOut
            message = "Password updated. Continue with your new password."
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        isWorking = false
    }

    func cancelPasswordReset() {
        state = .signedOut
        message = nil
    }

    func cancelSignUpConfirmation() {
        state = .signedOut
        message = nil
    }

    func unlockWithFaceID() async {
        guard case .locked(let session) = state else { return }
        isWorking = true
        message = nil
        diagnostic = nil

        do {
            try await biometricUnlocker.unlock()
            state = .unlocked(session)
        } catch {
            message = "Face ID did not unlock SAVY. Try again or sign in."
        }

        isWorking = false
    }

    func usePasswordInstead() {
        state = .signedOut
    }

    func signOut() async {
        await AmplifyAuthService.signOut()
        KeychainSessionStore.clear()
        state = .signedOut
        message = nil
        diagnostic = nil
    }

    private func authenticate(
        email: String,
        password: String,
        action: (String, String) async throws -> AuthSession
    ) async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            message = "Enter an email and password."
            diagnostic = nil
            return
        }

        isWorking = true
        message = nil
        diagnostic = nil

        do {
            let session = try await action(trimmedEmail, password)
            try KeychainSessionStore.save(session)
            state = .unlocked(session)
        } catch let error as AmplifyAuthServiceError {
            switch error {
            case .confirmSignUpRequired(let email, let guidance):
                state = .awaitingSignUpConfirmation(email: email, message: guidance)
                message = guidance ?? error.localizedDescription
            default:
                message = error.localizedDescription
            }
        } catch {
            message = error.localizedDescription
        }

        isWorking = false
    }
}
