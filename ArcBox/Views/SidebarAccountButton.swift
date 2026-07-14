import ArcBoxAuth
import SwiftUI

/// Account chip pinned to the bottom of the main-window sidebar.
///
/// Signed out it shows the placeholder avatar and "Sign In" and starts the
/// browser flow directly; signed in (or while a sign-in is in flight) it
/// shows the current state and opens Settings > Account.
struct SidebarAccountButton: View {
    @Environment(AppViewModel.self) private var appVM
    @Environment(AuthSession.self) private var authSession
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
        authSession.status != .signedIn && authSession.status != .signingIn
            && authSession.configuration.isPlaceholder
    }

    private var helpText: String {
        switch authSession.status {
        case .signedIn: return "Open account settings"
        case .signingIn: return "Waiting for the browser — click to manage"
        default:
            return authSession.configuration.isPlaceholder
                ? "No OIDC provider is configured" : "Sign in to ArcBox"
        }
    }

    private func primaryAction() {
        switch authSession.status {
        case .signedIn, .signingIn:
            // While signing in, Settings > Account shows progress and offers
            // Cancel — the only way out of an abandoned browser leg.
            appVM.settingsTab = .account
            openWindow(id: "settings")
        default:
            Task { await authSession.signIn() }
        }
    }
}
