import AppKit
import ArcBoxClient
import DockerClient
import SwiftUI

struct MenuBarView: View {
    @Environment(DaemonManager.self) var daemonManager
    @Environment(AppViewModel.self) var appVM
    @Environment(ContainersViewModel.self) var containersVM
    @Environment(ImagesViewModel.self) var imagesVM
    @Environment(NetworksViewModel.self) var networksVM
    @Environment(VolumesViewModel.self) var volumesVM
    @Environment(\.openWindow) var openWindow
    @Environment(\.arcboxClient) var client
    @Environment(\.dockerClient) var docker

    @State var containersExpanded = true

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
            .onAppear {
                containersExpanded = hasContainers
            }
            .onChange(of: containersVM.runningCount) { _, newValue in
                withAnimation(.easeInOut(duration: 0.2)) {
                    containersExpanded = newValue > 0 || hasStoppedContainers
                }
            }
            .onChange(of: containersVM.containers.isEmpty) { _, isEmpty in
                withAnimation(.easeInOut(duration: 0.2)) {
                    containersExpanded = !isEmpty
                }
            }
    }
}
