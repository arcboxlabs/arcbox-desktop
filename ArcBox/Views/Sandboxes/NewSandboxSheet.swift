import ArcBoxClient
import SwiftUI

/// Network mode options for sandbox creation
enum SandboxNetworkMode: String, CaseIterable, Identifiable {
    case enabled
    case none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .enabled: "Enabled (default)"
        case .none: "None"
        }
    }

    var protobufValue: Arcbox_Sandbox_V1_NetworkMode {
        switch self {
        case .enabled: .enabled
        case .none: .none
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
    @State private var errorMessage: String?

    // Count
    @State private var count: Int = 1

    // What boots inside the sandbox, in `CreateSandboxRequest.template` form.
    // Empty selects the daemon's built-in minimal template.
    @State private var templateRef = ""

    // Resources. Zero means "send no limits", which inherits the catalog
    // template's defaults where it has any, and the daemon's otherwise.
    @State private var vcpus: Int = 0
    @State private var memoryMiB: Int = 0

    // Workload
    @State private var command = ""
    @State private var workingDir = ""
    @State private var user = ""

    // Network
    @State private var networkMode: SandboxNetworkMode = .enabled

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
                            .frame(width: AppMetrics.sheetCloseButton, height: AppMetrics.sheetCloseButton)
                    }
                )
                .buttonStyle(.plain)
                .disabled(isCreating)
            }
            .padding(.horizontal, 16)
            .frame(height: AppMetrics.sheetTitleBarHeight)
            .overlay(alignment: .bottom) { Divider() }

            // Scrollable form
            Form {
                Section {
                    Stepper("Count: \(count)", value: $count, in: 1...100)
                }

                Section {
                    Picker("Source", selection: $templateRef) {
                        Text("Built-in minimal").tag("")
                        if !vm.addressableTemplates.isEmpty {
                            Section("Templates") {
                                ForEach(vm.addressableTemplates) { template in
                                    Text(templateLabel(template)).tag(template.reference)
                                }
                            }
                        }
                        if !availableImages.isEmpty {
                            Section("Docker images") {
                                ForEach(availableImages, id: \.self) { name in
                                    Text(name).tag("docker:\(name)")
                                }
                            }
                        }
                    }
                } header: {
                    Text("Source")
                } footer: {
                    // A failed catalog load otherwise reads as a catalog with
                    // no templates in it.
                    if case .failed(let message) = vm.templatesLoadState {
                        Text("Templates unavailable: \(message)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let selectedTemplate {
                        Text(templateSummary(selectedTemplate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Stepper(
                        "vCPUs: \(vcpus == 0 ? defaultsLabel : "\(vcpus)")",
                        value: $vcpus, in: 0...16)
                    Stepper(
                        "Memory: \(memoryMiB == 0 ? defaultsLabel : "\(memoryMiB) MiB")",
                        value: $memoryMiB, in: 0...16384, step: 128)
                } header: {
                    Text("Resources")
                } footer: {
                    // The daemon reads a set `limits` as replacing the
                    // template's wholesale, so a zero subfield inside it falls
                    // back to the daemon default rather than the template's.
                    if selectedTemplate != nil, (vcpus == 0) != (memoryMiB == 0) {
                        Text("Setting one resource drops the template's default for the other.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Workload") {
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("Command", text: $command, prompt: Text(commandPrompt))
                        Text(ArgumentList.inputHelp)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
            .disabled(isCreating)

            // Footer buttons
            HStack {
                SheetErrorMessage(message: errorMessage)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isCreating)

                Button("Create") {
                    let requestedCount = count
                    isCreating = true
                    errorMessage = nil
                    Task {
                        let createdCount = await createSandboxes(count: requestedCount)
                        isCreating = false
                        if createdCount == requestedCount {
                            dismiss()
                        } else {
                            count = requestedCount - createdCount
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isCreating)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .overlay(alignment: .top) { Divider() }
        }
        .frame(width: AppMetrics.sheetWidth, height: 540)
        .interactiveDismissDisabled(isCreating)
        .task {
            vm.clearError()
            // Populate the source picker even when the Images view hasn't been
            // opened yet; loadImages no-ops if the Docker client isn't ready.
            await vm.loadTemplates(client: client)
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

    /// The catalog template backing the current selection, if the selection is
    /// one — `docker:` references and the built-in minimal template are not.
    private var selectedTemplate: SandboxTemplateViewModel? {
        vm.addressableTemplates.first { $0.reference == templateRef }
    }

    /// What an unset resource resolves to, which depends on the source.
    private var defaultsLabel: String {
        selectedTemplate == nil ? "Default" : "Template default"
    }

    private var commandPrompt: String {
        guard let selectedTemplate, !selectedTemplate.defaultCmd.isEmpty else {
            return "empty = boot to ready"
        }
        return "empty = \(selectedTemplate.defaultCmd.joined(separator: " "))"
    }

    private func templateLabel(_ template: SandboxTemplateViewModel) -> String {
        var label = "\(template.name):\(template.displayVersion)"
        if template.isWarm {
            label += " · warm"
        }
        return label
    }

    /// One line of what creating from this template implies but the form does
    /// not otherwise show: startup speed, and the ports it expects to serve.
    private func templateSummary(_ template: SandboxTemplateViewModel) -> String {
        var parts: [String] = []
        parts.append(
            template.isWarm
                ? "Restores from a pre-warmed snapshot." : "Cold boot from the built rootfs."
        )
        if !template.exposedPorts.isEmpty {
            let ports = template.exposedPorts.map(String.init).joined(separator: ", ")
            parts.append("Serves on \(ports).")
        }
        if template.isDraft {
            parts.append("Unpublished draft.")
        }
        return parts.joined(separator: " ")
    }

    private func createSandboxes(count requestedCount: Int) async -> Int {
        guard client != nil else {
            errorMessage = "ArcBox daemon is unavailable."
            return 0
        }

        vm.clearError()
        var spec = SandboxCreateSpec()
        spec.template = templateRef.trimmingCharacters(in: .whitespaces)
        spec.vcpus = UInt32(vcpus)
        spec.memoryMiB = UInt64(memoryMiB)
        do {
            spec.cmd = try ArgumentList.parse(command)
        } catch {
            errorMessage = "Invalid command: \(error.localizedDescription)"
            return 0
        }
        spec.workingDir = workingDir.trimmingCharacters(in: .whitespaces)
        spec.user = user.trimmingCharacters(in: .whitespaces)
        spec.networkMode = networkMode.protobufValue
        spec.ttlSeconds = UInt32(ttlSeconds)

        var createdCount = 0
        for _ in 0..<requestedCount {
            let id = await vm.createSandbox(spec, client: client)
            guard id != nil else {
                let failure = vm.lastError ?? "Sandbox creation failed."
                vm.clearError()
                if createdCount == 0 {
                    errorMessage = failure
                } else {
                    errorMessage =
                        "Created \(createdCount) of \(requestedCount) sandboxes. \(failure)"
                }
                return createdCount
            }
            createdCount += 1
        }
        await vm.loadSandboxes(client: client)
        return createdCount
    }
}
