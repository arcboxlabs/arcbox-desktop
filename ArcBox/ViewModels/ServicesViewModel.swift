import ArcBoxClient
import K8sClient
import OSLog
import SwiftUI

/// Detail tab for services
enum ServiceDetailTab: String, CaseIterable, Identifiable {
    case info = "Info"

    var id: String { rawValue }
}

/// Service list state
@MainActor
@Observable
class ServicesViewModel {
    var services: [ServiceViewModel] = []
    var selectedID: String? = nil
    var activeTab: ServiceDetailTab = .info
    var listWidth: CGFloat = 320
    var isLoading: Bool = false

    private var k8sClient: K8sClient?

    var serviceCount: Int { services.count }

    var selectedService: ServiceViewModel? {
        guard let id = selectedID else { return nil }
        return services.first { $0.id == id }
    }

    func selectService(_ id: String) {
        selectedID = id
    }

    /// Fetch kubeconfig via gRPC, create K8sClient, then load services.
    /// Returns `true` if the request succeeded (even if the list is empty).
    @discardableResult
    func loadServices(client: ArcBoxClient?) async -> Bool {
        guard let client else {
            Log.services.debug("No gRPC client available")
            return false
        }

        isLoading = true
        defer { isLoading = false }

        do {
            if k8sClient == nil {
                let kubeconfigResponse: Arcbox_V1_KubernetesKubeconfigResponse = try await client.kubernetes.getKubeconfig(.init(), options: ArcBoxClient.defaultCallOptions)
                let config = try KubeConfig(yaml: kubeconfigResponse.kubeconfig)
                self.k8sClient = try K8sClient(config: config)
            }

            guard let k8s = k8sClient else { return false }
            let serviceList = try await k8s.listAllServices()
            self.services = serviceList.items.compactMap { Self.mapService($0) }
            return true
        } catch {
            Log.services.error("Error loading services: \(error.localizedDescription, privacy: .public)")
            self.services = []
            self.k8sClient = nil
            return false
        }
    }

    /// Clear all service data when K8s is stopped.
    func clear() {
        k8sClient = nil
        services = []
        selectedID = nil
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
