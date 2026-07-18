import ArcBoxClient
import SwiftTerm
import SwiftUI

/// Terminal tab providing an interactive shell into a machine.
struct MachineTerminalTab: View {
    let machine: MachineViewModel

    @Environment(\.arcboxClient) private var client

    @State private var session = MachineTerminalSession()
    @State private var selectedShell = "/bin/sh"
    @State private var terminalToken = UUID()
    @State private var hasConnected = false

    private let availableShells = ["/bin/sh", "/bin/bash", "/bin/zsh"]

    var body: some View {
        VStack(spacing: 0) {
            if machine.isRunning {
                toolbar

                Divider()

                // Terminal content — keep SwiftTermView alive to avoid
                // recreation loops
                if case .error(let message) = session.state {
                    errorView(message)
                } else {
                    ZStack {
                        terminalContent
                            .id(terminalToken)

                        if session.state == .connecting {
                            VStack {
                                Spacer()
                                ProgressView("Connecting…")
                                    .progressViewStyle(.circular)
                                    .foregroundStyle(AppColors.textSecondary)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(AppColors.background)
                        }
                    }
                }
            } else {
                notRunningView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .onDisappear {
            session.disconnect()
        }
        .onChange(of: machine.id) {
            // Selection moved to another machine: drop the old session.
            reconnect()
        }
    }

    private var toolbar: some View {
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
                Button(
                    action: { session.disconnect() },
                    label: {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                )
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
    }

    private var terminalContent: some View {
        SwiftTermView(delegate: TerminalSessionBridge(session: session)) { terminalView in
            TerminalAppearance.configure(terminalView)

            guard !hasConnected, let client else { return }
            let machineID = machine.id
            let shell = selectedShell
            // Defer state modifications out of the view update cycle.
            Task { @MainActor in
                hasConnected = true
                session.connect(
                    machineID: machineID,
                    command: [shell, "-l"],
                    client: client,
                    terminalView: terminalView
                )
            }
        }
    }

    private var notRunningView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "terminal")
                .font(.system(size: 32))
                .foregroundStyle(AppColors.textMuted)
            Text("Machine is not running")
                .font(.system(size: 15))
                .foregroundStyle(AppColors.textSecondary)
            Text("Start the machine to open a terminal.")
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        hasConnected = false
        terminalToken = UUID()
    }
}
