import SwiftUI

struct AuthGateView: View {
    @StateObject private var authStore = AuthenticationStore()

    var body: some View {
        Group {
            switch authStore.state {
            case .checking:
                StartupView()
            case .signedOut:
                LoginView(store: authStore)
            case .locked(let session):
                LockedView(store: authStore, session: session)
            case .unlocked:
                RootView {
                    Task {
                        await authStore.signOut()
                    }
                }
            }
        }
    }
}

private struct StartupView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()

            Text("SAVY")
                .font(.system(size: 54, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(SavyTheme.crimson)

            Text("Opening workspace")
                .font(.system(size: 14, weight: .bold))
                .tracking(2)
                .foregroundStyle(.black.opacity(0.42))

            ProgressView()
                .tint(SavyTheme.crimson)
                .padding(.top, 10)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
        .background(SavyTheme.paper.ignoresSafeArea())
    }
}

private struct LoginView: View {
    @ObservedObject var store: AuthenticationStore
    @State private var mode: AuthenticationMode = .signIn
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                brandHeader

                VStack(alignment: .leading, spacing: 16) {
                    Picker("Mode", selection: $mode) {
                        ForEach(AuthenticationMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        .authFieldStyle()

                    SecureField("Password", text: $password)
                        .textContentType(mode == .signIn ? .password : .newPassword)
                        .authFieldStyle()

                    Button {
                        Task {
                            switch mode {
                            case .signIn:
                                await store.signIn(email: email, password: password)
                            case .signUp:
                                await store.signUp(email: email, password: password)
                            }
                        }
                    } label: {
                        HStack {
                            if store.isWorking {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: mode == .signIn ? "person.crop.circle.badge.checkmark" : "person.badge.plus")
                            }

                            Text(mode.actionTitle)
                                .font(.system(size: 17, weight: .bold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 54)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(SavyTheme.crimson, in: RoundedRectangle(cornerRadius: 12))
                    .disabled(store.isWorking)

                    if let message = store.message {
                        Text(message)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(SavyTheme.crimson)
                    }

                    if let diagnostic = store.diagnostic {
                        DiagnosticTraceView(diagnostic: diagnostic)
                    }

                    if !store.hasBackendConfiguration {
                        Text("This build needs SUPABASE_URL and SUPABASE_ANON_KEY in the app Info.plist or build settings before sign in can reach Supabase.")
                            .font(.system(size: 14))
                            .lineSpacing(3)
                            .foregroundStyle(.black.opacity(0.52))
                    }
                }
                .padding(22)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.05), radius: 14, y: 5)
            }
            .padding(.horizontal, 28)
            .padding(.top, 88)
            .padding(.bottom, 40)
        }
        .background(SavyTheme.paper.ignoresSafeArea())
    }

    private var brandHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SAVY")
                .font(.system(size: 54, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(SavyTheme.crimson)

            Text("A STUDY IN LEVERAGE")
                .font(.system(size: 13, weight: .bold))
                .tracking(2.4)
                .foregroundStyle(.black.opacity(0.38))

            Text("Sign in once, then use Face ID to open your workspace.")
                .font(.system(size: 19, weight: .regular, design: .serif))
                .lineSpacing(5)
                .foregroundStyle(SavyTheme.ink.opacity(0.72))
                .padding(.top, 14)
        }
    }
}

private struct LockedView: View {
    @ObservedObject var store: AuthenticationStore
    let session: AuthSession

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                Text("SAVY")
                    .font(.system(size: 54, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(SavyTheme.crimson)

                Text(session.user.email ?? "Your workspace")
                    .font(.system(size: 15, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(.black.opacity(0.38))
            }

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

            Button("Use password instead") {
                store.usePasswordInstead()
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(SavyTheme.ink.opacity(0.62))

            if let message = store.message {
                Text(message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SavyTheme.crimson)
            }

            if let diagnostic = store.diagnostic {
                DiagnosticTraceView(diagnostic: diagnostic)
            }

            Spacer()
        }
        .padding(.horizontal, 28)
        .background(SavyTheme.paper.ignoresSafeArea())
    }
}

private struct DiagnosticTraceView: View {
    let diagnostic: SupabaseDiagnostic

    var body: some View {
        DisclosureGroup {
            Text(diagnostic.displayText)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.black.opacity(0.58))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        } label: {
            Label("Supabase Trace", systemImage: "waveform.path.ecg.rectangle")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(SavyTheme.ink.opacity(0.58))
        }
        .padding(12)
        .background(SavyTheme.paperAccent, in: RoundedRectangle(cornerRadius: 10))
    }
}

private extension View {
    func authFieldStyle() -> some View {
        self
            .font(.system(size: 17))
            .textFieldStyle(.plain)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(SavyTheme.paperAccent, in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(SavyTheme.ink)
    }
}
