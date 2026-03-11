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
    @State private var useDockerInit = false

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("New Container")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
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
                    TextField("Command", text: $command)
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
                    Toggle(isOn: $useDockerInit) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Use docker-init")
                            Text("Run the container payload under a docker-init process. (--init)")
                                .font(.system(size: 11))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            // Footer buttons
            HStack {
                Button("?") {}
                    .buttonStyle(.plain)
                    .frame(width: 24, height: 24)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    // TODO: create container
                    dismiss()
                }

                Button("Create & Start") {
                    // TODO: create & start container
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .overlay(alignment: .top) { Divider() }
        }
        .frame(width: 480, height: 560)
    }
}
