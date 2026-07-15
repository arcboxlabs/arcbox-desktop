import FleetControlClient
import SwiftUI

private enum FleetVMModeChoice: String, CaseIterable, Identifiable {
    case automatic = "Automatic"
    case enabled = "Enabled"
    case disabled = "Disabled"

    var id: String { rawValue }

    var value: FleetVmMode {
        switch self {
        case .automatic: .auto
        case .enabled: .enabled
        case .disabled: .disabled
        }
    }

    init?(_ value: FleetVmMode) {
        switch value {
        case .auto: self = .automatic
        case .enabled: self = .enabled
        case .disabled: self = .disabled
        case .unspecified, .unrecognized: return nil
        }
    }
}

private struct FleetVMSettingsDraft: Equatable {
    var mode: FleetVMModeChoice?
    var image = ""

    init(settings: FleetAgentSettings? = nil) {
        mode = settings?.vmMode.flatMap { FleetVMModeChoice($0.target) }
        image = settings?.macosRunnerImage?.target ?? ""
    }
}

struct FleetSettingsView: View {
    @Environment(FleetViewModel.self) private var fleet

    @State private var draft = FleetVMSettingsDraft()

    var body: some View {
        Form {
            agentSection
            vmSettingsContent
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear {
            syncDraft(from: fleet.settings)
        }
        .onChange(of: fleet.settings) { oldSettings, newSettings in
            guard draft == FleetVMSettingsDraft(settings: oldSettings) else { return }
            syncDraft(from: newSettings)
        }
    }

    private var agentSection: some View {
        Section("Fleet Agent") {
            LabeledContent("Version", value: fleet.agentInfo?.agentVersion ?? "Not connected")
            LabeledContent("VM backend") {
                Label(
                    fleet.isVMBackendActive ? "Active" : "Inactive",
                    systemImage: fleet.isVMBackendActive ? "checkmark.circle.fill" : "circle"
                )
                .foregroundStyle(fleet.isVMBackendActive ? .green : .secondary)
            }
        }
    }

    @ViewBuilder
    private var vmSettingsContent: some View {
        switch fleet.vmSettingsAvailability {
        case .loading:
            Section {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading Fleet VM settings…")
                        .foregroundStyle(.secondary)
                }
            }
        case .unavailable(let message):
            messageSection(
                title: "Fleet Agent Unavailable",
                message: message,
                systemImage: "exclamationmark.triangle"
            )
        case .unsupported:
            messageSection(
                title: "Fleet Agent Update Required",
                message: "The connected Fleet Agent does not support VM settings.",
                systemImage: "arrow.down.circle"
            )
        case .missingSettings:
            messageSection(
                title: "VM Settings Not Reported",
                message: "The Fleet Agent advertised VM settings but did not return their values.",
                systemImage: "exclamationmark.triangle"
            )
        case .available:
            configurationSection
            imagePreparationSection
        }
    }

    private var configurationSection: some View {
        Section {
            if let vmMode = fleet.settings?.vmMode {
                LabeledContent {
                    if draft.mode != nil {
                        Picker("VM isolation", selection: modeBinding) {
                            ForEach(FleetVMModeChoice.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    } else {
                        Text(Self.label(for: vmMode.target))
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("VM isolation")
                        Text("Current: \(Self.label(for: vmMode.current))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let image = fleet.settings?.macosRunnerImage {
                LabeledContent {
                    TextField("Image reference", text: $draft.image)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("macOS runner image")
                        Text("Current: \(Self.currentImageLabel(image.current))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Save") {
                    saveSettings()
                }
                .disabled(!canSave)
            }

            if let lastError = fleet.lastError {
                Label(lastError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if fleet.requiresAgentRestartForVM {
                Label {
                    Text(
                        "The daemon-managed Fleet Agent must restart before this VM configuration becomes active. ArcBox Desktop will not restart it."
                    )
                } icon: {
                    Image(systemName: "arrow.clockwise.circle")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } header: {
            Text("macOS Runner VMs")
        } footer: {
            Text(
                "Fleet Agent provisions disposable runner VMs through arcbox-daemon. Desktop only updates settings and communicates with the Agent."
            )
        }
    }

    private var imagePreparationSection: some View {
        Section("Image Preparation") {
            if fleet.settings?.macosRunnerImage?.isPending == true {
                Label("The target image must be prepared before it can run jobs.", systemImage: "shippingbox")
                    .foregroundStyle(.secondary)
            }

            preparationStatus

            HStack {
                Spacer()
                Button("Prepare Image") {
                    fleet.beginMacOSRunnerImagePreparation()
                }
                .disabled(!fleet.canBeginMacOSRunnerImagePreparation)
            }

            if !fleet.supportsMacOSImagePreparation {
                Text("The connected Fleet Agent cannot prepare macOS runner images.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var preparationStatus: some View {
        switch fleet.imagePreparationState {
        case .idle:
            EmptyView()
        case .preparing(let progress):
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: progress.fraction)
                Text(progress.displayDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .completed(let reference):
            Label("Runner image \(reference) prepared.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    private var modeBinding: Binding<FleetVMModeChoice> {
        Binding(
            get: { draft.mode ?? .automatic },
            set: { draft.mode = $0 }
        )
    }

    private var canSave: Bool {
        guard fleet.vmSettingsAvailability == .available,
            !fleet.isPerformingAction,
            !fleet.imagePreparationState.isPreparing,
            !draft.image.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return false
        }
        return draft != FleetVMSettingsDraft(settings: fleet.settings)
    }

    private func saveSettings() {
        guard let settings = fleet.settings else { return }

        let image = draft.image.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageUpdate = image == settings.macosRunnerImage?.target ? nil : image
        let modeValue = draft.mode?.value
        let modeUpdate = modeValue == settings.vmMode?.target ? nil : modeValue

        Task {
            let saved = await fleet.updateSettings(
                macosRunnerImage: imageUpdate,
                vmMode: modeUpdate
            )
            if saved {
                syncDraft(from: fleet.settings)
            }
        }
    }

    private func syncDraft(from settings: FleetAgentSettings?) {
        draft = FleetVMSettingsDraft(settings: settings)
    }

    @ViewBuilder
    private func messageSection(
        title: String,
        message: String,
        systemImage: String
    ) -> some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: systemImage)
            }
        }
    }

    private static func label(for mode: FleetVmMode) -> String {
        switch mode {
        case .auto: "Automatic"
        case .enabled: "Enabled"
        case .disabled: "Disabled"
        case .unspecified: "Unspecified"
        case .unrecognized(let value): "Unknown (\(value))"
        }
    }

    private static func currentImageLabel(_ reference: String) -> String {
        reference.isEmpty ? "Not prepared" : reference
    }

}

#Preview {
    let fleet = FleetViewModel()
    fleet.loadState = .ready
    fleet.agentInfo = FleetAgentInfo(
        agentVersion: "0.5.0",
        apiVersion: 1,
        features: ["vm-settings", "macos-image-prepare"]
    )
    fleet.settings = FleetAgentSettings(
        macosRunnerImage: FleetSetting(current: "tahoe-base", target: "tahoe-base"),
        vmMode: FleetSetting(current: .auto, target: .auto)
    )

    return FleetSettingsView()
        .environment(fleet)
        .frame(width: 520, height: 580)
}
