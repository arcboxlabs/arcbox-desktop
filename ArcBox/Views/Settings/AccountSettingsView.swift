import AppKit
import ArcBoxAuth
import SwiftUI

/// Sign-in state for the ArcBox platform: identity, session, sign in/out.
struct AccountSettingsView: View {
    @Environment(AuthSession.self) private var authSession
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var isConfirmingSignOut = false

    var body: some View {
        Form {
            switch authSession.status {
            case .signedIn:
                signedInSections
            case .signedOut, .signingIn, .error:
                signedOutSection
            }
        }
        .formStyle(.grouped)
        // Sign-in fetches userinfo itself; this covers sessions restored
        // from the Keychain at launch.
        .task { await authSession.loadUserInfo() }
    }

    // MARK: - Signed in

    @ViewBuilder
    private var signedInSections: some View {
        Section {
            AccountIdentityHeader(identity: authSession.identity)
        }
        Section("Account") {
            LabeledContent("User ID") {
                HStack(spacing: 4) {
                    Text(authSession.identity?.subject ?? "—")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    // Button("Copy User ID", systemImage: "doc.on.doc", action: copyUserID)
                    //     .labelStyle(.iconOnly)
                    //     .buttonStyle(.borderless)
                    //     .controlSize(.small)
                    //     .help("Copy User ID")
                }
            }
            LabeledContent("Provider", value: authSession.configuration.environmentLabel)
        }
        Section("Session") {
            if let expiresAt = authSession.accessTokenExpiresAt {
                LabeledContent("Session renews") {
                    Text(expiresAt, format: .relative(presentation: .named))
                }
            }
            #if DEBUG
                // Dev-loop aid: exercises the refresh grant; the "Session
                // renews" row above reflects the outcome.
                Button("Refresh Access Token", action: refreshAccessToken)
            #endif
        }
        Section {
            Button("Sign Out…", role: .destructive) {
                isConfirmingSignOut = true
            }
            // Form rows on macOS don't tint from the destructive role alone.
            .foregroundStyle(.red)
            .confirmationDialog("Sign out of ArcBox?", isPresented: $isConfirmingSignOut) {
                Button("Sign Out", role: .destructive, action: signOut)
            } message: {
                Text("Your local containers and settings are unaffected.")
            }
        }
    }

    // MARK: - Signed out / signing in

    private var signedOutSection: some View {
        Section {
            ContentUnavailableView {
                Label("Not Signed In", systemImage: "person.crop.circle")
            } description: {
                if authSession.configuration.isPlaceholder {
                    Text(
                        "No OIDC provider is configured for this build. See Local.xcconfig.example."
                    )
                } else {
                    Text("Sign in to your ArcBox account to use platform features.")
                }
                if case .error(let message) = authSession.status {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            } actions: {
                if authSession.status == .signingIn {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Waiting for the browser…")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button("Sign In to ArcBox…", action: signIn)
                        .buttonStyle(.borderedProminent)
                        .disabled(authSession.configuration.isPlaceholder)
                }
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Actions

    private func signIn() {
        Task { await authSession.signIn(using: webAuthenticationSession) }
    }

    private func signOut() {
        Task { await authSession.signOut() }
    }

    private func refreshAccessToken() {
        Task { _ = try? await authSession.accessToken() }
    }

    private func copyUserID() {
        guard let subject = authSession.identity?.subject else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(subject, forType: .string)
    }
}

/// Hero header for the signed-in account — avatar, display name, and email
/// with a verification badge — in the style of the Apple Account pane.
private struct AccountIdentityHeader: View {
    let identity: AuthIdentity?

    var body: some View {
        VStack(spacing: 8) {
            AvatarView(url: identity?.avatarURL, size: 64)
            Text(identity?.displayName ?? "Unknown")
                .font(.title3)
                .bold()
            if let email = identity?.email {
                HStack(spacing: 4) {
                    Text(email)
                    if identity?.emailVerified == true {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .help("Email address verified")
                            .accessibilityLabel("Verified")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .listRowBackground(Color.clear)
    }
}

#Preview {
    AccountSettingsView()
        .environment(AuthSession())
}
