import ArcBoxClient
import OSLog
import SwiftUI

/// Shared Kubernetes cluster state observed by both Pods and Services views.
@MainActor
@Observable
class KubernetesState {
    var enabled: Bool = false
    var isStarting: Bool = false
    var isStopping: Bool = false

    /// Check current K8s cluster status via gRPC.
    func checkStatus(client: ArcBoxClient?) async {
        guard let client else { return }
        do {
            let status: Arcbox_V1_KubernetesStatusResponse = try await client.kubernetes.status(.init())
            self.enabled = status.running && status.apiReady
        } catch {
            self.enabled = false
        }
    }

    /// Start the Kubernetes cluster and wait until it is fully ready.
    func start(client: ArcBoxClient?) async {
        guard let client, !isStarting else { return }
        isStarting = true
        do {
            let response: Arcbox_V1_KubernetesStartResponse = try await client.kubernetes.start(.init())
            Log.pods.info("Kubernetes start: running=\(response.running) apiReady=\(response.apiReady) endpoint=\(response.endpoint)")

            // Poll until API is fully ready or timeout (~60s).
            for attempt in 0..<30 {
                if attempt > 0 {
                    try await Task.sleep(for: .seconds(2))
                }
                let status: Arcbox_V1_KubernetesStatusResponse = try await client.kubernetes.status(.init())
                if status.running && status.apiReady {
                    self.enabled = true
                    break
                }
            }
        } catch {
            Log.pods.error("Error starting Kubernetes: \(error)")
        }
        isStarting = false
    }

    /// Stop the Kubernetes cluster.
    func stop(client: ArcBoxClient?) async {
        guard let client else { return }
        isStopping = true
        do {
            let _: Arcbox_V1_KubernetesStopResponse = try await client.kubernetes.stop(.init())
            self.enabled = false
        } catch {
            Log.pods.error("Error stopping Kubernetes: \(error)")
        }
        isStopping = false
    }
}
