import ArcBoxClient
import DockerClient
import SwiftUI

/// Transitional SwiftUI toolbar host for the native network detail controller.
struct NetworkDetailView: View {
    @Environment(NetworksViewModel.self) private var vm
    @Environment(ContainersViewModel.self) private var containersVM
    @Environment(DaemonManager.self) private var daemonManager
    @Environment(\.dockerClient) private var docker

    var body: some View {
        NetworkDetailControllerView(
            viewModel: vm,
            loadContainers: makeContainerLoader(),
            runningContainerIDs: runningContainerIDs
        )
        .toolbar {
            DetailTabPicker(selection: .constant(NetworkDetailTab.info))
        }
        .task(id: dockerRuntimeAvailable) {
            await loadContainerStates()
        }
        .onReceive(NotificationCenter.default.publisher(for: .dockerContainerChanged)) { _ in
            Task { await loadContainerStates() }
        }
    }

    private var dockerRuntimeAvailable: Bool {
        daemonManager.isDockerReady && docker != nil
    }

    private var runningContainerIDs: Set<String>? {
        guard dockerRuntimeAvailable, containersVM.loadState == .loaded else { return nil }
        return Set(containersVM.containers.filter(\.isRunning).map(\.id))
    }

    private func makeContainerLoader() -> NetworkDetailViewController.LoadContainers? {
        guard daemonManager.isDockerReady, let docker else { return nil }
        return { networkID in
            let response = try await docker.api.NetworkInspect(path: .init(id: networkID))
            let network = try response.ok.body.json

            return (network.Containers?.additionalProperties ?? [:])
                .map { containerID, container in
                    NetworkDetailViewController.ContainerEntry(
                        id: containerID,
                        name: container.Name ?? String(containerID.prefix(12)),
                        ipv4: container.IPv4Address ?? "",
                        mac: container.MacAddress ?? ""
                    )
                }
                .sorted {
                    let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
                    return comparison == .orderedSame
                        ? $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending
                        : comparison == .orderedAscending
                }
        }
    }

    private func loadContainerStates() async {
        guard dockerRuntimeAvailable else { return }
        await containersVM.loadContainersFromDocker(docker: docker)
    }
}

private enum NetworkDetailTab: String, @MainActor DetailTab {
    case info = "Info"

    var id: String { rawValue }
}

private struct NetworkDetailControllerView: NSViewControllerRepresentable {
    let viewModel: NetworksViewModel
    let loadContainers: NetworkDetailViewController.LoadContainers?
    let runningContainerIDs: Set<String>?

    func makeNSViewController(context _: Context) -> NetworkDetailViewController {
        NetworkDetailViewController(
            viewModel: viewModel,
            loadContainers: loadContainers,
            runningContainerIDs: runningContainerIDs
        )
    }

    func updateNSViewController(
        _ controller: NetworkDetailViewController,
        context _: Context
    ) {
        controller.update(
            loadContainers: loadContainers,
            runningContainerIDs: runningContainerIDs
        )
    }
}
