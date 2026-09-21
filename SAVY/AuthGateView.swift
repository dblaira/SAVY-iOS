import SwiftUI

struct AuthGateView: View {
    @StateObject private var authStore = AuthenticationStore()

    var body: some View {
        Group {
            if ProcessInfo.processInfo.arguments.contains("SAVY_UI_TEST_UNLOCKED") {
                RootView(
                    session: .uiTest,
                    onSignOut: {},
                    initialSection: ProcessInfo.processInfo.arguments.contains("SAVY_UI_TEST_OPEN_REMINDERS")
                        ? .reminders
                        : .now
                )
            } else {
                switch authStore.state {
                case .checking:
                    ProgressView()
                        .tint(SavyTheme.crimson)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(SavyTheme.deepNavy.ignoresSafeArea())
                case .signedOut:
                    LoginView(store: authStore)
                case .awaitingSignUpConfirmation(let email, let guidance):
                    ConfirmSignUpView(store: authStore, email: email, guidance: guidance)
                case .awaitingPasswordReset(let email, let guidance):
                    ResetPasswordView(store: authStore, email: email, guidance: guidance)
                case .locked(let session):
                    LockedView(store: authStore, session: session)
                case .unlocked(let session):
                    RootView(session: session) {
                        Task {
                            await authStore.signOut()
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            guard !ProcessInfo.processInfo.arguments.contains("SAVY_UI_TEST_UNLOCKED") else { return }
            authStore.bootstrap()
        }
    }
}

private extension AuthSession {
    static let uiTest = AuthSession(
        accessToken: "ui-test-access-token",
        refreshToken: "ui-test-refresh-token",
        tokenType: "bearer",
        expiresIn: 3600,
        user: AuthUser(id: "ui-test-user", email: "ui-test@savy.local")
    )
}

private struct LoginView: View {
    @ObservedObject var store: AuthenticationStore
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                brandHeader

                VStack(alignment: .leading, spacing: 16) {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        .authFieldStyle()

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .authFieldStyle()

                    Button {
                        Task {
                            await store.enter(email: email, password: password)
                        }
                    } label: {
                        HStack {
                            if store.isWorking {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "arrow.right.circle.fill")
                            }

                            Text("Continue")
                                .font(.system(size: 17, weight: .bold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 54)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(SavyTheme.crimson, in: RoundedRectangle(cornerRadius: 12))
                    .disabled(store.isWorking)

                    Button("Forgot password?") {
                        Task {
                            await store.startPasswordReset(email: email)
                        }
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SavyTheme.crimson)
                    .disabled(store.isWorking || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Text("First time here? Continue creates your account. Returning? Continue signs you in.")
                        .font(.system(size: 14, weight: .regular, design: .serif))
                        .foregroundStyle(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)

                    if let message = store.message {
                        Text(message)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(SavyTheme.crimson)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !store.hasBackendConfiguration {
                        Text("Beliefs API is not configured in this build. Auth still works; live data may use seed content.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 88)
            .padding(.bottom, 40)
        }
        .background(SavyTheme.deepNavy.ignoresSafeArea())
    }

    private var brandHeader: some View {
        Text("SAVY")
            .font(SavyTypography.displaySerif(54, weight: .bold))
            .foregroundStyle(.white)
    }
}

private struct ConfirmSignUpView: View {
    @ObservedObject var store: AuthenticationStore
    let email: String
    let guidance: String?
    @State private var code = ""

    var body: some View {
        authForm(
            title: "Confirm your account",
            instructions: guidance ?? "Enter the code AWS sent to \(email)."
        ) {
            TextField("Confirmation code", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .authFieldStyle()

            Button {
                Task {
                    await store.confirmSignUp(email: email, code: code)
                }
            } label: {
                primaryButtonLabel("Confirm Account")
            }
            .disabled(store.isWorking || code.isEmpty)

            Button("Back to sign in") {
                store.cancelSignUpConfirmation()
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white.opacity(0.72))

            if let message = store.message {
                Text(message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SavyTheme.crimson)
            }
        }
    }
}

private struct ResetPasswordView: View {
    @ObservedObject var store: AuthenticationStore
    let email: String
    let guidance: String?
    @State private var code = ""
    @State private var newPassword = ""

    var body: some View {
        authForm(
            title: "Reset password",
            instructions: guidance ?? "Enter the code sent to \(email) and choose a new password."
        ) {
            TextField("Reset code", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .authFieldStyle()

            SecureField("New password", text: $newPassword)
                .textContentType(.newPassword)
                .authFieldStyle()

            Button {
                Task {
                    await store.confirmPasswordReset(
                        email: email,
                        code: code,
                        newPassword: newPassword
                    )
                }
            } label: {
                primaryButtonLabel("Update Password")
            }
            .disabled(store.isWorking || code.isEmpty || newPassword.isEmpty)

            Button("Back to sign in") {
                store.cancelPasswordReset()
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white.opacity(0.72))

            if let message = store.message {
                Text(message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SavyTheme.crimson)
            }
        }
    }
}

private struct LockedView: View {
    @ObservedObject var store: AuthenticationStore
    let session: AuthSession

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            Spacer()

            Text("SAVY")
                .font(SavyTypography.displaySerif(54, weight: .bold))
                .foregroundStyle(SavyTheme.crimson)

            Button {
                Task {
                    await store.unlockWithFaceID()
                }
            } label: {
                HStack {
                    Image(systemName: "faceid")
                    Text("Open with Face ID")
                        .font(.system(size: 17, weight: .bold))
                }
                .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(SavyTheme.crimson, in: RoundedRectangle(cornerRadius: 12))
            .disabled(store.isWorking || !store.canUseFaceID)

            if let email = session.user.displayEmail {
                Text(email)
                    .font(.system(size: 15, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(Brand.tabActive)
            }

            Button("Use password instead") {
                store.usePasswordInstead()
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Brand.tabActive)

            if let message = store.message {
                Text(message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SavyTheme.crimson)
            }

            Spacer()
        }
        .padding(.horizontal, 28)
        .background(
            LinearGradient(
                stops: [
                    .init(color: Brand.card, location: 0),
                    .init(color: Brand.card, location: 0.25),
                    .init(color: SavyTheme.bottomNavTan, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }
}

@ViewBuilder
private func authForm<Content: View>(
    title: String,
    instructions: String,
    @ViewBuilder content: () -> Content
) -> some View {
    ScrollView {
        VStack(alignment: .leading, spacing: 28) {
            Text(title)
                .font(SavyTypography.displaySerif(34, weight: .bold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 16) {
                content()

                Text(instructions)
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .lineSpacing(4)
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 88)
        .padding(.bottom, 40)
    }
    .background(SavyTheme.deepNavy.ignoresSafeArea())
}

@ViewBuilder
private func primaryButtonLabel(_ title: String) -> some View {
    Text(title)
        .font(.system(size: 17, weight: .bold))
        .frame(maxWidth: .infinity, minHeight: 54)
        .foregroundStyle(.white)
        .background(SavyTheme.crimson, in: RoundedRectangle(cornerRadius: 12))
}

private extension View {
    func authFieldStyle() -> some View {
        self
            .font(.system(size: 17))
            .textFieldStyle(.plain)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(SavyTheme.paperAccent, in: RoundedRectangle(cornerRadius: 10))
            .environment(\.colorScheme, .light)
            .foregroundStyle(SavyTheme.ink)
    }
}
