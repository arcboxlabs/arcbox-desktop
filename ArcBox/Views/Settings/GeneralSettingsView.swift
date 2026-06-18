import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

import ArcBoxClient
import PostHog

struct GeneralSettingsView: View {
    private static let chooseExternalTerminalID = "__arcbox_choose_external_terminal__"

    @Environment(DaemonManager.self) private var daemonManager
    @Environment(ContainersViewModel.self) private var containersVM
    @Environment(ImagesViewModel.self) private var imagesVM

    @AppStorage("startAtLogin") private var startAtLogin = false
    @AppStorage("showInMenuBar") private var showInMenuBar = false
    @AppStorage("keepRunning") private var keepRunning = false
    @AppStorage("autoUpdate") private var autoUpdate = false
    @AppStorage("updateChannel") private var updateChannel = "stable"
    @AppStorage("terminalTheme") private var terminalTheme = "system"
    @AppStorage("externalTerminal") private var externalTerminal = ExternalTerminalApp.terminalBundleIdentifier
    @AppStorage("telemetryEnabled") private var telemetryEnabled = true

    @State private var isSyncingLoginItem = false
    @State private var isExportingDiagnostics = false
    @State private var externalTerminalApps = ExternalTerminalDiscovery.availableTerminals()
    @State private var externalTerminalSelection = ExternalTerminalApp.terminalBundleIdentifier

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
                    #if !DEBUG
                        if newValue {
                            PostHogSDK.shared.optIn()
                        } else {
                            PostHogSDK.shared.optOut()
                        }
                    #endif
                }
            }

            Section("Terminal") {
                Picker("Terminal theme", selection: $terminalTheme) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                LabeledContent {
                    Picker("", selection: $externalTerminalSelection) {
                        ForEach(externalTerminalApps) { app in
                            Text(app.displayName).tag(app.id)
                        }
                        Divider()
                        Text("Choose...").tag(Self.chooseExternalTerminalID)
                    }
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: externalTerminalSelection) { _, newValue in
                        updateExternalTerminalSelection(newValue)
                    }
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
            refreshExternalTerminalApps()
        }
    }

    private func refreshExternalTerminalApps(additionalTerminal: ExternalTerminalApp? = nil) {
        var terminals = ExternalTerminalDiscovery.availableTerminals(
            preferredBundleIdentifier: externalTerminal
        )
        if let additionalTerminal, !terminals.contains(where: { $0.id == additionalTerminal.id }) {
            terminals.append(additionalTerminal)
        }
        externalTerminalApps = terminals

        let normalized = ExternalTerminalDiscovery.normalizedPreference(
            externalTerminal,
            availableTerminals: terminals
        )
        if normalized != externalTerminal {
            externalTerminal = normalized
        }
        externalTerminalSelection = normalized
    }

    private func updateExternalTerminalSelection(_ selection: String) {
        guard selection != Self.chooseExternalTerminalID else {
            chooseExternalTerminal()
            return
        }

        externalTerminal = selection
        refreshExternalTerminalApps()
    }

    private func chooseExternalTerminal() {
        let panel = NSOpenPanel()
        panel.title = "Choose External Terminal"
        panel.prompt = "Choose"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK,
            let appURL = panel.url,
            let terminal = ExternalTerminalDiscovery.terminalApp(for: appURL)
        else {
            externalTerminalSelection = externalTerminal
            return
        }

        externalTerminal = terminal.id
        refreshExternalTerminalApps(additionalTerminal: terminal)
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
