import DockerClient
import SwiftUI

nonisolated private enum TimeMachineSettingError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let detail): detail
        }
    }
}

struct StorageSettingsView: View {
    @Environment(\.dockerClient) private var docker

    @AppStorage("includeTimeMachine") private var includeTimeMachine = false
    /// Tracks whether the Time Machine exclusion has been applied this session, to avoid
    /// spawning tmutil on every onAppear.
    @State private var timeMachineExclusionApplied = false
    @State private var isUpdatingTimeMachine = false
    @State private var timeMachineErrorMessage: String?
    @State private var failedTimeMachineValue: Bool?
    // Reset state
    @State private var showResetDockerAlert = false
    @State private var isResetting = false
    @State private var resetResultMessage: String?

    private static var arcboxDataPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let profile = Bundle.main.object(forInfoDictionaryKey: "ArcBoxProfile") as? String
        let dataDir = profile?.caseInsensitiveCompare("development") == .orderedSame ? ".arcbox-dev" : ".arcbox"
        return "\(home)/\(dataDir)"
    }

    var body: some View {
        Form {
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
    }

    // MARK: - Time Machine

    private func updateTimeMachineExclusion(include: Bool) {
        let path = Self.arcboxDataPath
        timeMachineErrorMessage = nil
        failedTimeMachineValue = nil
        isUpdatingTimeMachine = true
        Task {
            do {
                try await Self.setTimeMachineExclusion(include: include, path: path)
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

    nonisolated private static func setTimeMachineExclusion(include: Bool, path: String) async throws {
        try await Task.detached {
            let fileManager = FileManager.default
            if !fileManager.fileExists(atPath: path) {
                try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)
            }

            let process = Process()
            let errorPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
            process.arguments = include ? ["removeexclusion", path] : ["addexclusion", path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = errorPipe
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus != 0 else { return }

            let detail = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw TimeMachineSettingError.commandFailed(
                detail?.isEmpty == false
                    ? detail ?? ""
                    : "tmutil exited with status \(process.terminationStatus)."
            )
        }.value
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

        isResetting = false
    }
}
