import SwiftUI

// MARK: - Settings Tab Enum

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case system = "System"
    case network = "Network"
    case storage = "Storage"
    case machines = "Machines"
    case docker = "Docker"
    case kubernetes = "Kubernetes"

    var id: String { rawValue }

    var sfSymbol: String {
        switch self {
        case .general: return "gearshape"
        case .system: return "square.grid.2x2"
        case .network: return "globe"
        case .storage: return "externaldrive"
        case .machines: return "desktopcomputer"
        case .docker: return "shippingbox"
        case .kubernetes: return "helm"
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.sfSymbol)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 150, ideal: 180, max: 220)
        } detail: {
            settingsContent
                .navigationTitle(selectedTab.rawValue)
        }
        .toolbar(removing: .sidebarToggle)
        .frame(width: 700, height: 500)
    }

    @ViewBuilder
    private var settingsContent: some View {
        switch selectedTab {
        case .general:
            GeneralSettingsView()
        default:
            Text(selectedTab.rawValue)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    SettingsView()
}
