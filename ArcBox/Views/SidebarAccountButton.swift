import ArcBoxAuth
import SwiftUI

/// Account chip pinned to the bottom of the main-window sidebar.
///
/// Signed out it shows the placeholder avatar and "Sign In" and starts the
/// browser flow directly; signed in it shows the avatar and display name
/// and opens Settings > Account.
struct SidebarAccountButton: View {
    @Environment(AppViewModel.self) private var appVM
    @Environment(AuthSession.self) private var authSession
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @Environment(\.openWindow) private var openWindow
    @State private var isHovered = false

    var body: some View {
        Button(action: primaryAction) {
            HStack(spacing: 8) {
                if authSession.status == .signingIn {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 24, height: 24)
                    Text("Signing In…")
                        .foregroundStyle(.secondary)
                } else {
                    AvatarView(url: authSession.identity?.avatarURL, size: 24)
                    Text(title)
                }
                Spacer(minLength: 0)
            }
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(
            isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
            in: .rect(cornerRadius: 6)
        )
        .onHover { isHovered = $0 }
        // Leading inset tuned so the avatar lines up with the icons of the
        // sidebar list rows above.
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .disabled(isDisabled)
        .help(helpText)
    }

    private var title: String {
        authSession.status == .signedIn
            ? authSession.identity?.displayName ?? "Account"
            : "Sign In"
    }

    private var isDisabled: Bool {
        authSession.status == .signingIn
            || (authSession.status != .signedIn && authSession.configuration.isPlaceholder)
    }

    private var helpText: String {
        if authSession.status == .signedIn { return "Open account settings" }
        if authSession.configuration.isPlaceholder { return "No OIDC provider is configured" }
        return "Sign in to ArcBox"
    }

    private func primaryAction() {
        if authSession.status == .signedIn {
            appVM.settingsTab = .account
            openWindow(id: "settings")
        } else {
            Task { await authSession.signIn(using: webAuthenticationSession) }
        }
    }
}
