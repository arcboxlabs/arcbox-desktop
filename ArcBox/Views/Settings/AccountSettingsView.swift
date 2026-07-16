import AppKit
import ArcBoxAuth
import SwiftUI

/// Sign-in state for the ArcBox platform: identity, session, sign in/out.
struct AccountSettingsView: View {
    @Environment(AuthSession.self) private var authSession
    @State private var isConfirmingSignOut = false

    var body: some View {
        Form {
            switch authSession.status {
            case .signedIn:
                signedInSections
            case .restoring:
                restoringSection
            case .signedOut, .signingIn, .error:
                signedOutSection
            }
        }
        .formStyle(.grouped)
        // Sign-in verifies the session itself; this covers sessions restored
        // from the Keychain at launch.
        .task { await authSession.refreshSession() }
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

    private var restoringSection: some View {
        Section {
            ContentUnavailableView {
                Label("Restoring Session", systemImage: "person.crop.circle.badge.clock")
            } description: {
                Text("Checking for a saved ArcBox sign-in.")
            } actions: {
                ProgressView()
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        }
    }

    private var signedOutSection: some View {
        Section {
            ContentUnavailableView {
                Label("Not Signed In", systemImage: "person.crop.circle")
            } description: {
                if authSession.configuration.isPlaceholder {
                    Text(
                        "No sign-in service is configured for this build. See Local.xcconfig.example."
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
                    signingInPrompt
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

    /// Browser-approval progress: the confirmation code to match in the
    /// browser, a way to reopen the page, and an escape hatch.
    @ViewBuilder
    private var signingInPrompt: some View {
        VStack(spacing: 10) {
            if let prompt = authSession.deviceAuthorization {
                Text(prompt.userCode)
                    .font(.title2.monospaced().bold())
                    .textSelection(.enabled)
                    .accessibilityLabel("Sign-in confirmation code")
                Text("Confirm this code in your browser to finish signing in.")
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button("Open Browser") {
                        NSWorkspace.shared.open(prompt.browserURL)
                    }
                    Button("Cancel", role: .cancel) {
                        authSession.cancelSignIn()
                    }
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Contacting the sign-in service…")
                        .foregroundStyle(.secondary)
                }
                Button("Cancel", role: .cancel) {
                    authSession.cancelSignIn()
                }
            }
        }
    }

    // MARK: - Actions

    private func signIn() {
        Task { await authSession.signIn() }
    }

    private func signOut() {
        Task { await authSession.signOut() }
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
