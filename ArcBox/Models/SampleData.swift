import Foundation

/// Mock data factory for SwiftUI previews and development
enum SampleData {
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
            architecture: "arm64",
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
            architecture: "arm64",
            ipAddress: nil,
            createdAt: Date().addingTimeInterval(-86400 * 7)
        ),
    ]

    // MARK: - Pods

    static let pods: [PodViewModel] = []

    // MARK: - Services

    static let services: [ServiceViewModel] = []

    // MARK: - Sandboxes

    static let sandboxes: [SandboxViewModel] = []

    // MARK: - Templates

    static let templates: [TemplateViewModel] = [
        TemplateViewModel(
            id: "tmpl-python-base",
            name: "Python Base",
            cpuCount: 2,
            memoryMB: 512,
            createdAt: Date().addingTimeInterval(-86400 * 30),
            updatedAt: Date().addingTimeInterval(-86400 * 2),
            sandboxCount: 2
        ),
        TemplateViewModel(
            id: "tmpl-python-data",
            name: "Python Data Science",
            cpuCount: 4,
            memoryMB: 1024,
            createdAt: Date().addingTimeInterval(-86400 * 14),
            updatedAt: Date().addingTimeInterval(-86400),
            sandboxCount: 1
        ),
        TemplateViewModel(
            id: "tmpl-node-base",
            name: "Node.js Base",
            cpuCount: 2,
            memoryMB: 512,
            createdAt: Date().addingTimeInterval(-86400 * 7),
            updatedAt: Date().addingTimeInterval(-86400 * 3),
            sandboxCount: 1
        ),
    ]
}
