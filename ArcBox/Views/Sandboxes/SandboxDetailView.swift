import ArcBoxClient
import SwiftUI

/// Column 3: sandbox detail with tab-based toolbar
struct SandboxDetailView: View {
    @Environment(SandboxesViewModel.self) private var vm
    @Environment(\.arcboxClient) private var client

    private func stateColor(_ state: SandboxState) -> Color {
        switch state {
        case .starting: AppColors.warning
        case .ready, .idle: AppColors.running
        case .running: AppColors.running
        case .stopping: AppColors.warning
        case .stopped: AppColors.stopped
        case .failed: AppColors.error
        case .removed, .unknown: AppColors.stopped
        }
    }

    var body: some View {
        @Bindable var vm = vm
        let sandbox = vm.selectedSandbox

        VStack(spacing: 0) {
            if let sandbox {
                switch vm.activeTab {
                case .info:
                    ScrollView {
                        VStack(spacing: 0) {
                            InfoRow(label: "ID", value: sandbox.shortID)
                            InfoRow(label: "Status", value: sandbox.state.label)
                            InfoRow(label: "IP Address", value: sandbox.ipAddress.isEmpty ? "—" : sandbox.ipAddress)
                            InfoRow(label: "CPU", value: sandbox.cpuDisplay)
                            InfoRow(label: "Memory", value: sandbox.memoryDisplay)
                            InfoRow(label: "Created", value: sandbox.createdAgo)
                            if let readyAt = sandbox.readyAt {
                                InfoRow(label: "Ready At", value: relativeTime(from: readyAt))
                            }
                            if sandbox.lastExitCode != 0 {
                                InfoRow(label: "Last Exit Code", value: "\(sandbox.lastExitCode)")
                            }
                            if !sandbox.error.isEmpty {
                                InfoRow(label: "Error", value: sandbox.error)
                            }
                            if !sandbox.labels.isEmpty {
                                InfoRow(
                                    label: "Labels",
                                    value: sandbox.labels.map { "\($0.key)=\($0.value)" }
                                        .joined(separator: ", ")
                                )
                            }
                        }
                        .infoSectionStyle()
                        .padding(16)
                    }
                case .terminal:
                    if sandbox.state.isAcceptingCommands {
                        SandboxTerminalTab(sandboxID: sandbox.id)
                    } else {
                        Spacer()
                        Text("Sandbox must be in ready or idle state for terminal access")
                            .foregroundStyle(AppColors.textSecondary)
                        Spacer()
                    }
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
                .frame(maxWidth: 200)
            }
        }
        .task(id: vm.selectedID) {
            if let id = vm.selectedID {
                await vm.loadSandboxDetails(id, client: client)
            }
        }
    }
}
