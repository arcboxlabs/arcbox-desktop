import AppKit
import ArcBoxClient
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct GeneralSettingsView: View {
    private static let chooseExternalTerminalID = "__arcbox_choose_external_terminal__"

    @Environment(DaemonManager.self) private var daemonManager
    @Environment(ContainersViewModel.self) private var containersVM
    @Environment(ImagesViewModel.self) private var imagesVM
    @Environment(UpdaterSettingsModel.self) private var updaterSettings

    @AppStorage("startAtLogin") private var startAtLogin = false
    @AppStorage("showInMenuBar") private var showInMenuBar = false
    @AppStorage("updateChannel") private var updateChannel = "stable"
    @AppStorage("terminalTheme") private var terminalTheme = "system"
    @AppStorage("externalTerminal") private var externalTerminal = ExternalTerminalApp.terminalBundleIdentifier
    @AppStorage("telemetryEnabled") private var telemetryEnabled = true

    @State private var isSyncingLoginItem = false
    @State private var isExportingDiagnostics = false
    @State private var externalTerminalApps = ExternalTerminalDiscovery.availableTerminals()
    @State private var externalTerminalSelection = ExternalTerminalApp.terminalBundleIdentifier
    @State private var isShowingExternalTerminalImporter = false
    @State private var isShowingExternalTerminalSelectionError = false
    @State private var externalTerminalSelectionErrorMessage = ""

    var body: some View {
        Form {
            Section {
                Toggle("Start at login", isOn: $startAtLogin)
                    .onChange(of: startAtLogin) { _, newValue in
                        guard !isSyncingLoginItem else { return }
                        updateLoginItem(enabled: newValue)
                    }
                Toggle("Show in menu bar", isOn: $showInMenuBar)
            }

            Section("Updates") {
                Toggle(
                    "Automatically check for updates",
                    isOn: Binding(
                        get: { updaterSettings.automaticallyChecksForUpdates },
                        set: { updaterSettings.setAutomaticallyChecksForUpdates($0) }
                    )
                )
                Toggle(
                    "Automatically download and install updates",
                    isOn: Binding(
                        get: { updaterSettings.automaticallyDownloadsUpdates },
                        set: { updaterSettings.setAutomaticallyDownloadsUpdates($0) }
                    )
                )
                .disabled(!updaterSettings.allowsAutomaticUpdates)
                .padding(.leading, 20)
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
                        Text("Share usage data")
                        Text(
                            "Help improve ArcBox by sharing feature usage statistics. While you are signed in, this is linked to your account."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                    guard let presentingWindow = NSApp.keyWindow else { return }
                    isExportingDiagnostics = true
                    Task {
                        await DiagnosticBundleExporter.exportInteractively(
                            daemonManager: daemonManager,
                            containersVM: containersVM,
                            imagesVM: imagesVM,
                            presentingWindow: presentingWindow
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
        .fileImporter(
            isPresented: $isShowingExternalTerminalImporter,
            allowedContentTypes: [.applicationBundle]
        ) { result in
            handleExternalTerminalSelection(result)
        }
        .fileDialogDefaultDirectory(URL(fileURLWithPath: "/Applications", isDirectory: true))
        .fileDialogConfirmationLabel("Choose")
        .alert("External terminal not available", isPresented: $isShowingExternalTerminalSelectionError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(externalTerminalSelectionErrorMessage)
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
            isShowingExternalTerminalImporter = true
            return
        }

        externalTerminal = selection
        refreshExternalTerminalApps()
    }

    private func handleExternalTerminalSelection(_ result: Result<URL, Error>) {
        guard case .success(let appURL) = result else {
            externalTerminalSelection = externalTerminal
            if case .failure(let error) = result,
                (error as? CocoaError)?.code != .userCancelled
            {
                showExternalTerminalSelectionError(error.localizedDescription)
            }
            return
        }

        let hasAccess = appURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { appURL.stopAccessingSecurityScopedResource() }
        }

        let commandHandlerBundleIDs = Set(
            externalTerminalApps.filter(\.supportsCommandFiles).compactMap(\.bundleIdentifier)
        )
        guard
            let terminal = ExternalTerminalDiscovery.terminalApp(
                for: appURL,
                commandHandlerBundleIDs: commandHandlerBundleIDs
            )
        else {
            externalTerminalSelection = externalTerminal
            showExternalTerminalSelectionError(
                "ArcBox could not read a bundle identifier from the selected app."
            )
            return
        }

        externalTerminal = terminal.id
        refreshExternalTerminalApps(additionalTerminal: terminal)
    }

    private func showExternalTerminalSelectionError(_ message: String) {
        externalTerminalSelectionErrorMessage = message
        isShowingExternalTerminalSelectionError = true
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
