import SwiftUI

/// Sidebar with Docker/Linux sections and collapse toggle
struct SidebarView: View {
    @Environment(AppViewModel.self) private var appVM

    var body: some View {
        let collapsed = appVM.sidebarCollapsed

        VStack(spacing: 0) {
            // Titlebar spacer area (for traffic lights on macOS)
            HStack {
                Spacer()
                Button(action: { appVM.toggleSidebar() }) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .buttonStyle(.plain)
                .frame(width: 24, height: 24)
            }
            .frame(height: 52)
            .padding(.horizontal, 8)

            if !collapsed {
                // DOCKER section
                Text("DOCKER")
                    .sectionHeaderStyle()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 4)
            }

            ForEach(NavItem.Section.docker.items) { item in
                SidebarItemView(
                    item: item,
                    isSelected: appVM.currentNav == item,
                    collapsed: collapsed
                )
                .onTapGesture { appVM.navigate(to: item) }
            }

            if !collapsed {
                // LINUX section
                Text("LINUX")
                    .sectionHeaderStyle()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 4)
            } else {
                Spacer().frame(height: 16)
            }

            ForEach(NavItem.Section.linux.items) { item in
                SidebarItemView(
                    item: item,
                    isSelected: appVM.currentNav == item,
                    collapsed: collapsed
                )
                .onTapGesture { appVM.navigate(to: item) }
            }

            Spacer()
        }
        .frame(
            width: collapsed ? 52 : appVM.sidebarWidth
        )
        .background(AppColors.sidebar)
        .animation(.easeInOut(duration: 0.25), value: collapsed)
    }
}
