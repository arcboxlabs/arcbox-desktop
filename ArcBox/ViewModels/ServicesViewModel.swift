import Foundation
import K8sClient
import Observation

/// Service list state
@MainActor
@Observable
class ServicesViewModel {
    var services: [ServiceViewModel] = [] {
        didSet {
            if let selectedID, !services.contains(where: { $0.id == selectedID }) {
                self.selectedID = nil
            }
        }
    }
    var selectedID: String?
    var streamPhase: KubernetesStreamPhase = .connecting
    var lastStreamUpdate: ContinuousClock.Instant?
    var searchText: String = ""
    var isSearching: Bool = false

    var serviceCount: Int { services.count }
    var filteredServices: [ServiceViewModel] {
        guard !searchText.isEmpty else { return services }
        let query = searchText.lowercased()
        return services.filter {
            $0.name.lowercased().contains(query)
                || $0.namespace.lowercased().contains(query)
                || $0.type.rawValue.lowercased().contains(query)
                || ($0.clusterIP?.lowercased().contains(query) ?? false)
                || $0.portsDisplay.lowercased().contains(query)
        }
    }

    var selectedService: ServiceViewModel? {
        guard let id = selectedID else { return nil }
        return services.first { $0.id == id }
    }

    /// Replace the list with a watch snapshot. Called by ``KubernetesState``, which owns the
    /// client and the stream.
    func apply(_ items: [K8sService]) {
        services = items.compactMap { Self.mapService($0) }
        lastStreamUpdate = ContinuousClock().now
    }

    /// Clear all service data when K8s is stopped.
    func clear() {
        services = []
        selectedID = nil
        streamPhase = .connecting
        lastStreamUpdate = nil
    }

    // MARK: - Mapping

    private static func mapService(_ svc: K8sService) -> ServiceViewModel? {
        guard let meta = svc.metadata, let name = meta.name else { return nil }
        let uid = meta.uid ?? name

        let serviceType: ServiceType
        switch svc.spec?.type {
        case "ClusterIP": serviceType = .clusterIP
        case "NodePort": serviceType = .nodePort
        case "LoadBalancer": serviceType = .loadBalancer
        case "ExternalName": serviceType = .externalName
        default: serviceType = .clusterIP
        }

        let ports: [ServicePort] = (svc.spec?.ports ?? []).map { p in
            let targetStr: String
            if let tp = p.targetPort {
                switch tp {
                case .int(let v): targetStr = "\(v)"
                case .string(let v): targetStr = v
                }
            } else {
                targetStr = "\(p.port ?? 0)"
            }
            return ServicePort(
                port: UInt16(p.port ?? 0),
                targetPort: targetStr,
                protocol: p.protocol ?? "TCP"
            )
        }

        return ServiceViewModel(
            id: uid,
            name: name,
            namespace: meta.namespace ?? "default",
            type: serviceType,
            clusterIP: svc.spec?.clusterIP,
            ports: ports,
            createdAt: meta.creationTimestamp ?? Date()
        )
    }
}
