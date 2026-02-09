import Foundation

/// Mock data factory for SwiftUI previews and development
enum SampleData {
    // MARK: - Containers

    static let containers: [ContainerViewModel] = [
        ContainerViewModel(
            id: "a1b2c3d4e5f6",
            name: "web-frontend",
            image: "nginx:latest",
            state: .running,
            ports: [PortMapping(hostPort: 8080, containerPort: 80, protocol: "tcp")],
            createdAt: Date().addingTimeInterval(-3600 * 2),
            composeProject: "myapp",
            labels: [
                "com.docker.compose.project": "myapp",
                "com.docker.compose.service": "web",
                "maintainer": "dev@example.com",
            ],
            cpuPercent: 2.3,
            memoryMB: 45.2,
            memoryLimitMB: 512.0
        ),
        ContainerViewModel(
            id: "b2c3d4e5f6g7",
            name: "api-server",
            image: "node:20-alpine",
            state: .running,
            ports: [PortMapping(hostPort: 3000, containerPort: 3000, protocol: "tcp")],
            createdAt: Date().addingTimeInterval(-3600 * 2),
            composeProject: "myapp",
            labels: [
                "com.docker.compose.project": "myapp",
                "com.docker.compose.service": "api",
            ],
            cpuPercent: 8.1,
            memoryMB: 128.5,
            memoryLimitMB: 1024.0
        ),
        ContainerViewModel(
            id: "c3d4e5f6g7h8",
            name: "postgres-db",
            image: "postgres:15",
            state: .running,
            ports: [PortMapping(hostPort: 5432, containerPort: 5432, protocol: "tcp")],
            createdAt: Date().addingTimeInterval(-86400),
            composeProject: "myapp",
            labels: [
                "com.docker.compose.project": "myapp",
                "com.docker.compose.service": "db",
            ],
            cpuPercent: 1.2,
            memoryMB: 256.0,
            memoryLimitMB: 2048.0
        ),
        ContainerViewModel(
            id: "d4e5f6g7h8i9",
            name: "redis-cache",
            image: "redis:7-alpine",
            state: .stopped,
            ports: [],
            createdAt: Date().addingTimeInterval(-86400 * 3),
            composeProject: nil,
            labels: [:],
            cpuPercent: 0,
            memoryMB: 0,
            memoryLimitMB: 0
        ),
        ContainerViewModel(
            id: "e5f6g7h8i9j0",
            name: "dev-ubuntu",
            image: "ubuntu:22.04",
            state: .stopped,
            ports: [],
            createdAt: Date().addingTimeInterval(-86400 * 7),
            composeProject: nil,
            labels: ["purpose": "development"],
            cpuPercent: 0,
            memoryMB: 0,
            memoryLimitMB: 0
        ),
    ]

    // MARK: - Volumes

    static let volumes: [VolumeViewModel] = [
        VolumeViewModel(
            name: "postgres-data",
            driver: "local",
            mountPoint: "/var/lib/docker/volumes/postgres-data/_data",
            sizeBytes: 524_288_000,
            createdAt: Date().addingTimeInterval(-86400 * 30),
            inUse: true,
            containerNames: ["postgres-db"]
        ),
        VolumeViewModel(
            name: "redis-data",
            driver: "local",
            mountPoint: "/var/lib/docker/volumes/redis-data/_data",
            sizeBytes: 10_240_000,
            createdAt: Date().addingTimeInterval(-86400 * 14),
            inUse: false,
            containerNames: []
        ),
        VolumeViewModel(
            name: "node-modules-cache",
            driver: "local",
            mountPoint: "/var/lib/docker/volumes/node-modules-cache/_data",
            sizeBytes: 1_200_000_000,
            createdAt: Date().addingTimeInterval(-86400 * 7),
            inUse: true,
            containerNames: ["api-server"]
        ),
    ]

    // MARK: - Images

    static let images: [ImageViewModel] = [
        ImageViewModel(
            id: "sha256:abc123def456",
            repository: "nginx",
            tag: "latest",
            sizeBytes: 187_000_000,
            createdAt: Date().addingTimeInterval(-86400 * 5),
            inUse: true,
            os: "linux",
            architecture: "arm64"
        ),
        ImageViewModel(
            id: "sha256:bcd234efg567",
            repository: "node",
            tag: "20-alpine",
            sizeBytes: 178_000_000,
            createdAt: Date().addingTimeInterval(-86400 * 3),
            inUse: true,
            os: "linux",
            architecture: "arm64"
        ),
        ImageViewModel(
            id: "sha256:cde345fgh678",
            repository: "postgres",
            tag: "15",
            sizeBytes: 412_000_000,
            createdAt: Date().addingTimeInterval(-86400 * 10),
            inUse: true,
            os: "linux",
            architecture: "arm64"
        ),
        ImageViewModel(
            id: "sha256:def456ghi789",
            repository: "redis",
            tag: "7-alpine",
            sizeBytes: 32_000_000,
            createdAt: Date().addingTimeInterval(-86400 * 14),
            inUse: false,
            os: "linux",
            architecture: "arm64"
        ),
        ImageViewModel(
            id: "sha256:efg567hij890",
            repository: "ubuntu",
            tag: "22.04",
            sizeBytes: 77_000_000,
            createdAt: Date().addingTimeInterval(-86400 * 30),
            inUse: false,
            os: "linux",
            architecture: "arm64"
        ),
    ]

    // MARK: - Networks

    static let networks: [NetworkViewModel] = [
        NetworkViewModel(
            id: "abc123def456abc123def456",
            name: "bridge",
            driver: "bridge",
            scope: "local",
            createdAt: Date().addingTimeInterval(-86400 * 90),
            internal: false,
            attachable: false,
            containerCount: 2
        ),
        NetworkViewModel(
            id: "bcd234efg567bcd234efg567",
            name: "host",
            driver: "host",
            scope: "local",
            createdAt: Date().addingTimeInterval(-86400 * 90),
            internal: false,
            attachable: false,
            containerCount: 0
        ),
        NetworkViewModel(
            id: "cde345fgh678cde345fgh678",
            name: "none",
            driver: "null",
            scope: "local",
            createdAt: Date().addingTimeInterval(-86400 * 90),
            internal: false,
            attachable: false,
            containerCount: 0
        ),
        NetworkViewModel(
            id: "def456ghi789def456ghi789",
            name: "myapp_default",
            driver: "bridge",
            scope: "local",
            createdAt: Date().addingTimeInterval(-86400 * 2),
            internal: false,
            attachable: true,
            containerCount: 3
        ),
    ]

    // MARK: - Machines

    static let machines: [MachineViewModel] = [
        MachineViewModel(
            id: "machine-001",
            name: "dev-workspace",
            distro: DistroInfo(name: "ubuntu", version: "22.04", displayName: "Ubuntu 22.04 LTS"),
            state: .running,
            cpuCores: 4,
            memoryGB: 8,
            diskGB: 64,
            ipAddress: "192.168.64.2",
            createdAt: Date().addingTimeInterval(-86400 * 14)
        ),
        MachineViewModel(
            id: "machine-002",
            name: "test-env",
            distro: DistroInfo(name: "fedora", version: "39", displayName: "Fedora 39"),
            state: .stopped,
            cpuCores: 2,
            memoryGB: 4,
            diskGB: 32,
            ipAddress: nil,
            createdAt: Date().addingTimeInterval(-86400 * 7)
        ),
    ]
}
