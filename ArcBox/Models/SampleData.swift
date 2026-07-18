import Foundation

/// Mock data factory for SwiftUI previews and development
enum SampleData {
    // MARK: - Machines

    // Machines come from the live gRPC API; no sample data.

    // MARK: - Pods

    static let pods: [PodViewModel] = []

    // MARK: - Services

    static let services: [ServiceViewModel] = []

    // MARK: - Sandboxes

    // Sandboxes come from the live gRPC API; no sample data.
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
