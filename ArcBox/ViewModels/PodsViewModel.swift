import ArcBoxClient
import K8sClient
import OSLog
import SwiftUI

/// Detail tab for pods
enum PodDetailTab: String, CaseIterable, Identifiable {
    case info = "Info"
    case logs = "Logs"
    case terminal = "Terminal"

    var id: String { rawValue }
}

/// Pod list state
@MainActor
@Observable
class PodsViewModel {
    var pods: [PodViewModel] = []
    var selectedID: String? = nil
    var activeTab: PodDetailTab = .info
    var listWidth: CGFloat = 320
    var isLoading: Bool = false

    private var k8sClient: K8sClient?

    var podCount: Int { pods.count }
    var runningCount: Int { pods.filter(\.isRunning).count }

    var selectedPod: PodViewModel? {
        guard let id = selectedID else { return nil }
        return pods.first { $0.id == id }
    }

    func selectPod(_ id: String) {
        selectedID = id
    }

    /// Fetch kubeconfig via gRPC, create K8sClient, then load pods.
    /// Returns `true` if the request succeeded (even if the list is empty).
    @discardableResult
    func loadPods(client: ArcBoxClient?) async -> Bool {
        guard let client else {
            Log.pods.debug("No gRPC client available")
            return false
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let kubeconfigResponse: Arcbox_V1_KubernetesKubeconfigResponse = try await client.kubernetes.getKubeconfig(.init())
            let config = try KubeConfig(yaml: kubeconfigResponse.kubeconfig)
            let k8s = try K8sClient(config: config)
            self.k8sClient = k8s

            let podList = try await k8s.listAllPods()
            self.pods = podList.items.compactMap { Self.mapPod($0) }
            return true
        } catch {
            Log.pods.error("Error loading pods: \(error)")
            self.pods = []
            return false
        }
    }

    /// Clear all pod data when K8s is stopped.
    func clear() {
        k8sClient = nil
        pods = []
        selectedID = nil
    }

    // MARK: - Mapping

    private static func mapPod(_ pod: Pod) -> PodViewModel? {
        guard let meta = pod.metadata, let name = meta.name else { return nil }
        let uid = meta.uid ?? name

        let containers = pod.spec?.containers ?? []
        let statuses = pod.status?.containerStatuses ?? []
        let readyCount = statuses.filter { $0.ready == true }.count
        let restartCount = statuses.reduce(0) { $0 + ($1.restartCount ?? 0) }

        let phase: PodPhase
        switch pod.status?.phase {
        case "Running": phase = .running
        case "Pending": phase = .pending
        case "Succeeded": phase = .succeeded
        case "Failed": phase = .failed
        default: phase = .unknown
        }

        return PodViewModel(
            id: uid,
            name: name,
            namespace: meta.namespace ?? "default",
            phase: phase,
            containerCount: containers.count,
            readyCount: readyCount,
            restartCount: restartCount,
            createdAt: meta.creationTimestamp ?? Date()
        )
    }
}
