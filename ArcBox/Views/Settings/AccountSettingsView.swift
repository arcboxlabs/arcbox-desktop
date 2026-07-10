import ArcBoxAuth
import SwiftUI

/// Sign-in state for the ArcBox platform: identity, provider, sign in/out.
struct AccountSettingsView: View {
    @Environment(AuthSession.self) private var authSession
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    var body: some View {
        Form {
            Section("ArcBox Platform") {
                switch authSession.status {
                case .signedIn:
                    signedInRows
                case .signingIn:
                    signingInRows
                case .signedOut, .error:
                    signedOutRows
                }
                LabeledContent("Provider", value: authSession.configuration.environmentLabel)
            }
        }
        .formStyle(.grouped)
        // Sign-in fetches userinfo itself; this covers sessions restored
        // from the Keychain at launch.
        .task { await authSession.loadUserInfo() }
    }

    @ViewBuilder
    private var signedInRows: some View {
        LabeledContent("Signed in as") {
            HStack(spacing: 10) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(authSession.identity?.displayName ?? "Unknown")
                    if let email = authSession.identity?.email, authSession.identity?.name != nil {
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                avatar
            }
        }
        LabeledContent("User ID") {
            Text(authSession.identity?.subject ?? "—")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        if let expiresAt = authSession.accessTokenExpiresAt {
            LabeledContent("Session renews") {
                Text(expiresAt, format: .relative(presentation: .named))
            }
        }
        #if DEBUG
            // Dev-loop aid: exercises the refresh grant; the "Session renews"
            // row above reflects the outcome.
            Button("Refresh Access Token") {
                Task { _ = try? await authSession.accessToken() }
            }
        #endif
        Button("Sign Out", role: .destructive) {
            Task { await authSession.signOut() }
        }
    }

    /// Remote avatar with the Apple-style fallback (white silhouette on
    /// gray, as in Contacts and Apple Account settings), which also covers
    /// the loading and failure phases.
    private var avatar: some View {
        AsyncImage(url: authSession.identity?.avatarURL) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color(nsColor: .systemGray))
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(Circle())
    }

    private var signingInRows: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Waiting for the browser…")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var signedOutRows: some View {
        LabeledContent("Status", value: "Not signed in")
        if case .error(let message) = authSession.status {
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
        }
        if authSession.configuration.isPlaceholder {
            Text("No OIDC provider is configured for this build. See Local.xcconfig.example.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Button("Sign In to ArcBox…") {
            Task { await authSession.signIn(using: webAuthenticationSession) }
        }
    }
}

#Preview {
    AccountSettingsView()
        .environment(AuthSession())
}
