import ArcBoxClient
import DockerClient
import Foundation

// MARK: - Proto → UI Model Conversion

extension ContainerViewModel {
    /// Create a ContainerViewModel from a gRPC ContainerSummary.
    init(from summary: Arcbox_V1_ContainerSummary) {
        let name =
            summary.names.first.map {
                $0.hasPrefix("/") ? String($0.dropFirst()) : $0
            } ?? summary.id.prefix(12).description

        let state: ContainerState =
            switch summary.state {
            case "running": .running
            case "paused": .paused
            case "restarting": .restarting
            case "dead": .dead
            default: .stopped
            }

        let ports = summary.ports.map { port in
            PortMapping(
                hostPort: UInt16(port.hostPort),
                containerPort: UInt16(port.containerPort),
                protocol: port.protocol
            )
        }

        let composeProject = summary.labels["com.docker.compose.project"]
        let composeService = summary.labels["com.docker.compose.service"]
        let rootfsMountPath = ContainerViewModel.inferRootFSMountPath(
            explicitPath: nil,
            labels: summary.labels,
            mounts: []
        )

        self.init(
            id: summary.id,
            name: name,
            image: summary.image,
            state: state,
            ports: ports,
            createdAt: Date(timeIntervalSince1970: TimeInterval(summary.created)),
            composeProject: composeProject,
            composeService: composeService,
            labels: summary.labels,
            cpuPercent: 0,
            memoryMB: 0,
            memoryLimitMB: 0,
            rootfsMountPath: rootfsMountPath
        )
    }

    /// Create a ContainerViewModel from a Docker Engine API ContainerSummary.
    init(fromDocker summary: Components.Schemas.ContainerSummary) {
        let name =
            summary.Names?.first.map {
                $0.hasPrefix("/") ? String($0.dropFirst()) : $0
            } ?? summary.Id?.prefix(12).description ?? "unknown"

        let state: ContainerState =
            switch summary.State?.lowercased() {
            case "running": .running
            case "paused": .paused
            case "restarting": .restarting
            case "dead": .dead
            default: .stopped  // created, exited, removing -> stopped
            }

        let ports = (summary.Ports ?? []).compactMap { port -> PortMapping? in
            guard let publicPort = port.PublicPort else { return nil }
            return PortMapping(
                hostPort: UInt16(publicPort),
                containerPort: UInt16(port.PrivatePort),
                protocol: port._Type.rawValue
            )
        }

        let labels = summary.Labels?.additionalProperties ?? [:]
        let composeProject = labels["com.docker.compose.project"]
        let composeService = labels["com.docker.compose.service"]
        let mounts = (summary.Mounts ?? []).compactMap { mount -> ContainerMount? in
            guard let destination = ContainersViewModel.normalized(mount.Destination) else { return nil }
            let source = ContainersViewModel.normalized(mount.Source) ?? "-"
            return ContainerMount(
                type: "unknown",
                source: source,
                destination: destination,
                isReadOnly: false
            )
        }
        let rootfsMountPath = ContainerViewModel.inferRootFSMountPath(
            explicitPath: nil,
            labels: labels,
            mounts: mounts
        )

        self.init(
            id: summary.Id ?? "",
            name: name,
            image: summary.Image ?? "",
            state: state,
            ports: ports,
            createdAt: Date(timeIntervalSince1970: TimeInterval(summary.Created ?? 0)),
            composeProject: composeProject,
            composeService: composeService,
            labels: labels,
            cpuPercent: 0,
            memoryMB: 0,
            memoryLimitMB: 0,
            mounts: mounts,
            rootfsMountPath: rootfsMountPath
        )
    }
}
