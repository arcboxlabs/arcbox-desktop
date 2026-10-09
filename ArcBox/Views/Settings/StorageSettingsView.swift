import ArcBoxClient
import DockerClient
import SwiftUI

struct StorageSettingsView: View {
    @Environment(\.dockerClient) private var docker
    @Environment(DaemonManager.self) private var daemon
    @Environment(RuntimeStorageRecoveryModel.self) private var recovery

    @AppStorage("includeTimeMachine") private var includeTimeMachine = false
    /// Tracks whether the Time Machine exclusion has been applied this session, to avoid
    /// spawning tmutil on every onAppear.
    @State private var timeMachineExclusionApplied = false
    @State private var isUpdatingTimeMachine = false
    @State private var timeMachineErrorMessage: String?
    @State private var failedTimeMachineValue: Bool?
    // Reset state
    @State private var showResetDockerAlert = false
    @State private var resetResultMessage: String?

    private static var arcboxDataPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let profile = Bundle.main.object(forInfoDictionaryKey: "ArcBoxProfile") as? String
        let dataDir = profile?.caseInsensitiveCompare("development") == .orderedSame ? ".arcbox-dev" : ".arcbox"
        return "\(home)/\(dataDir)"
    }

    var body: some View {
        Form {
            RuntimeStorageDetails()
            RuntimeStorageRecoverySection()

            Section("Data") {
                Toggle(
                    "Include data in Time Machine backups",
                    isOn: Binding(
                        get: { includeTimeMachine },
                        set: { updateTimeMachineExclusion(include: $0) }
                    )
                )
                .disabled(isUpdatingTimeMachine)
                .onAppear {
                    guard !timeMachineExclusionApplied else { return }
                    timeMachineExclusionApplied = true
                    updateTimeMachineExclusion(include: includeTimeMachine)
                }

                if isUpdatingTimeMachine {
                    ProgressView()
                        .controlSize(.small)
                }

                if let timeMachineErrorMessage {
                    Label(timeMachineErrorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                    if let failedTimeMachineValue {
                        Button("Try Again") {
                            updateTimeMachineExclusion(include: failedTimeMachineValue)
                        }
                        .font(.caption)
                    }
                }
            }

            Section("Danger Zone") {
                Button("Reset Docker Data") {
                    showResetDockerAlert = true
                }
                .disabled(
                    recovery.isResettingDockerData || docker == nil || daemon.storageWriteFailureMessage != nil
                        || recovery.mayBeRunning)

                Text("Reset removes Docker resources. Reset does not repair runtime storage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if recovery.isResettingDockerData {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Resetting…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let message = resetResultMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .alert("Reset Docker Data", isPresented: $showResetDockerAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                recovery.startDockerDataReset { await resetDockerData() }
            }
            .disabled(recovery.isResettingDockerData || recovery.mayBeRunning)
        } message: {
            Text("This will remove all containers, images, volumes, and networks. This action cannot be undone.")
        }
    }

    // MARK: - Time Machine

    private func updateTimeMachineExclusion(include: Bool) {
        let path = Self.arcboxDataPath
        timeMachineErrorMessage = nil
        failedTimeMachineValue = nil
        isUpdatingTimeMachine = true
        Task {
            do {
                try await TimeMachineExclusion().update(path, includeInBackups: include)
                includeTimeMachine = include
            } catch {
                failedTimeMachineValue = include
                timeMachineErrorMessage =
                    "The Time Machine setting was not changed: \(error.localizedDescription) "
                    + "Check Full Disk Access in System Settings > Privacy & Security, then try again."
            }
            isUpdatingTimeMachine = false
        }
    }

    // MARK: - Reset Operations

    private func resetDockerData() async {
        if let reason = daemon.storageWriteFailureMessage {
            resetResultMessage = reason
            return
        }
        guard let docker else { return }
        resetResultMessage = nil

        do {
            // Stop all running containers first
            let listResponse = try await docker.api.ContainerList(query: .init(all: false))
            let running = try listResponse.ok.body.json
            var stopFailures: [String] = []
            for container in running {
                guard let id = container.Id else { continue }
                do {
                    let response = try await docker.api.ContainerStop(path: .init(id: id))
                    if response.stopFailureMessage != nil {
                        stopFailures.append(String(id.prefix(12)))
                    }
                } catch {
                    stopFailures.append(String(id.prefix(12)))
                }
            }

            // Prune everything: containers, images, volumes, networks
            var errors: [String] = []
            do {
                _ = try await docker.api.ContainerPrune().ok
            } catch {
                errors.append("containers")
            }
            do {
                _ = try await docker.api.ImagePrune(
                    query: .init(filters: #"{"dangling":["false"]}"#)
                ).ok
            } catch {
                errors.append("images")
            }
            do {
                _ = try await docker.api.NetworkPrune().ok
            } catch {
                errors.append("networks")
            }
            do {
                _ = try await docker.api.VolumePrune(
                    query: .init(filters: #"{"all":["true"]}"#)
                ).ok
            } catch {
                errors.append("volumes")
            }

            if stopFailures.isEmpty && errors.isEmpty {
                resetResultMessage = "Docker data has been reset successfully."
            } else {
                var issues: [String] = []
                if !stopFailures.isEmpty {
                    issues.append("could not stop containers: \(stopFailures.joined(separator: ", "))")
                }
                if !errors.isEmpty {
                    issues.append("could not prune \(errors.joined(separator: ", "))")
                }
                resetResultMessage = "Reset partially failed: \(issues.joined(separator: "; "))."
            }
            NotificationCenter.default.post(name: .dockerDataChanged, object: nil)
        } catch {
            resetResultMessage = "Reset failed: \(error.localizedDescription)"
        }
    }
}
