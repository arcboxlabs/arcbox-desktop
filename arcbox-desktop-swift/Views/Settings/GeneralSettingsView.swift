import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage("startAtLogin") private var startAtLogin = false
    @AppStorage("showInMenuBar") private var showInMenuBar = false
    @AppStorage("keepRunning") private var keepRunning = false
    @AppStorage("autoUpdate") private var autoUpdate = false
    @AppStorage("updateChannel") private var updateChannel = "stable"
    @AppStorage("terminalTheme") private var terminalTheme = "system"
    @AppStorage("externalTerminal") private var externalTerminal = "lastUsed"

    var body: some View {
        Form {
            Section {
                Toggle("Start at login", isOn: $startAtLogin)
                    .onChange(of: startAtLogin) { _, newValue in
                        updateLoginItem(enabled: newValue)
                    }
                Toggle("Show in menu bar", isOn: $showInMenuBar)
                Toggle("Keep running when app is quit", isOn: $keepRunning)
            }

            Section("Updates") {
                Toggle("Automatically download updates", isOn: $autoUpdate)
                Picker("Update channel", selection: $updateChannel) {
                    Text("Stable").tag("stable")
                    Text("Beta").tag("beta")
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
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear {
            syncLoginItemState()
        }
    }

    // MARK: - Login Item

    private func syncLoginItemState() {
        startAtLogin = SMAppService.mainApp.status == .enabled
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
        .frame(width: 500, height: 400)
}
