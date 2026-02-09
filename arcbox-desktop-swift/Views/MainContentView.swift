import SwiftUI

/// 3-column layout: sidebar | resize handle | main content
struct MainContentView: View {
    @Environment(AppViewModel.self) private var appVM

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            SidebarView()

            // Divider between sidebar and content
            if !appVM.sidebarCollapsed {
                Rectangle()
                    .fill(AppColors.borderSubtle)
                    .frame(width: 1)
            }

            // Main content - switches based on navItem
            Group {
                switch appVM.currentNav {
                case .containers:
                    ContainersListView()
                case .volumes:
                    VolumesListView()
                case .images:
                    ImagesListView()
                case .networks:
                    NetworksListView()
                case .machines:
                    MachinesView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppColors.background)
    }
}
