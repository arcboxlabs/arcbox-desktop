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
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("startAtLogin") private var startAtLogin = false
    @AppStorage("showInMenuBar") private var showInMenuBar = false
    @AppStorage("updateChannel") private var updateChannel = "stable"
    @AppStorage("terminalTheme") private var terminalTheme = "system"
    @AppStorage("externalTerminal") private var externalTerminal = ExternalTerminalApp.terminalBundleIdentifier
    @AppStorage("telemetryEnabled") private var telemetryEnabled = true
    @AppStorage(AppNotification.Category.sandbox.preferenceKey) private var notifySandboxResults = true
    @AppStorage(AppNotification.Category.daemonHealth.preferenceKey) private var notifyDaemonProblems = true

    @State private var isExportingDiagnostics = false
    @State private var loginItemErrorMessage: String?
    @State private var diagnosticErrorMessage: String?
    @State private var externalTerminalApps = ExternalTerminalDiscovery.availableTerminals()
    @State private var externalTerminalSelection = ExternalTerminalApp.terminalBundleIdentifier
    @State private var isShowingExternalTerminalImporter = false
    @State private var isShowingExternalTerminalSelectionError = false
    @State private var externalTerminalSelectionErrorMessage = ""

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Start at login",
                    isOn: Binding(
                        get: { startAtLogin },
                        set: { updateLoginItem(enabled: $0) }
                    )
                )
                if let loginItemErrorMessage {
                    Label(loginItemErrorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                    Button("Open Login Items Settings") {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                    .font(.caption)
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

            Section("Notifications") {
                LabeledContent {
                    Toggle("", isOn: $notifySandboxResults)
                        .labelsHidden()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sandbox execution results")
                        Text("Every failure, and successful runs longer than 30 seconds.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent {
                    Toggle("", isOn: $notifyDaemonProblems)
                        .labelsHidden()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Daemon problems")
                        Text("When the daemon stops, or stays unreachable for 30 seconds.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Button("Open Notification Settings...") {
                    openNotificationSettings()
                }
                .font(.caption)
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
                    guard let presentingWindow = NSApp.keyWindow ?? NSApp.mainWindow else {
                        diagnosticErrorMessage =
                            "ArcBox could not present the save panel. Reopen Settings and try again."
                        return
                    }
                    diagnosticErrorMessage = nil
                    isExportingDiagnostics = true
                    Task {
                        defer { isExportingDiagnostics = false }
                        do {
                            _ = try await DiagnosticBundleExporter.exportInteractively(
                                daemonManager: daemonManager,
                                containersVM: containersVM,
                                imagesVM: imagesVM,
                                presentingWindow: presentingWindow
                            )
                        } catch {
                            diagnosticErrorMessage =
                                "Diagnostic report was not exported: \(error.localizedDescription)"
                        }
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

                if let diagnosticErrorMessage {
                    Label(diagnosticErrorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear {
            syncLoginItemState()
            refreshExternalTerminalApps()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                syncLoginItemState()
            }
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
        let status = SMAppService.mainApp.status
        startAtLogin = status == .enabled
        loginItemErrorMessage =
            status == .requiresApproval
            ? "macOS requires approval before ArcBox can start at login."
            : nil
    }

    /// The toggles above only gate what ArcBox sends; whether any of it is
    /// allowed through is a system-level decision that lives in System
    /// Settings. There is no API for that pane — unlike login items, which have
    /// `SMAppService.openSystemSettingsLoginItems()` — so this goes through the
    /// URL scheme. It is not documented by Apple, so a pane identifier change
    /// would leave the button opening nothing rather than misbehaving.
    private func openNotificationSettings() {
        let pane = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        guard let url = URL(string: "\(pane)?id=\(Bundle.main.bundleIdentifier ?? "")") else { return }
        NSWorkspace.shared.open(url)
    }

    private func updateLoginItem(enabled: Bool) {
        var operationError: Error?
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            operationError = error
        }

        let status = SMAppService.mainApp.status
        startAtLogin = status == .enabled
        guard startAtLogin != enabled else {
            loginItemErrorMessage = nil
            return
        }

        if status == .requiresApproval {
            loginItemErrorMessage = "macOS requires approval before ArcBox can start at login."
        } else if let operationError {
            loginItemErrorMessage =
                "The login item was not changed: \(operationError.localizedDescription)"
        } else {
            loginItemErrorMessage = "macOS did not apply the requested login item setting."
        }
    }
}
