import Amplify
import AWSPluginsCore
import AWSCognitoAuthPlugin
import Foundation

enum AmplifyAuthService {
    private static nonisolated(unsafe) var isConfigured = false

    static func configureIfNeeded() throws {
        guard !isConfigured else { return }

        try Amplify.add(plugin: AWSCognitoAuthPlugin())
        try Amplify.configure()
        isConfigured = true
    }

    static func bootstrapSession() async throws -> AuthSession? {
        let session = try await Amplify.Auth.fetchAuthSession()
        guard session.isSignedIn else { return nil }
        return try await currentSession()
    }

    static func enter(email: String, password: String) async throws -> AuthSession {
        do {
            return try await signIn(email: email, password: password)
        } catch let signInError as AmplifyAuthServiceError where signInError.shouldAttemptSignUp {
            do {
                return try await signUp(email: email, password: password)
            } catch let signUpError as AmplifyAuthServiceError where signUpError.isExistingAccount {
                throw AmplifyAuthServiceError.invalidCredentials
            }
        }
    }

    static func signIn(email: String, password: String) async throws -> AuthSession {
        do {
            let result = try await Amplify.Auth.signIn(username: email, password: password)

            switch result.nextStep {
            case .done:
                return try await currentSession()
            case .confirmSignUp:
                throw AmplifyAuthServiceError.confirmSignUpRequired(email: email)
            default:
                throw AmplifyAuthServiceError.additionalStepRequired(
                    "Sign-in needs another step this build does not handle yet."
                )
            }
        } catch let error as AmplifyAuthServiceError {
            throw error
        } catch {
            throw AmplifyAuthServiceError.map(error)
        }
    }

    static func signUp(email: String, password: String) async throws -> AuthSession {
        do {
            let attributes = [AuthUserAttribute(.email, value: email)]
            let options = AuthSignUpRequest.Options(userAttributes: attributes)
            let result = try await Amplify.Auth.signUp(
                username: email,
                password: password,
                options: options
            )

            switch result.nextStep {
            case .done:
                return try await signIn(email: email, password: password)
            case .completeAutoSignIn:
                _ = try await Amplify.Auth.autoSignIn()
                return try await currentSession()
            case .confirmUser(let deliveryDetails, _, _):
                let destination = deliveryLabel(deliveryDetails?.destination)
                throw AmplifyAuthServiceError.confirmSignUpRequired(
                    email: email,
                    message: "Check \(destination) for your confirmation code."
                )
            }
        } catch let error as AmplifyAuthServiceError {
            throw error
        } catch {
            throw AmplifyAuthServiceError.map(error)
        }
    }

    static func confirmSignUp(email: String, code: String) async throws {
        let result = try await Amplify.Auth.confirmSignUp(for: email, confirmationCode: code)

        switch result.nextStep {
        case .done:
            return
        case .completeAutoSignIn:
            _ = try await Amplify.Auth.autoSignIn()
            return
        default:
            throw AmplifyAuthServiceError.additionalStepRequired(
                "Account confirmation needs another step."
            )
        }
    }

    static func resetPassword(email: String) async throws -> String {
        let result = try await Amplify.Auth.resetPassword(for: email)

        switch result.nextStep {
        case .confirmResetPasswordWithCode(let details, _):
            return "Enter the code sent to \(deliveryLabel(details.destination))."
        case .done:
            return "Password reset complete. Sign in with your new password."
        }
    }

    static func confirmResetPassword(
        email: String,
        newPassword: String,
        confirmationCode: String
    ) async throws {
        try await Amplify.Auth.confirmResetPassword(
            for: email,
            with: newPassword,
            confirmationCode: confirmationCode
        )
    }

    static func signOut() async {
        _ = await Amplify.Auth.signOut()
    }

    static func currentSession() async throws -> AuthSession {
        let authSession = try await Amplify.Auth.fetchAuthSession()
        guard authSession.isSignedIn else {
            throw AmplifyAuthServiceError.notSignedIn
        }

        guard let tokenProvider = authSession as? AuthCognitoTokensProvider else {
            throw AmplifyAuthServiceError.missingTokens
        }

        let tokens = try tokenProvider.getCognitoTokens().get()
        let cognitoUser = try await Amplify.Auth.getCurrentUser()
        let attributes = try await Amplify.Auth.fetchUserAttributes()
        let attributeEmail = attributes.first(where: { $0.key == .email })?.value

        let email: String?
        if let attributeEmail, attributeEmail.contains("@") {
            email = attributeEmail
        } else if cognitoUser.username.contains("@") {
            email = cognitoUser.username
        } else {
            email = nil
        }

        return AuthSession(
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            tokenType: "bearer",
            expiresIn: 3600,
            user: AuthUser(id: cognitoUser.userId, email: email)
        )
    }

    private static func deliveryLabel(_ destination: DeliveryDestination?) -> String {
        guard let destination else { return "your email" }

        switch destination {
        case .email(let value):
            return value ?? "your email"
        case .phone(let value), .sms(let value):
            return value ?? "your phone"
        case .unknown(let value):
            return value ?? "your account"
        }
    }
}

enum AmplifyAuthServiceError: LocalizedError, Equatable {
    case notSignedIn
    case missingTokens
    case invalidCredentials
    case confirmSignUpRequired(email: String, message: String? = nil)
    case additionalStepRequired(String)
    case existingAccount

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "You are signed out."
        case .missingTokens:
            return "Could not read your sign-in session."
        case .invalidCredentials:
            return "Email or password did not match."
        case .confirmSignUpRequired(_, let message):
            return message ?? "Check your email for the confirmation code."
        case .additionalStepRequired(let message):
            return message
        case .existingAccount:
            return "That account already exists. Use your password or reset it."
        }
    }

    var shouldAttemptSignUp: Bool {
        switch self {
        case .invalidCredentials, .notSignedIn:
            return true
        default:
            return false
        }
    }

    var isExistingAccount: Bool {
        if case .existingAccount = self { return true }
        return false
    }

    static func map(_ error: Error) -> AmplifyAuthServiceError {
        if let mapped = error as? AmplifyAuthServiceError {
            return mapped
        }

        if let authError = error as? AuthError {
            let combined = [
                authError.errorDescription,
                authError.recoverySuggestion,
                authError.underlyingError?.localizedDescription
            ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

            if combined.contains("user does not exist")
                || combined.contains("usernotfound")
                || combined.contains("user not found") {
                return .invalidCredentials
            }

            if combined.contains("usernameexists")
                || combined.contains("already exists")
                || combined.contains("user already exists") {
                return .existingAccount
            }

            if combined.contains("notauthorized")
                || combined.contains("incorrect")
                || combined.contains("password") {
                return .invalidCredentials
            }

            return .additionalStepRequired(
                authError.errorDescription
            )
        }

        return .additionalStepRequired(error.localizedDescription)
    }
}
