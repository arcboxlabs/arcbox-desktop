import ArcBoxClient
import DockerClient
import SwiftUI

/// The SwiftUI content displayed inside the menu bar popover.
struct MenuBarView: View {
    @Environment(DaemonManager.self) private var daemonManager
    @Environment(\.dockerClient) private var docker

    @State private var vm = ContainersViewModel()
    @State private var selectedFlyout: MenuBarFlyout?

    private var menuContainers: [ContainerViewModel] {
        vm.containers.sorted { lhs, rhs in
            if lhs.isRunning != rhs.isRunning {
                return lhs.isRunning && !rhs.isRunning
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var visibleContainers: [ContainerViewModel] {
        Array(menuContainers.prefix(4))
    }

    private var hasHiddenContainers: Bool {
        menuContainers.count > visibleContainers.count
    }

    private var selectedContainer: ContainerViewModel? {
        guard case let .container(id)? = selectedFlyout else { return visibleContainers.first }
        return visibleContainers.first(where: { $0.id == id }) ?? visibleContainers.first
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            mainMenuPanel

            if let selectedFlyout {
                secondaryPanel(for: selectedFlyout)
                    .padding(.top, secondaryPanelTopPadding(for: selectedFlyout))
                    .transition(.offset(x: -10).combined(with: .opacity))
            }
        }
        .padding(10)
        .frame(width: selectedFlyout == nil ? 340 : 582)
        .animation(.snappy(duration: 0.18, extraBounce: 0), value: selectedFlyout)
        .task(id: docker != nil) {
            guard docker != nil else { return }
            await vm.loadContainersFromDocker(docker: docker)
        }
        .onReceive(NotificationCenter.default.publisher(for: .dockerContainerChanged)) { _ in
            Task { await vm.loadContainersFromDocker(docker: docker) }
        }
        .onAppear {
            ensureFlyoutSelection()
        }
        .onChange(of: visibleContainers) { _, _ in
            ensureFlyoutSelection()
        }
    }

    // MARK: - Layout

    private var mainMenuPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            openArcBoxRow
            panelDivider

            sectionHeader("Containers")

            if visibleContainers.isEmpty {
                emptyContainerRow
            } else {
                ForEach(visibleContainers) { container in
                    MenuBarContainerRow(
                        container: container,
                        isSelected: selectedFlyout == .container(container.id),
                        onHoverStart: {
                            selectFlyout(.container(container.id))
                        }
                    ) {
                        selectFlyout(.container(container.id))
                    }
                }
            }

            if hasHiddenContainers {
                MenuBarMenuRow(
                    title: "More containers",
                    systemImage: "ellipsis",
                    accent: AppColors.textSecondary,
                    showsChevron: true
                ) {}
            }

            panelDivider
            sectionHeader("Machines")

            ForEach(Self.defaultMachines) { machine in
                MenuBarMenuRow(
                    title: machine.name,
                    subtitle: machine.subtitle,
                    systemImage: "laptopcomputer",
                    accent: machine.isRunning ? AppColors.running : AppColors.stopped,
                    showsChevron: true,
                    isSelected: selectedFlyout == .machine(machine.id),
                    onHoverStart: {
                        selectFlyout(.machine(machine.id))
                    }
                ) {
                    selectFlyout(.machine(machine.id))
                }
            }

            panelDivider

            MenuBarMenuRow(
                title: "Help",
                systemImage: "questionmark.circle",
                accent: AppColors.textSecondary,
                showsChevron: true,
                isSelected: selectedFlyout == .help,
                onHoverStart: {
                    selectFlyout(.help)
                }
            ) {
                selectFlyout(.help)
            }

            MenuBarMenuRow(
                title: "Settings",
                systemImage: "gearshape",
                accent: AppColors.textSecondary
            ) {}

            MenuBarMenuRow(
                title: "Quit",
                systemImage: "power",
                accent: AppColors.error
            ) {
                NSApp.terminate(nil)
            }
        }
        .padding(10)
        .frame(width: 326, alignment: .leading)
        .background { panelBackground(cornerRadius: 18) }
    }

    private var openArcBoxRow: some View {
        Button {
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 34, height: 34)

                    Image(systemName: "macwindow.on.rectangle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Open ArcBox")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Bring the app to front")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
                statusBadge
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppColors.sidebarItemHover)
            )
        }
        .buttonStyle(.plain)
    }

    private var statusBadge: some View {
        Text(statusBadgeTitle)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(statusBadgeColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(statusBadgeColor.opacity(0.16))
            )
    }

    private var emptyContainerRow: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                    .frame(width: 28, height: 28)

                Image(systemName: "shippingbox")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("No containers yet")
                    .font(.system(size: 13, weight: .medium))
                Text("Daemon will populate this area later")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func secondaryPanel(for flyout: MenuBarFlyout) -> some View {
        switch flyout {
        case .container:
            if let container = selectedContainer {
                flyoutCard(
                    title: container.name,
                    subtitle: container.image,
                    systemImage: "shippingbox.fill",
                    accent: container.state.color
                ) {
                    MenuBarSubmenuRow(
                        title: container.isRunning ? "Stop" : "Start",
                        systemImage: container.isRunning ? "stop.fill" : "play.fill",
                        tint: container.isRunning ? AppColors.error : AppColors.running
                    ) {
                        performPrimaryAction(for: container)
                    }

                    MenuBarSubmenuRow(
                        title: "Restart",
                        systemImage: "arrow.clockwise",
                        tint: .primary
                    ) {}

                    MenuBarSubmenuRow(
                        title: "Delete",
                        systemImage: "trash",
                        tint: AppColors.error
                    ) {}

                    flyoutDivider

                    MenuBarSubmenuRow(
                        title: "Logs",
                        systemImage: "text.alignleft",
                        tint: .primary
                    ) {}

                    let services = serviceItems(for: container)
                    if !services.isEmpty {
                        flyoutDivider
                        flyoutSectionHeader("Services")

                        ForEach(services) { service in
                            MenuBarSubmenuRow(
                                title: service.title,
                                systemImage: "circle.fill",
                                tint: service.isRunning ? AppColors.running : AppColors.stopped,
                                showsChevron: true
                            ) {}
                        }
                    }
                }
            }

        case let .machine(id):
            if let machine = Self.defaultMachines.first(where: { $0.id == id }) {
                flyoutCard(
                    title: machine.name,
                    subtitle: machine.subtitle,
                    systemImage: "laptopcomputer",
                    accent: machine.isRunning ? AppColors.running : AppColors.stopped
                ) {
                    MenuBarSubmenuRow(
                        title: machine.isRunning ? "Stop" : "Start",
                        systemImage: machine.isRunning ? "stop.fill" : "play.fill",
                        tint: machine.isRunning ? AppColors.error : AppColors.running
                    ) {}

                    MenuBarSubmenuRow(
                        title: "Restart",
                        systemImage: "arrow.clockwise",
                        tint: .primary
                    ) {}

                    flyoutDivider

                    MenuBarSubmenuRow(
                        title: "Open Terminal",
                        systemImage: "terminal",
                        tint: .primary
                    ) {}

                    MenuBarSubmenuRow(
                        title: "Inspect",
                        systemImage: "info.circle",
                        tint: .primary
                    ) {}
                }
            }

        case .help:
            flyoutCard(
                title: "Help",
                subtitle: "Useful shortcuts and links",
                systemImage: "questionmark.circle",
                accent: AppColors.textSecondary
            ) {
                ForEach(Self.helpItems) { item in
                    MenuBarSubmenuRow(
                        title: item.title,
                        systemImage: item.systemImage,
                        tint: .primary,
                        showsChevron: true
                    ) {}
                }
            }
        }
    }

    private func flyoutCard<Content: View>(
        title: String,
        subtitle: String,
        systemImage: String,
        accent: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accent.opacity(0.15))
                        .frame(width: 34, height: 34)

                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            panelDivider

            VStack(alignment: .leading, spacing: 4) {
                content()
            }
            .padding(8)
        }
        .frame(width: 234, alignment: .leading)
        .background { panelBackground(cornerRadius: 18) }
    }

    private var panelDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
            .padding(.vertical, 8)
    }

    private var flyoutDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
            .padding(.vertical, 6)
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    private func flyoutSectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 2)
    }

    private var statusBadgeTitle: String {
        if daemonManager.state.isRunning {
            return "\(vm.runningCount) live"
        }
        return "Starting"
    }

    private var statusBadgeColor: Color {
        if daemonManager.state.isRunning {
            return AppColors.running
        }
        return AppColors.textSecondary
    }

    private func performPrimaryAction(for container: ContainerViewModel) {
        Task {
            if container.isRunning {
                await vm.stopContainerDocker(container.id, docker: docker)
            } else {
                await vm.startContainerDocker(container.id, docker: docker)
            }
        }
    }

    private func selectFlyout(_ flyout: MenuBarFlyout) {
        withAnimation(.snappy(duration: 0.18, extraBounce: 0)) {
            selectedFlyout = flyout
        }
    }

    private func ensureFlyoutSelection() {
        switch selectedFlyout {
        case let .container(id)?:
            if !visibleContainers.contains(where: { $0.id == id }) {
                selectedFlyout = visibleContainers.first.map { .container($0.id) } ?? .help
            }
        case let .machine(id)?:
            if !Self.defaultMachines.contains(where: { $0.id == id }) {
                selectedFlyout = visibleContainers.first.map { .container($0.id) } ?? .help
            }
        case .help?:
            break
        case nil:
            selectedFlyout = visibleContainers.first.map { .container($0.id) } ?? .help
        }
    }

    private func secondaryPanelTopPadding(for flyout: MenuBarFlyout) -> CGFloat {
        let topRowHeight: CGFloat = 60
        let rowHeight: CGFloat = 47
        let sectionSpacing: CGFloat = 40
        let containerRows = CGFloat(max(visibleContainers.count, 1)) * rowHeight
        let overflowRow = hasHiddenContainers ? rowHeight : 0

        switch flyout {
        case let .container(id):
            let index = CGFloat(visibleContainers.firstIndex(where: { $0.id == id }) ?? 0)
            return topRowHeight + index * rowHeight

        case let .machine(id):
            let machineIndex = CGFloat(Self.defaultMachines.firstIndex(where: { $0.id == id }) ?? 0)
            return topRowHeight + containerRows + overflowRow + sectionSpacing + machineIndex * rowHeight

        case .help:
            let machinesHeight = CGFloat(Self.defaultMachines.count) * rowHeight
            return topRowHeight + containerRows + overflowRow + sectionSpacing + machinesHeight + sectionSpacing - 6
        }
    }

    private func serviceItems(for container: ContainerViewModel) -> [MenuBarServiceItem] {
        switch container.name {
        case "arcbox-web":
            [
                MenuBarServiceItem(id: "main", title: "main", isRunning: container.isRunning),
                MenuBarServiceItem(id: "docs", title: "docs", isRunning: true),
            ]
        case "arcbox-api":
            [
                MenuBarServiceItem(id: "api", title: "api", isRunning: container.isRunning),
                MenuBarServiceItem(id: "worker", title: "worker", isRunning: container.isRunning),
            ]
        case "arcbox-db":
            [
                MenuBarServiceItem(id: "postgres", title: "postgres", isRunning: container.isRunning)
            ]
        default:
            [
                MenuBarServiceItem(id: "dashboard", title: "dashboard", isRunning: container.isRunning)
            ]
        }
    }

    private func panelBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08))
            )
            .shadow(color: .black.opacity(0.14), radius: 18, x: 0, y: 10)
    }
}

private extension MenuBarView {
    static let defaultMachines: [MenuBarMachine] = [
        MenuBarMachine(id: "ubuntu-dev", name: "ubuntu-dev", subtitle: "Running", isRunning: true),
        MenuBarMachine(id: "qa-runner", name: "qa-runner", subtitle: "Stopped", isRunning: false),
    ]

    static let helpItems: [MenuBarHelpItem] = [
        MenuBarHelpItem(id: "docs", title: "Docs", systemImage: "book.closed"),
        MenuBarHelpItem(id: "troubleshooting", title: "Troubleshooting", systemImage: "wrench.and.screwdriver"),
        MenuBarHelpItem(id: "changelog", title: "Release Notes", systemImage: "sparkles"),
    ]
}

private enum MenuBarFlyout: Equatable {
    case container(String)
    case machine(String)
    case help
}

private struct MenuBarMachine: Identifiable, Equatable {
    let id: String
    let name: String
    let subtitle: String
    let isRunning: Bool
}

private struct MenuBarServiceItem: Identifiable {
    let id: String
    let title: String
    let isRunning: Bool
}

private struct MenuBarHelpItem: Identifiable {
    let id: String
    let title: String
    let systemImage: String
}

private struct MenuBarMenuRow: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String
    var accent: Color = AppColors.accent
    var showsChevron = false
    var isSelected = false
    var onHoverStart: (() -> Void)? = nil
    let action: () -> Void

    @State private var isHovering = false

    private var isHighlighted: Bool {
        isSelected || isHovering
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(accent.opacity(isHighlighted ? 0.18 : 0.12))
                        .frame(width: 28, height: 28)

                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHighlighted ? AppColors.sidebarItemSelected : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                onHoverStart?()
            }
        }
    }
}

private struct MenuBarSubmenuRow: View {
    let title: String
    let systemImage: String
    var tint: Color = .primary
    var showsChevron = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 16)

                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Spacer(minLength: 8)

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovering ? AppColors.sidebarItemHover : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
