import Foundation

struct AuthSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int
    let user: AuthUser

    var authorizationHeader: String {
        "\(tokenType.capitalized) \(accessToken)"
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case user
    }
}

struct AuthUser: Codable, Equatable {
    let id: String
    let email: String?

    /// Human-readable account label for UI. Hides Cognito UUID usernames.
    var displayEmail: String? {
        guard let email, email.contains("@") else { return nil }
        return email
    }
}

enum AuthenticationState: Equatable {
    case checking
    case signedOut
    case awaitingSignUpConfirmation(email: String, message: String?)
    case awaitingPasswordReset(email: String, message: String?)
    case locked(AuthSession)
    case unlocked(AuthSession)
}

enum AuthenticationMode: String, CaseIterable, Identifiable {
    case signIn = "Sign In"
    case signUp = "Create Account"

    var id: String { rawValue }

    var actionTitle: String {
        switch self {
        case .signIn:
            return "Sign In"
        case .signUp:
            return "Create Account"
        }
    }
}
