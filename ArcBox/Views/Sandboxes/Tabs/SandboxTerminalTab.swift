import ArcBoxClient
import SwiftTerm
import SwiftUI

/// Terminal tab providing an interactive shell into a sandbox.
struct SandboxTerminalTab: View {
    let sandboxID: String

    @Environment(SandboxesViewModel.self) private var vm
    @Environment(\.arcboxClient) private var client

    @State private var session = SandboxTerminalSession()
    @State private var selectedShell = "/bin/sh"
    @State private var terminalToken = UUID()

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
            case .connecting:
                VStack {
                    Spacer()
                    ProgressView("Connecting…")
                        .progressViewStyle(.circular)
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .error(let message):
                errorView(message)
            default:
                terminalContent
                    .id(terminalToken)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .onDisappear {
            session.disconnect()
        }
    }

    private var terminalContent: some View {
        SwiftTermView(delegate: SandboxTerminalBridge(session: session)) { terminalView in
            TerminalAppearance.configure(terminalView)

            guard let client else { return }
            session.connect(
                sandboxID: sandboxID,
                command: [selectedShell],
                machineID: vm.activeMachineID,
                client: client,
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
        terminalToken = UUID()
    }
}
