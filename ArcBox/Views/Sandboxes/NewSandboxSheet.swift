import ArcBoxClient
import SwiftUI

/// Network mode options for sandbox creation
enum SandboxNetworkMode: String, CaseIterable, Identifiable {
    case tap
    case none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tap: "TAP (default)"
        case .none: "None"
        }
    }
}

/// New sandbox dialog presented as a sheet
struct NewSandboxSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SandboxesViewModel.self) private var vm
    @Environment(\.arcboxClient) private var client
    @Environment(\.dockerClient) private var docker
    @Environment(ImagesViewModel.self) private var imagesVM

    @State private var isCreating = false

    // Count
    @State private var count: Int = 1

    // Image — empty string means "use the daemon default rootfs"
    @State private var image = ""

    // Resources
    @State private var vcpus: Int = 1
    @State private var memoryMiB: Int = 512

    // Workload
    @State private var command = ""
    @State private var workingDir = ""
    @State private var user = ""

    // Network
    @State private var networkMode: SandboxNetworkMode = .tap

    // Lifecycle
    @State private var ttlSeconds: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("New Sandbox")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(
                    action: { dismiss() },
                    label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(width: 24, height: 24)
                    }
                )
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .overlay(alignment: .bottom) { Divider() }

            // Scrollable form
            Form {
                Section {
                    Stepper("Count: \(count)", value: $count, in: 1...100)
                }

                Section("Image") {
                    Picker("Image", selection: $image) {
                        Text("Default rootfs").tag("")
                        ForEach(availableImages, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                }

                Section("Resources") {
                    Stepper("vCPUs: \(vcpus)", value: $vcpus, in: 1...16)
                    Stepper(
                        "Memory: \(memoryMiB) MiB", value: $memoryMiB, in: 128...16384, step: 128)
                }

                Section("Workload") {
                    TextField("Command", text: $command, prompt: Text("empty = boot to ready"))
                    TextField("Working directory", text: $workingDir)
                    TextField("User", text: $user, prompt: Text("e.g. root"))
                }

                Section("Network") {
                    Picker("Mode", selection: $networkMode) {
                        ForEach(SandboxNetworkMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                }

                Section("Lifecycle") {
                    Stepper(
                        "TTL: \(ttlSeconds == 0 ? "No limit" : "\(ttlSeconds)s")",
                        value: $ttlSeconds, in: 0...86400, step: 60)
                }
            }
            .formStyle(.grouped)

            // Footer buttons
            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    isCreating = true
                    Task {
                        await createSandboxes()
                        isCreating = false
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isCreating)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .overlay(alignment: .top) { Divider() }
        }
        .frame(width: 480, height: 540)
        .task {
            // Populate the image picker even when the Images view hasn't been
            // opened yet; loadImages no-ops if the Docker client isn't ready.
            await imagesVM.loadImages(docker: docker, iconClient: client)
        }
    }

    /// Unique image names from Docker, excluding untagged entries.
    private var availableImages: [String] {
        Array(
            Set(
                imagesVM.images
                    .map(\.fullName)
                    .filter { !$0.hasPrefix("<none>") }
            )
        ).sorted()
    }

    private func createSandboxes() async {
        var spec = SandboxCreateSpec()
        spec.image = image.trimmingCharacters(in: .whitespaces)
        spec.vcpus = UInt32(vcpus)
        spec.memoryMiB = UInt64(memoryMiB)
        let trimmedCommand = command.trimmingCharacters(in: .whitespaces)
        spec.cmd = trimmedCommand.isEmpty ? [] : trimmedCommand.split(separator: " ").map(String.init)
        spec.workingDir = workingDir.trimmingCharacters(in: .whitespaces)
        spec.user = user.trimmingCharacters(in: .whitespaces)
        spec.networkMode = networkMode.rawValue
        spec.ttlSeconds = UInt32(ttlSeconds)

        for _ in 0..<count {
            let id = await vm.createSandbox(spec, client: client, docker: docker)
            if id == nil { break }
        }
    }
}
