import DockerClient
import SwiftUI

struct StorageSettingsView: View {
    @Environment(\.dockerClient) private var docker

    @State private var storageLocation = "default"
    @AppStorage("includeTimeMachine") private var includeTimeMachine = false
    @State private var hideOrbStackVolume = false

    // Reset state
    @State private var showResetDockerAlert = false
    @State private var showResetAllAlert = false
    @State private var isResetting = false
    @State private var resetResultMessage: String?

    private let locationOptions = [
        ("default", "Default"),
        ("custom", "Custom..."),
    ]

    private static var arcboxDataPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.arcbox"
    }

    var body: some View {
        Form {
            Section("Data") {
                LabeledContent("Location") {
                    Picker("", selection: $storageLocation) {
                        ForEach(locationOptions, id: \.0) { option in
                            Text(option.1).tag(option.0)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                    .disabled(true) // Requires backend support for data migration
                }

                Toggle("Include data in Time Machine backups", isOn: $includeTimeMachine)
                    .onChange(of: includeTimeMachine) { _, include in
                        updateTimeMachineExclusion(include: include)
                    }
                    .onAppear {
                        // Ensure exclusion state matches toggle on first appearance
                        updateTimeMachineExclusion(include: includeTimeMachine)
                    }
            }

            Section("Integration") {
                LabeledContent {
                    Toggle("", isOn: $hideOrbStackVolume)
                        .labelsHidden()
                        .disabled(true) // Requires backend support
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hide ArcBox volume from Finder & Desktop")
                        Text("This volume makes it easy to access files in containers and machines.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Danger Zone") {
                Button("Reset Docker Data") {
                    showResetDockerAlert = true
                }
                .disabled(isResetting || docker == nil)

                Button("Reset Kubernetes Cluster") {}
                    .disabled(true) // Requires K8s backend

                Button("Reset All Data") {
                    showResetAllAlert = true
                }
                .disabled(isResetting || docker == nil)

                if isResetting {
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
                Task { await resetDockerData() }
            }
        } message: {
            Text("This will remove all containers, images, volumes, and networks. This action cannot be undone.")
        }
        .alert("Reset All Data", isPresented: $showResetAllAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset Everything", role: .destructive) {
                Task { await resetAllData() }
            }
        } message: {
            Text("This will stop all containers and remove all Docker data including images, volumes, and networks. This action cannot be undone.")
        }
    }

    // MARK: - Time Machine

    private func updateTimeMachineExclusion(include: Bool) {
        let path = Self.arcboxDataPath
        Task.detached {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
            proc.arguments = include ? ["removeexclusion", path] : ["addexclusion", path]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            do {
                try proc.run()
                proc.waitUntilExit()
            } catch {
                // tmutil may require admin privileges — silently fail
            }
        }
    }

    // MARK: - Reset Operations

    private func resetDockerData() async {
        guard let docker else { return }
        isResetting = true
        resetResultMessage = nil

        do {
            // Stop all running containers first
            let listResponse = try await docker.api.ContainerList(query: .init(all: false))
            let running = try listResponse.ok.body.json
            var stopFailures: [String] = []
            for container in running {
                guard let id = container.Id else { continue }
                do {
                    _ = try await docker.api.ContainerStop(path: .init(id: id))
                } catch {
                    stopFailures.append(String(id.prefix(12)))
                }
            }

            // Prune everything: containers, images, volumes, networks
            var errors: [String] = []
            do { _ = try await docker.api.ContainerPrune() } catch { errors.append("containers") }
            do { _ = try await docker.api.ImagePrune() } catch { errors.append("images") }
            do { _ = try await docker.api.NetworkPrune() } catch { errors.append("networks") }
            do { _ = try await docker.api.VolumePrune() } catch { errors.append("volumes") }

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

        isResetting = false
    }

    private func resetAllData() async {
        // Reset Docker data first
        await resetDockerData()
        // Additional cleanup could be done here in the future (K8s, machines, etc.)
    }
}

#Preview {
    StorageSettingsView()
        .frame(width: 500, height: 600)
}
