import DockerClient
import SwiftUI

/// Restart policy options
enum RestartPolicy: String, CaseIterable, Identifiable {
    case no = "no"
    case always = "always"
    case onFailure = "on-failure"
    case unlessStopped = "unless-stopped"

    var id: String { rawValue }
}

/// Platform options
enum ContainerPlatform: String, CaseIterable, Identifiable {
    case auto = "auto"
    case linuxAmd64 = "linux/amd64"
    case linuxArm64 = "linux/arm64"

    var id: String { rawValue }
}

/// New container dialog presented as a sheet
struct NewContainerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ContainersViewModel.self) private var vm
    @Environment(\.dockerClient) private var docker

    @State private var isCreating = false
    @State private var pendingStartID: String?
    /// Copied out of the view model rather than observed: the list behind this sheet has an
    /// `.errorToast` on the same `lastError`, and the toast clears it after four seconds even
    /// though it is hidden — which would wipe this message while the form is still open.
    @State private var errorMessage: String?

    // Basic settings
    @State private var image = ""
    @State private var platform: ContainerPlatform = .auto
    @State private var name = ""
    @State private var removeAfterStop = false
    @State private var restartPolicy: RestartPolicy = .no

    // Payload
    @State private var command = ""
    @State private var entrypoint = ""
    @State private var workdir = ""

    // Advanced
    @State private var privileged = false
    @State private var readOnly = false

    private var imageIsEmpty: Bool {
        image.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var createOptions: ContainerCreateOptions {
        ContainerCreateOptions(
            image: image,
            name: name,
            platform: platform == .auto ? nil : platform.rawValue,
            command: command,
            entrypoint: entrypoint,
            workingDir: workdir,
            autoRemove: removeAfterStop,
            restartPolicy: restartPolicy.rawValue,
            privileged: privileged,
            readOnlyRootfs: readOnly,
            dockerInit: false
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("New Container")
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
                // Basic settings
                Section {
                    TextField("Image", text: $image, prompt: Text("e.g. alpine:latest"))
                    Picker("Platform", selection: $platform) {
                        ForEach(ContainerPlatform.allCases) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    TextField("Name", text: $name, prompt: Text("default"))
                    Toggle("Remove after stop", isOn: $removeAfterStop)
                    Picker("Restart policy", selection: $restartPolicy) {
                        ForEach(RestartPolicy.allCases) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                }

                // Payload section
                Section("Payload") {
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("Command", text: $command)
                        Text(ArgumentList.inputHelp)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    TextField("Entrypoint", text: $entrypoint)
                    TextField("Working directory", text: $workdir)
                }

                // Advanced section
                Section("Advanced") {
                    Toggle(isOn: $privileged) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Privileged")
                            Text("Allow access to privileged APIs and resources. (--privileged)")
                                .font(.system(size: 11))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                    Toggle(isOn: $readOnly) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Read-only")
                            Text("Mount the container's root filesystem as read-only. (--read-only)")
                                .font(.system(size: 11))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(isCreating || pendingStartID != nil)

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
                    errorMessage = nil
                    isCreating = true
                    Task {
                        let id = await vm.createContainer(
                            options: createOptions,
                            docker: docker
                        )
                        isCreating = false
                        if id != nil { dismiss() } else { errorMessage = vm.lastError }
                    }
                }
                .disabled(isCreating || imageIsEmpty || pendingStartID != nil)

                Button(pendingStartID == nil ? "Create & Start" : "Retry Start") {
                    errorMessage = nil
                    isCreating = true
                    Task {
                        await createAndStart()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isCreating || (pendingStartID == nil && imageIsEmpty))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .overlay(alignment: .top) { Divider() }
        }
        .frame(width: AppMetrics.sheetWidth, height: 560)
        .interactiveDismissDisabled(isCreating)
    }

    private func createAndStart() async {
        let id: String
        if let pendingStartID {
            id = pendingStartID
        } else if let createdID = await vm.createContainer(
            options: createOptions,
            docker: docker
        ) {
            pendingStartID = createdID
            id = createdID
        } else {
            isCreating = false
            errorMessage = vm.lastError
            return
        }

        let started = await vm.startContainerDocker(id, docker: docker)
        isCreating = false
        if started {
            dismiss()
        } else {
            errorMessage = vm.lastError
        }
    }
}
