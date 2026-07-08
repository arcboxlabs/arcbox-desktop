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
                    if sandbox.state.isAcceptingCommands {
                        SandboxTerminalTab(sandboxID: sandbox.id)
                    } else {
                        tabUnavailable(
                            "Sandbox must be in ready or idle state for terminal access")
                    }
                case .files:
                    if sandbox.state.isActive {
                        SandboxFilesTab(sandbox: sandbox)
                    } else {
                        tabUnavailable("Sandbox must be alive for file transfer")
                    }
                case .ports:
                    if sandbox.state.isActive {
                        SandboxPortsTab(sandbox: sandbox)
                    } else {
                        tabUnavailable("Sandbox must be alive to expose ports")
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
            ToolbarItem(placement: .principal) {
                Picker("Tab", selection: $vm.activeTab) {
                    ForEach(SandboxDetailTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)
            }
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
                if sandbox.lastExitedAt != nil {
                    InfoRow(label: "Last Exit Code", value: "\(sandbox.lastExitCode)")
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
