import ArcBoxClient
import SwiftUI

/// Column 2: sandboxes page with Monitoring and List tabs
struct SandboxesListView: View {
    @Environment(SandboxesViewModel.self) private var vm
    @Environment(\.arcboxClient) private var client

    @State private var sandboxToRemove: SandboxViewModel? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Page tab bar
            HStack(spacing: 0) {
                ForEach(SandboxPageTab.allCases) { tab in
                    Button {
                        vm.pageTab = tab
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab == .monitoring ? "chart.xyaxis.line" : "list.bullet")
                                .font(.system(size: 12))
                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            vm.pageTab == tab
                                ? AppColors.surfaceElevated
                                : Color.clear
                        )
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            Divider()

            // Tab content
            switch vm.pageTab {
            case .monitoring:
                SandboxMonitoringView(vm: vm)
            case .list:
                sandboxListContent
            }
        }
        .navigationTitle("Sandboxes")
        .navigationSubtitle(vm.pageTab == .list ? "\(vm.sandboxCount) total" : "\(vm.concurrentSandboxes) concurrent")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if vm.pageTab == .list {
                    SortMenuButton(sortBy: Bindable(vm).sortBy, ascending: Bindable(vm).sortAscending)
                }
                Button(action: {
                    Task {
                        _ = await vm.createSandbox(client: client)
                    }
                }) {
                    Image(systemName: "plus")
                }
            }
        }
        .task {
            await vm.loadSandboxes(client: client)
        }
        .onReceive(NotificationCenter.default.publisher(for: .sandboxChanged)) { _ in
            Task {
                await vm.loadSandboxes(client: client)
            }
        }
        .confirmationDialog(
            "Remove Sandbox",
            isPresented: Binding(
                get: { sandboxToRemove != nil },
                set: { if !$0 { sandboxToRemove = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let sandbox = sandboxToRemove {
                Button("Remove \"\(sandbox.displayName)\"", role: .destructive) {
                    Task {
                        await vm.removeSandbox(sandbox.id, force: true, client: client)
                    }
                }
            }
            Button("Cancel", role: .cancel) { sandboxToRemove = nil }
        } message: {
            Text("This action cannot be undone.")
        }
        .alert("Error", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.clearError() } }
        )) {
            Button("OK") { vm.clearError() }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    private var sandboxListContent: some View {
        VStack(spacing: 0) {
            if vm.sandboxes.isEmpty {
                SandboxEmptyState()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.sortedSandboxes) { sandbox in
                            SandboxRowView(
                                sandbox: sandbox,
                                isSelected: vm.selectedID == sandbox.id,
                                onSelect: { vm.selectSandbox(sandbox.id) },
                                onStop: {
                                    Task { await vm.stopSandbox(sandbox.id, client: client) }
                                },
                                onRemove: {
                                    sandboxToRemove = sandbox
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}
