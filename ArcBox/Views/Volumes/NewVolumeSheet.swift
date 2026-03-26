import AppKit
import DockerClient
import SwiftUI
import UniformTypeIdentifiers

/// New volume dialog presented as a sheet
struct NewVolumeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(VolumesViewModel.self) private var vm
    @Environment(\.dockerClient) private var docker

    @State private var isCreating = false
    @State private var name = ""

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            VStack(alignment: .leading, spacing: 4) {
                Text("New Volume")
                    .font(.system(size: 13, weight: .semibold))
                Text("Volumes are for sharing data between containers. Unlike bind mounts, they are stored on a native Linux file system, making them faster and more reliable.")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Divider() }

            // Form
            Form {
                Section {
                    TextField("Name", text: $name)
                }
            }
            .formStyle(.grouped)

            // Footer buttons
            HStack {
                Button("?") {}
                    .buttonStyle(.plain)
                    .frame(width: 24, height: 24)

                Button("Import...") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [UTType(filenameExtension: "tar")!, .gzip]
                    panel.allowsMultipleSelection = false
                    panel.canChooseDirectories = false
                    guard panel.runModal() == .OK, let url = panel.url else { return }
                    isCreating = true
                    Task {
                        await vm.importVolume(name: name, tarURL: url, docker: docker)
                        isCreating = false
                        dismiss()
                    }
                }
                .disabled(isCreating)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    isCreating = true
                    Task {
                        await vm.createVolume(name: name, docker: docker)
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
        .frame(width: 480, height: 240)
    }
}
