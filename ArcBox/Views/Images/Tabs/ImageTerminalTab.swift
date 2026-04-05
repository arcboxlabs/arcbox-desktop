import SwiftTerm
import SwiftUI

/// Terminal tab providing an interactive shell into a temporary container spawned from an image.
///
/// The TerminalView (NSView) is created once and kept alive via ZStack + opacity in
/// ImageDetailView. The session only connects/reconnects when the tab is visible
/// (`isActive == true`), avoiding unnecessary docker process management.
struct ImageTerminalTab: View {
    let image: ImageViewModel
    let isActive: Bool

    @AppStorage("terminalTheme") private var terminalTheme = "system"
    @State private var session = DockerTerminalSession()
    @State private var selectedShell = "/bin/sh"
    @State private var connectedImageID: String = ""

    private let availableShells = ["/bin/sh", "/bin/bash", "/bin/zsh"]

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                Picker("Shell", selection: $selectedShell) {
                    ForEach(availableShells, id: \.self) { shell in
                        Text(shell).tag(shell)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)
                .disabled(session.state == .connected)

                Spacer()

                if session.state == .connected {
                    Button(action: { session.disconnect() }) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Disconnect")
                } else if session.state == .disconnected || session.state == .idle {
                    Button(action: reconnect) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Reconnect")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            // Terminal content
            switch session.state {
            case .error(let message):
                errorView(message)
            default:
                terminalContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .onChange(of: isActive) { _, nowActive in
            // When terminal tab becomes visible, connect if needed
            if nowActive && image.id != connectedImageID {
                connectToCurrentImage()
            }
        }
        .onChange(of: image.id) { _, newID in
            guard newID != connectedImageID else { return }
            // Only reconnect if terminal is currently visible
            guard isActive else { return }
            connectToCurrentImage()
        }
        .onDisappear {
            session.disconnect()
        }
    }

    private var terminalContent: some View {
        SwiftTermView(delegate: TerminalBridge(session: session), theme: terminalTheme) { terminalView in
            configureTerminalAppearance(terminalView)

            // Store terminal view reference (don't connect here — runs during makeNSView)
            // Connection is deferred to onChange(of: isActive)
            session.setTerminalView(terminalView)

            // If the terminal tab is already active, connect on next run loop
            let active = isActive
            let img = image
            let shell = selectedShell
            DispatchQueue.main.async {
                guard active else { return }
                connectedImageID = img.id
                session.connectImage(imageName: img.fullName, shell: shell)
            }
        }
    }

    private func configureTerminalAppearance(_ terminalView: TerminalView) {
        TerminalAppearance.configure(terminalView, theme: terminalTheme)
    }

    private func connectToCurrentImage() {
        session.connectImage(imageName: image.fullName, shell: selectedShell)
        connectedImageID = image.id
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(AppColors.textMuted)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)
            Button("Retry") {
                reconnect()
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reconnect() {
        session.disconnect()
        session.state = .idle
        connectToCurrentImage()
    }
}
