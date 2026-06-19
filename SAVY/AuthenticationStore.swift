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
        if case .checking = state {
            if let session = KeychainSessionStore.load() {
                state = .locked(session)
            } else {
                state = .signedOut
            }
        }
    }

    func signIn(email: String, password: String) async {
        await authenticate(email: email, password: password, mode: .signIn)
    }

    func signUp(email: String, password: String) async {
        await authenticate(email: email, password: password, mode: .signUp)
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
        if let client, case .unlocked(let session) = state {
            try? await client.signOut(accessToken: session.accessToken)
        }

        KeychainSessionStore.clear()
        state = .signedOut
        message = nil
        diagnostic = nil
    }

    private func authenticate(email: String, password: String, mode: AuthenticationMode) async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            message = "Enter an email and password."
            diagnostic = nil
            return
        }

        guard let client else {
            message = "AWS graph API is not configured in this build."
            diagnostic = AWSGraphDiagnostic(
                stage: "configuration",
                endpoint: nil,
                statusCode: nil,
                requestID: nil,
                errorCode: nil,
                missingField: nil,
                responseKeys: [],
                underlyingMessage: "Missing AWS_API_BASE_URL or AWS_API_KEY in the built app Info.plist."
            )
            return
        }

        isWorking = true
        message = nil
        diagnostic = nil

        do {
            let session: AuthSession
            switch mode {
            case .signIn:
                session = try await client.signIn(email: trimmedEmail, password: password)
            case .signUp:
                session = try await client.signUp(email: trimmedEmail, password: password)
            }

            try KeychainSessionStore.save(session)
            state = .unlocked(session)
        } catch {
            message = error.localizedDescription
            diagnostic = (error as? AWSGraphClientError)?.diagnostic ?? AWSGraphDiagnostic(
                stage: "native auth",
                endpoint: nil,
                statusCode: nil,
                requestID: nil,
                errorCode: nil,
                missingField: nil,
                responseKeys: [],
                underlyingMessage: error.localizedDescription
            )
        }

        isWorking = false
    }
}
