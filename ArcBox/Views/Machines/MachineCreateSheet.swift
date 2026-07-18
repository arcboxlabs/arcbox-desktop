import SwiftUI

/// New machine dialog presented as a sheet.
struct MachineCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MachinesViewModel.self) private var vm
    @Environment(\.arcboxClient) private var client

    @State private var isCreating = false
    @State private var errorMessage: String?

    @State private var name = ""
    @State private var distros: [MachineDistroOption] = MachineImageCatalog.fallback
    @State private var selectedDistro = "ubuntu"
    @State private var selectedRelease = ""

    // Resources (daemon defaults: 4 GiB memory, 50 GB disk)
    @State private var cpus: Int = 4
    @State private var memoryGiB: Int = 4
    @State private var diskGiB: Int = 50

    private var releases: [String] {
        distros.first { $0.distro == selectedDistro }?.releases ?? []
    }

    private var canCreate: Bool {
        !isCreating && !trimmedName.isEmpty && !selectedRelease.isEmpty
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("New Machine")
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

            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("my-machine"))
                        .disabled(isCreating)
                }

                Section("Image") {
                    Picker("Distribution", selection: $selectedDistro) {
                        ForEach(distros) { option in
                            Text(option.displayName).tag(option.distro)
                        }
                    }
                    Picker("Release", selection: $selectedRelease) {
                        ForEach(releases, id: \.self) { release in
                            Text(release).tag(release)
                        }
                    }
                }
                .disabled(isCreating)

                Section("Resources") {
                    Stepper("CPUs: \(cpus)", value: $cpus, in: 1...16)
                    Stepper("Memory: \(memoryGiB) GiB", value: $memoryGiB, in: 1...64)
                    Stepper("Disk: \(diskGiB) GB", value: $diskGiB, in: 10...500, step: 10)
                }
                .disabled(isCreating)

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            // Footer
            HStack {
                if isCreating {
                    ProgressView()
                        .controlSize(.small)
                    Text("Downloading image and starting…")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textSecondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .disabled(isCreating)
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
            }
            .padding(16)
        }
        .frame(width: 440, height: 460)
        .task {
            distros = await MachineImageCatalog.fetch()
            normalizeSelection()
        }
        .onChange(of: selectedDistro) {
            normalizeSelection()
        }
    }

    /// Keep the release selection valid for the selected distro.
    private func normalizeSelection() {
        if !distros.contains(where: { $0.distro == selectedDistro }) {
            selectedDistro = distros.first?.distro ?? ""
        }
        if !releases.contains(selectedRelease) {
            selectedRelease = releases.first ?? ""
        }
    }

    private func create() {
        guard let client else { return }
        var spec = MachineCreateSpec()
        spec.name = trimmedName
        spec.distro = selectedDistro
        spec.version = selectedRelease
        spec.cpus = UInt32(cpus)
        spec.memoryGiB = UInt64(memoryGiB)
        spec.diskGiB = UInt64(diskGiB)

        isCreating = true
        errorMessage = nil
        Task {
            let id = await vm.createMachine(spec, client: client)
            isCreating = false
            if let id {
                vm.selectMachine(id)
                dismiss()
            } else {
                // Surface the failure inside the sheet; the toast is hidden
                // behind it.
                errorMessage = vm.lastError
            }
        }
    }
}
