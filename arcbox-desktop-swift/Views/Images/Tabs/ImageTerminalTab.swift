import SwiftUI
import SwiftTerm

/// Terminal tab providing an interactive shell into a temporary container spawned from an image.
struct ImageTerminalTab: View {
    let image: ImageViewModel

    @State private var session = DockerTerminalSession()
    @State private var selectedShell = "/bin/sh"

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
                c(0x00, 0x00, 0x00),   // black
                c(0xC4, 0x1A, 0x16),   // red
                c(0x2D, 0xA4, 0x4E),   // green
                c(0xCF, 0x8F, 0x09),   // yellow
                c(0x1A, 0x5C, 0xC8),   // blue
                c(0xB9, 0x39, 0xB5),   // magenta
                c(0x0E, 0x83, 0x87),   // cyan
                c(0xBF, 0xBF, 0xBF),   // white
                // Bright colors (8-15)
                c(0x60, 0x60, 0x60),   // bright black
                c(0xDE, 0x35, 0x35),   // bright red
                c(0x3F, 0xC5, 0x5F),   // bright green
                c(0xEB, 0xB5, 0x20),   // bright yellow
                c(0x3A, 0x7C, 0xF0),   // bright blue
                c(0xD0, 0x5F, 0xCC),   // bright magenta
                c(0x1C, 0xAB, 0xAF),   // bright cyan
                c(0xFF, 0xFF, 0xFF),   // bright white
            ])

            // Launch ephemeral container from image
            session.runImage(
                imageName: image.fullName,
                shell: selectedShell,
                terminalView: terminalView
            )
        }
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
    }
}
