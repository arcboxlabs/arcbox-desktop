import ArcBoxClient
import DockerClient
import SwiftTerm
import SwiftUI

/// Terminal tab providing an interactive shell into a running container.
struct ContainerTerminalTab: View {
    let container: ContainerViewModel

    @Environment(ContainersViewModel.self) private var vm
    @Environment(\.arcboxClient) private var client
    @Environment(\.dockerClient) private var docker

    @State private var session = DockerTerminalSession()
    @State private var selectedShell = "/bin/sh"
    @State private var terminalToken = UUID()

    private let availableShells = ["/bin/sh", "/bin/bash", "/bin/zsh"]

    var body: some View {
        VStack(spacing: 0) {
            if container.state == .running {
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
            }

            // Terminal content
            if container.state != .running {
                notRunningView
            } else {
                switch session.state {
                case .error(let message):
                    errorView(message)
                default:
                    terminalContent
                        .id(terminalToken)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .task(id: container.id) {
            connectIfRunning()
        }
        .onDisappear {
            session.disconnect()
        }
        .onChange(of: container.state) { _, newState in
            if newState != .running {
                session.disconnect()
            }
        }
    }

    private var terminalContent: some View {
        SwiftTermView(delegate: TerminalBridge(session: session)) { terminalView in
            configureTerminalAppearance(terminalView)

            // Connect session
            session.connect(
                containerID: container.id,
                shell: selectedShell,
                terminalView: terminalView
            )
        }
    }

    private func configureTerminalAppearance(_ terminalView: TerminalView) {
        TerminalAppearance.configure(terminalView)
    }

    private var notRunningView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                // Container icon
                ZStack {
                    Circle()
                        .fill(AppColors.surfaceElevated)
                        .frame(width: 64, height: 64)
                    Image(systemName: "shippingbox")
                        .font(.system(size: 26))
                        .foregroundStyle(AppColors.textMuted)
                }

                // Container name
                Text(container.name)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.text)

                // Status badge
                HStack(spacing: 6) {
                    Circle()
                        .fill(container.state.color)
                        .frame(width: 8, height: 8)
                    Text(container.state.label)
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.textSecondary)
                }

                // Start button
                Button(action: startContainer) {
                    if container.isTransitioning {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 11))
                            Text("Start")
                                .font(.system(size: 13, weight: .medium))
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(container.isTransitioning)
                .padding(.top, 4)

                // Hint text
                Text("Start the container to open a terminal session.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textMuted)
            }

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

    private func connectIfRunning() {
        guard container.state == .running else { return }
        // Connection happens in SwiftTermView's onTerminalCreated callback
        // If already disconnected, the view will be recreated
    }

    private func reconnect() {
        session.disconnect()
        session.state = .idle
        terminalToken = UUID()
    }

    private func startContainer() {
        Task {
            if docker != nil {
                await vm.startContainerDocker(container.id, docker: docker)
            } else {
                await vm.startContainer(container.id, client: client)
            }
        }
    }
}
