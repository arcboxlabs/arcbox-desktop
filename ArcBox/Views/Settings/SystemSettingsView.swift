import ArcBoxClient
import SwiftUI

struct SystemSettingsView: View {
    // TODO: Implement resource controls (CPU/Memory) and environment
    // toggles (Admin) when backend gRPC APIs are available (ABXD-87)
    // @State private var memoryLimit: Double = 9
    // @State private var cpuLimit: Double = 17 // 17 = "None" (beyond max)
    // @State private var useAdminPrivileges = true
    @AppStorage("switchDockerContextAutomatically") private var switchContextAutomatically = true
    @AppStorage("pauseContainersWhileSleeping") private var pauseContainersWhileSleeping = true

    @Environment(\.arcboxClient) private var arcboxClient
    @Environment(DaemonManager.self) private var daemonManager
    @Environment(SystemVmBackendModel.self) private var backendModel

    // Picker-local state; the switch itself lives in SystemVmBackendModel so
    // an in-flight restart survives leaving this pane.
    @State private var selectedBackend: SystemVmBackend = .vz
    @State private var pendingBackend: SystemVmBackend?
    @State private var showBackendConfirm = false

    // private let memoryRange: ClosedRange<Double> = 1...14

    var body: some View {
        Form {
            // TODO: Implement resource controls when backend gRPC APIs are available (ABXD-87)
            // Section {
            //     Text("Resources are only used as needed. These are limits, not reservations. [Learn more](#)")
            //         .font(.callout)
            //         .foregroundStyle(.secondary)
            //
            //     LabeledContent {
            //         HStack {
            //             Text("1 GiB")
            //                 .font(.caption)
            //                 .foregroundStyle(.secondary)
            //             Slider(value: $memoryLimit, in: memoryRange, step: 1)
            //             Text("14 GiB")
            //                 .font(.caption)
            //                 .foregroundStyle(.secondary)
            //         }
            //     } label: {
            //         VStack(alignment: .leading, spacing: 2) {
            //             Text("Memory limit")
            //             Text("\(Int(memoryLimit)) GiB")
            //                 .font(.caption)
            //                 .foregroundStyle(.secondary)
            //         }
            //     }
            //
            //     LabeledContent {
            //         HStack {
            //             Text("100%")
            //                 .font(.caption)
            //                 .foregroundStyle(.secondary)
            //             Slider(value: $cpuLimit, in: 1...17, step: 1)
            //             Text("None")
            //                 .font(.caption)
            //                 .foregroundStyle(.secondary)
            //         }
            //     } label: {
            //         VStack(alignment: .leading, spacing: 2) {
            //             Text("CPU limit")
            //             Text(cpuLimitLabel)
            //                 .font(.caption)
            //                 .foregroundStyle(.secondary)
            //         }
            //     }
            // } header: {
            //     Text("Resources")
            // }

            Section("Environment") {
                // TODO: Implement admin privileges toggle (ABXD-87)
                // LabeledContent {
                //     Toggle("", isOn: $useAdminPrivileges)
                //         .labelsHidden()
                // } label: {
                //     VStack(alignment: .leading, spacing: 2) {
                //         Text("Use admin privileges for enhanced features")
                //         Text("This can improve performance and compatibility. [Learn more](#)")
                //             .font(.caption)
                //             .foregroundStyle(.secondary)
                //     }
                // }

                // TODO: Implement Kubernetes context auto-switch (ABXD-86)
                Toggle("Switch Docker & Kubernetes context automatically", isOn: $switchContextAutomatically)
                    .onChange(of: switchContextAutomatically) { _, newValue in
                        if newValue {
                            DockerContextManager.switchToArcBox()
                        } else {
                            DockerContextManager.restorePreviousContext()
                        }
                    }
            }

            Section {
                LabeledContent {
                    Picker("Virtual machine backend", selection: $selectedBackend) {
                        ForEach(SystemVmBackend.allCases) { backend in
                            Text(backend.label).tag(backend)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(
                        !daemonManager.state.isRunning || backendModel.currentBackend == nil
                            || backendModel.isSwitching)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Virtual machine backend")
                        Text(Self.backendCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if backendModel.isSwitching {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Switching backend and restarting the System VM…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let backendError = backendModel.lastError {
                    Text(backendError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                LabeledContent {
                    Toggle("", isOn: $pauseContainersWhileSleeping)
                        .labelsHidden()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pause containers while Mac is sleeping")
                        Text("Improves battery life. Only disable if you need to run background services.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Compatibility")
                    Text("Don't change these unless you run into issues.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            // TODO: Implement Apply and Restart (ABXD-87)
            // Section {
            //     HStack {
            //         Spacer()
            //         Button("Apply and Restart") {}
            //             .disabled(true)
            //         Spacer()
            //     }
            // }
            // .listRowBackground(Color.clear)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        // Keyed on client availability too: at startup the daemon can report
        // running before the injected client exists, and the load must re-run
        // once it does.
        .task(id: daemonManager.state.isRunning && arcboxClient != nil) {
            await backendModel.load(client: daemonManager.state.isRunning ? arcboxClient : nil)
            syncBackendSelection()
        }
        .onChange(of: backendModel.currentBackend) {
            syncBackendSelection()
        }
        .onChange(of: backendModel.isSwitching) { _, switching in
            // On completion, re-sync even when the backend value didn't change
            // (a failed switch re-reads the same backend it started with).
            if !switching {
                syncBackendSelection()
            }
        }
        .onChange(of: selectedBackend) { _, newValue in
            guard !backendModel.isSwitching, let current = backendModel.currentBackend,
                newValue != current
            else {
                return
            }
            pendingBackend = newValue
            showBackendConfirm = true
        }
        .alert("Switch System VM Backend", isPresented: $showBackendConfirm) {
            Button("Cancel", role: .cancel) { revertBackendSelection() }
            Button("Switch and Restart", role: .destructive) {
                if let pendingBackend {
                    backendModel.beginSwitch(to: pendingBackend, client: arcboxClient)
                }
                pendingBackend = nil
            }
        } message: {
            Text(
                "Switching the backend restarts the System VM and stops all running containers. Images and container data are preserved."
            )
        }
    }

    // MARK: - System VM Backend

    private static let backendCaption =
        "Intel (amd64) code runs via Rosetta on Virtualization.framework, or via FEX on Hypervisor.framework. Switching restarts the System VM."

    private func syncBackendSelection() {
        if let current = backendModel.currentBackend {
            selectedBackend = current
        }
    }

    private func revertBackendSelection() {
        pendingBackend = nil
        syncBackendSelection()
    }

    // TODO: Uncomment when CPU limit slider is enabled (ABXD-87)
    // private var cpuLimitLabel: String {
    //     if cpuLimit >= 17 {
    //         return "None"
    //     }
    //     return "\(Int(cpuLimit * 100 / 16))%"
    // }
}

#Preview {
    SystemSettingsView()
        .environment(DaemonManager())
        .environment(SystemVmBackendModel())
        .frame(width: 500, height: 600)
}
