import Foundation

/// Kubernetes service types
enum ServiceType: String, CaseIterable, Identifiable {
    case clusterIP = "ClusterIP"
    case nodePort = "NodePort"
    case loadBalancer = "LoadBalancer"
    case externalName = "ExternalName"

    var id: String { rawValue }
}

/// Service port mapping
struct ServicePort: Hashable {
    let port: UInt16
    let targetPort: String
    let `protocol`: String
}

/// Service view model for UI display
struct ServiceViewModel: Identifiable, Hashable {
    let id: String
    let name: String
    let namespace: String
    let type: ServiceType
    let clusterIP: String?
    let ports: [ServicePort]
    let createdAt: Date

    var portsDisplay: String {
        ports.map { "\($0.port):\($0.targetPort)/\($0.protocol)" }.joined(separator: ", ")
    }

    var createdAgo: String {
        relativeTime(from: createdAt)
    }
}
