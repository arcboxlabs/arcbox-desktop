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

    @State private var session = DockerTerminalSession()
    @State private var connectedImageID: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
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
        SwiftTermView(delegate: TerminalBridge(session: session)) { terminalView in
            // Configure light-theme appearance
            terminalView.nativeBackgroundColor = NSColor.white
            terminalView.nativeForegroundColor = NSColor.black
            terminalView.caretColor = NSColor.black
            terminalView.selectedTextBackgroundColor = NSColor(
                red: 0.0, green: 0.48, blue: 1.0, alpha: 0.2
            )

            // Install light-friendly ANSI palette (16 colors)
            func c(_ r: UInt16, _ g: UInt16, _ b: UInt16) -> SwiftTerm.Color {
                SwiftTerm.Color(red: r * 257, green: g * 257, blue: b * 257)
            }
            terminalView.installColors([
                // Normal colors (0-7)
                c(0x00, 0x00, 0x00),  // black
                c(0xC4, 0x1A, 0x16),  // red
                c(0x2D, 0xA4, 0x4E),  // green
                c(0xCF, 0x8F, 0x09),  // yellow
                c(0x1A, 0x5C, 0xC8),  // blue
                c(0xB9, 0x39, 0xB5),  // magenta
                c(0x0E, 0x83, 0x87),  // cyan
                c(0xBF, 0xBF, 0xBF),  // white
                // Bright colors (8-15)
                c(0x60, 0x60, 0x60),  // bright black
                c(0xDE, 0x35, 0x35),  // bright red
                c(0x3F, 0xC5, 0x5F),  // bright green
                c(0xEB, 0xB5, 0x20),  // bright yellow
                c(0x3A, 0x7C, 0xF0),  // bright blue
                c(0xD0, 0x5F, 0xCC),  // bright magenta
                c(0x1C, 0xAB, 0xAF),  // bright cyan
                c(0xFF, 0xFF, 0xFF),  // bright white
            ])

            // Store terminal view reference (don't connect here — runs during makeNSView)
            // Connection is deferred to onChange(of: isActive)
            session.setTerminalView(terminalView)

            // If the terminal tab is already active, connect on next run loop
            let active = isActive
            let img = image
            DispatchQueue.main.async {
                guard active else { return }
                connectedImageID = img.id
                session.connectImage(imageName: img.fullName, shell: "/bin/sh")
            }
        }
    }

    private func connectToCurrentImage() {
        session.connectImage(imageName: image.fullName, shell: "/bin/sh")
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
