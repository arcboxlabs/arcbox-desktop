import ArcBoxClient
import SwiftUI

/// Column 3: sandbox detail with tab-based toolbar
struct SandboxDetailView: View {
    @Environment(SandboxesViewModel.self) private var vm
    @Environment(\.arcboxClient) private var client

    var body: some View {
        @Bindable var vm = vm
        let sandbox = vm.selectedSandbox

        VStack(spacing: 0) {
            if let sandbox {
                switch vm.activeTab {
                case .info:
                    infoTab(sandbox)
                case .terminal:
                    if sandbox.state.isActive {
                        SandboxTerminalTab(
                            sandboxID: sandbox.id,
                            canStartExecution: sandbox.state.isAcceptingCommands,
                            session: vm.terminalSession
                        )
                        .id(sandbox.id)
                    } else {
                        tabUnavailable("Sandbox must be alive for terminal access")
                    }
                case .files:
                    if sandbox.state.isDataPlaneReady {
                        SandboxFilesTab(sandbox: sandbox)
                            .id(sandbox.id)
                    } else {
                        tabUnavailable("Sandbox must be ready for file transfer")
                    }
                case .ports:
                    if sandbox.state.isDataPlaneReady {
                        SandboxPortsTab(sandbox: sandbox)
                            .id(sandbox.id)
                    } else {
                        tabUnavailable("Sandbox must be ready to expose ports")
                    }
                case .snapshots:
                    SandboxSnapshotsTab(sandbox: sandbox)
                case .events:
                    SandboxEventsTab(sandboxID: sandbox.id)
                }
            } else {
                Spacer()
                Text("No Selection")
                    .foregroundStyle(AppColors.textSecondary)
                    .font(.system(size: 15))
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            DetailTabPicker(selection: $vm.activeTab)
        }
        .task(id: vm.selectedID) {
            if let id = vm.selectedID {
                await vm.loadSandboxDetails(id, client: client)
            }
        }
    }

    private func infoTab(_ sandbox: SandboxViewModel) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                InfoRow(label: "ID", value: sandbox.shortID)
                InfoRow(label: "Status", value: sandbox.state.label)
                InfoRow(
                    label: "IP Address",
                    value: sandbox.ipAddress.isEmpty ? "—" : sandbox.ipAddress)
                InfoRow(label: "CPU", value: sandbox.cpuDisplay)
                InfoRow(label: "Memory", value: sandbox.memoryDisplay)
                InfoRow(label: "Created", value: sandbox.createdAgo)
                if let readyAt = sandbox.readyAt {
                    InfoRow(label: "Ready", value: relativeTime(from: readyAt))
                }
                if let lastExitedAt = sandbox.lastExitedAt {
                    InfoRow(label: "Last Exited", value: relativeTime(from: lastExitedAt))
                }
                if let status = sandbox.lastExitStatus {
                    switch status {
                    case .code(let code):
                        InfoRow(label: "Exit Code", value: "\(code)")
                    case .signal(let signal):
                        InfoRow(label: "Exit Signal", value: "\(signal)")
                    }
                }
                if !sandbox.error.isEmpty {
                    InfoRow(label: "Error", value: sandbox.error)
                }
                if !sandbox.labels.isEmpty {
                    InfoRow(
                        label: "Labels",
                        value: sandbox.labels.map { "\($0.key)=\($0.value)" }
                            .sorted()
                            .joined(separator: ", ")
                    )
                }
            }
            .infoSectionStyle()
            .padding(16)
        }
    }

    private func tabUnavailable(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
        }
    }
}
