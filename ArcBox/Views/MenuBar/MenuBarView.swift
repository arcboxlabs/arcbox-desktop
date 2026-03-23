import ArcBoxClient
import DockerClient
import SwiftUI

struct MenuBarView: View {
    @Environment(DaemonManager.self) private var daemonManager
    @Environment(AppViewModel.self) private var appVM
    @Environment(ContainersViewModel.self) private var containersVM
    @Environment(ImagesViewModel.self) private var imagesVM
    @Environment(NetworksViewModel.self) private var networksVM
    @Environment(VolumesViewModel.self) private var volumesVM
    @Environment(\.arcboxClient) private var client
    @Environment(\.dockerClient) private var docker

    @State private var containersExpanded = true

    var body: some View {
        mainPanel
        .padding(6)
        .animation(.easeInOut(duration: 0.2), value: containersExpanded)
        .task(id: docker != nil && daemonManager.state.isRunning) {
            guard docker != nil, daemonManager.state.isRunning else { return }
            await loadAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: .dockerContainerChanged)) { _ in
            Task { await containersVM.loadContainersFromDocker(docker: docker, iconClient: client) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dockerImageChanged)) { _ in
            Task { await imagesVM.loadImages(docker: docker, iconClient: client) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dockerNetworkChanged)) { _ in
            Task { await networksVM.loadNetworks(docker: docker) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dockerVolumeChanged)) { _ in
            Task { await volumesVM.loadVolumes(docker: docker) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dockerDataChanged)) { _ in
            Task { await loadAll() }
        }
    }

    // MARK: - Data

    private func loadAll() async {
        async let c: () = containersVM.loadContainersFromDocker(docker: docker, iconClient: client)
        async let i: () = imagesVM.loadImages(docker: docker, iconClient: client)
        async let n: () = networksVM.loadNetworks(docker: docker)
        async let v: () = volumesVM.loadVolumes(docker: docker)
        _ = await (c, i, n, v)
    }

    // MARK: - Main Panel

    private var mainPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
                .padding(.bottom, 4)

            metricCards

            containersSection

            Divider()
                .padding(.vertical, 2)

            actionSection
        }
        .frame(width: 260)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Text("ArcBox")
                .font(.headline)

            Spacer(minLength: 0)

            statusPill(title: daemonStateDisplay, color: daemonStateColor)
        }
        .padding(.leading, 4)
        .padding(.horizontal, 2)
    }

    // MARK: - Metric Cards

    private var metricCards: some View {
        HStack(spacing: 6) {
            metricCard(
                title: "Volumes",
                count: volumesVM.volumes.count,
                symbol: "internaldrive",
                tint: .mint
            ) {
                navigateToPage(.volumes)
            }

            metricCard(
                title: "Images",
                count: imagesVM.images.count,
                symbol: "circle.circle",
                tint: .indigo
            ) {
                navigateToPage(.images)
            }

            metricCard(
                title: "Networks",
                count: networksVM.networks.count,
                symbol: "point.3.filled.connected.trianglepath.dotted",
                tint: .cyan
            ) {
                navigateToPage(.networks)
            }
        }
        .padding(.bottom, 2)
    }

    private func metricCard(
        title: String,
        count: Int,
        symbol: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Image(systemName: symbol)
                        .font(.caption2)
                        .foregroundStyle(tint)
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Text("\(count)")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(maxWidth: .infinity, alignment: .center)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .frame(height: 70)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.quaternary.opacity(0.30))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Containers Section

    private var containersSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            containersHeader

            if containersExpanded, !sortedContainers.isEmpty {
                containerList
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var containersHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                containersExpanded.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "cube")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.accent)
                    .frame(width: 16)

                Text("Containers")
                    .font(.system(size: 13, weight: .medium))

                Spacer(minLength: 0)

                Text("\(containersVM.runningCount) running")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(containersExpanded ? 90 : 0))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        containersExpanded
                            ? AnyShapeStyle(.quaternary.opacity(0.30))
                            : AnyShapeStyle(.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var containerList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(sortedContainers) { container in
                    containerRow(container)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 200)
        .padding(.leading, 26)
    }

    private func containerRow(_ container: ContainerViewModel) -> some View {
        MenuBarHoverButton {
            containersVM.selectContainer(container.id)
            appVM.navigate(to: .containers)
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(container.state.color)
                    .frame(width: 7, height: 7)

                Text(container.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(container.state.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
        }
    }

    // MARK: - Actions

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            MenuBarHoverButton {
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Show ArcBox", systemImage: "macwindow")
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
            }

            MenuBarHoverButton {
                // TODO: open settings
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
            }

            Divider()
                .padding(.vertical, 4)

            MenuBarHoverButton {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
            }
        }
        .labelStyle(.titleAndIcon)
    }

    // MARK: - Helpers

    private var sortedContainers: [ContainerViewModel] {
        containersVM.containers.sorted { lhs, rhs in
            if lhs.isRunning != rhs.isRunning {
                return lhs.isRunning && !rhs.isRunning
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var daemonStateDisplay: String {
        switch daemonManager.state {
        case .running: "Running"
        case .starting: "Starting"
        case .stopping: "Stopping"
        case .registered: "Registered"
        case .stopped: "Stopped"
        case .error: "Error"
        }
    }

    private var daemonStateColor: Color {
        switch daemonManager.state {
        case .running: AppColors.running
        case .starting, .registered, .stopping: AppColors.textSecondary
        case .stopped: AppColors.stopped
        case .error: AppColors.error
        }
    }

    private func statusPill(title: String, color: Color) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func navigateToPage(_ item: NavItem) {
        appVM.navigate(to: item)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Hover Components

private struct MenuBarHoverButton<Label: View>: View {
    var cornerRadius: CGFloat = 6
    let action: () -> Void
    @ViewBuilder let label: Label

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            label
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(isHovering ? Color.primary.opacity(0.10) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
