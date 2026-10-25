import RunnerAgentClient
import SwiftUI

private enum RunnerVMModeChoice: String, CaseIterable, Identifiable {
    case automatic = "Automatic"
    case enabled = "Enabled"
    case disabled = "Disabled"

    var id: String { rawValue }

    var value: RunnerVmMode {
        switch self {
        case .automatic: .auto
        case .enabled: .enabled
        case .disabled: .disabled
        }
    }

    init?(_ value: RunnerVmMode) {
        switch value {
        case .auto: self = .automatic
        case .enabled: self = .enabled
        case .disabled: self = .disabled
        case .unspecified, .unrecognized: return nil
        }
    }
}

private struct RunnerVMSettingsDraft: Equatable {
    var mode: RunnerVMModeChoice?
    var image = ""

    init(settings: RunnerAgentSettings? = nil) {
        mode = settings?.vmMode.flatMap { RunnerVMModeChoice($0.target) }
        image = settings?.macosRunnerImage?.target ?? ""
    }
}

struct RunnerSettingsView: View {
    @Environment(RunnerAgentViewModel.self) private var agent

    @State private var draft = RunnerVMSettingsDraft()

    var body: some View {
        Form {
            agentSection
            vmSettingsContent
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear {
            syncDraft(from: agent.settings)
        }
        .onChange(of: agent.settings) { oldSettings, newSettings in
            guard draft == RunnerVMSettingsDraft(settings: oldSettings) else { return }
            syncDraft(from: newSettings)
        }
    }

    private var agentSection: some View {
        Section("Runner Agent") {
            LabeledContent("Version", value: agent.agentInfo?.agentVersion ?? "Not connected")
            LabeledContent("VM backend") {
                Label(
                    agent.isVMBackendActive ? "Active" : "Inactive",
                    systemImage: agent.isVMBackendActive ? "checkmark.circle.fill" : "circle"
                )
                .foregroundStyle(agent.isVMBackendActive ? .green : .secondary)
            }
        }
    }

    @ViewBuilder
    private var vmSettingsContent: some View {
        switch agent.vmSettingsAvailability {
        case .loading:
            Section {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading runner VM settings…")
                        .foregroundStyle(.secondary)
                }
            }
        case .unavailable(let message):
            messageSection(
                title: "Runner Agent Unavailable",
                message: message,
                systemImage: "exclamationmark.triangle"
            )
        case .unsupported:
            messageSection(
                title: "Runner Agent Update Required",
                message: "The connected Runner Agent does not support VM settings.",
                systemImage: "arrow.down.circle"
            )
        case .missingSettings:
            messageSection(
                title: "VM Settings Not Reported",
                message: "The Runner Agent advertised VM settings but did not return their values.",
                systemImage: "exclamationmark.triangle"
            )
        case .available:
            configurationSection
            imagePreparationSection
        }
    }

    private var configurationSection: some View {
        Section {
            if let vmMode = agent.settings?.vmMode {
                LabeledContent {
                    if draft.mode != nil {
                        Picker("VM isolation", selection: modeBinding) {
                            ForEach(RunnerVMModeChoice.allCases) { mode in
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

            if let image = agent.settings?.macosRunnerImage {
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

            if let lastError = agent.lastError {
                Label(lastError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if agent.requiresAgentRestartForVM {
                Label {
                    Text(
                        "The daemon-managed Runner Agent must restart before this VM configuration becomes active. ArcBox Desktop will not restart it."
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
                "The Runner Agent provisions disposable runner VMs through arcbox-daemon. Desktop only updates settings and communicates with the Agent."
            )
        }
    }

    private var imagePreparationSection: some View {
        Section("Image Preparation") {
            if agent.settings?.macosRunnerImage?.isPending == true {
                Label("The target image must be prepared before it can run jobs.", systemImage: "shippingbox")
                    .foregroundStyle(.secondary)
            }

            preparationStatus

            HStack {
                Spacer()
                Button("Prepare Image") {
                    agent.beginMacOSRunnerImagePreparation()
                }
                .disabled(!agent.canBeginMacOSRunnerImagePreparation)
            }

            if !agent.supportsMacOSImagePreparation {
                Text("The connected Runner Agent cannot prepare macOS runner images.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var preparationStatus: some View {
        switch agent.imagePreparationState {
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

    private var modeBinding: Binding<RunnerVMModeChoice> {
        Binding(
            get: { draft.mode ?? .automatic },
            set: { draft.mode = $0 }
        )
    }

    private var canSave: Bool {
        guard agent.vmSettingsAvailability == .available,
            !agent.isPerformingAction,
            !agent.imagePreparationState.isPreparing,
            !draft.image.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return false
        }
        return draft != RunnerVMSettingsDraft(settings: agent.settings)
    }

    private func saveSettings() {
        guard let settings = agent.settings else { return }

        let image = draft.image.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageUpdate = image == settings.macosRunnerImage?.target ? nil : image
        let modeValue = draft.mode?.value
        let modeUpdate = modeValue == settings.vmMode?.target ? nil : modeValue

        Task {
            let saved = await agent.updateSettings(
                macosRunnerImage: imageUpdate,
                vmMode: modeUpdate
            )
            if saved {
                syncDraft(from: agent.settings)
            }
        }
    }

    private func syncDraft(from settings: RunnerAgentSettings?) {
        draft = RunnerVMSettingsDraft(settings: settings)
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

    private static func label(for mode: RunnerVmMode) -> String {
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
