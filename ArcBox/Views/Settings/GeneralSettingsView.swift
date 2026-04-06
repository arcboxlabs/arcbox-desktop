import ArcBoxClient
import PostHog
import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @Environment(DaemonManager.self) private var daemonManager
    @Environment(ContainersViewModel.self) private var containersVM
    @Environment(ImagesViewModel.self) private var imagesVM

    @AppStorage("startAtLogin") private var startAtLogin = false
    @AppStorage("showInMenuBar") private var showInMenuBar = false
    @AppStorage("keepRunning") private var keepRunning = false
    @AppStorage("autoUpdate") private var autoUpdate = false
    @AppStorage("updateChannel") private var updateChannel = "stable"
    @AppStorage("terminalTheme") private var terminalTheme = "system"
    @AppStorage("externalTerminal") private var externalTerminal = "lastUsed"
    @AppStorage("telemetryEnabled") private var telemetryEnabled = true

    @State private var isSyncingLoginItem = false
    @State private var isExportingDiagnostics = false

    var body: some View {
        Form {
            Section {
                Toggle("Start at login", isOn: $startAtLogin)
                    .onChange(of: startAtLogin) { _, newValue in
                        guard !isSyncingLoginItem else { return }
                        updateLoginItem(enabled: newValue)
                    }
                Toggle("Show in menu bar", isOn: $showInMenuBar)
                Toggle("Keep running when app is quit", isOn: $keepRunning)
            }

            Section("Updates") {
                Toggle("Automatically check for updates", isOn: $autoUpdate)
                Picker("Update channel", selection: $updateChannel) {
                    Text("Stable").tag("stable")
                    Text("Beta").tag("beta")
                }
            }

            Section("Privacy") {
                LabeledContent {
                    Toggle("", isOn: $telemetryEnabled)
                        .labelsHidden()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Share anonymous usage data")
                        Text(
                            "Help improve ArcBox by sharing feature usage statistics. No personal data is collected."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: telemetryEnabled) { _, newValue in
                    if newValue {
                        PostHogSDK.shared.optIn()
                    } else {
                        PostHogSDK.shared.optOut()
                    }
                }
            }

            Section("Terminal") {
                Picker("Terminal theme", selection: $terminalTheme) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                LabeledContent {
                    Picker("", selection: $externalTerminal) {
                        Text("Last used").tag("lastUsed")
                        Text("Terminal").tag("terminal")
                        Text("iTerm").tag("iterm")
                    }
                    .labelsHidden()
                    .frame(width: 120)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("External terminal app")
                        Text("Used when opening terminal in a new window.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Troubleshooting") {
                Button("Export Diagnostic Report...") {
                    isExportingDiagnostics = true
                    Task {
                        await DiagnosticBundleExporter.exportInteractively(
                            daemonManager: daemonManager,
                            containersVM: containersVM,
                            imagesVM: imagesVM
                        )
                        isExportingDiagnostics = false
                    }
                }
                .disabled(isExportingDiagnostics)

                if isExportingDiagnostics {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Generating report...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear {
            syncLoginItemState()
        }
    }

    // MARK: - Login Item

    private func syncLoginItemState() {
        isSyncingLoginItem = true
        startAtLogin = SMAppService.mainApp.status == .enabled
        isSyncingLoginItem = false
    }

    private func updateLoginItem(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Revert on failure
            startAtLogin = !enabled
        }
    }
}

#Preview {
    GeneralSettingsView()
        .environment(DaemonManager())
        .environment(ContainersViewModel())
        .environment(ImagesViewModel())
        .frame(width: 500, height: 400)
}
