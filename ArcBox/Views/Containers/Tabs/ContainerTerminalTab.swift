import SwiftUI
import SwiftTerm
import ArcBoxClient
import DockerClient

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

            // Connect session
            session.connect(
                containerID: container.id,
                shell: selectedShell,
                terminalView: terminalView
            )
        }
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
