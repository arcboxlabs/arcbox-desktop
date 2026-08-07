import ArcBoxClient
import Foundation
import K8sClient
import OSLog
import Observation

enum KubernetesLifecycle: Equatable {
    enum Operation: Equatable {
        case status
        case start
        case stop
    }

    case checking
    case disabled
    case starting
    case ready
    case stopping
    case failed(Operation, String)

    var toggleIsOn: Bool {
        switch self {
        case .starting, .ready, .stopping, .failed(.stop, _):
            true
        default:
            false
        }
    }

    var canToggle: Bool {
        switch self {
        case .disabled, .ready, .failed(.start, _), .failed(.stop, _):
            true
        default:
            false
        }
    }
}

enum KubernetesStreamPhase: Equatable {
    case connecting
    case live
    case reconnecting(attempt: Int, lastError: String?)
}

struct KubernetesStatus: Equatable, Sendable {
    let running: Bool
    let apiReady: Bool

    var isReady: Bool { running && apiReady }
}

@MainActor
protocol KubernetesControlClient: AnyObject {
    func kubernetesStatus() async throws -> KubernetesStatus
    func startKubernetes() async throws
    func stopKubernetes() async throws
    func kubernetesKubeconfig() async throws -> String
}

extension ArcBoxClient: KubernetesControlClient {
    func kubernetesStatus() async throws -> KubernetesStatus {
        let response: Arcbox_V1_KubernetesStatusResponse = try await kubernetes.status(
            .init(), options: Self.defaultCallOptions
        )
        return KubernetesStatus(running: response.running, apiReady: response.apiReady)
    }

    func startKubernetes() async throws {
        let response: Arcbox_V1_KubernetesStartResponse = try await kubernetes.start(
            .init(), options: Self.defaultCallOptions
        )
        Log.pods.info(
            "Kubernetes start: running=\(response.running) apiReady=\(response.apiReady) endpoint=\(response.endpoint)"
        )
    }

    func stopKubernetes() async throws {
        let _: Arcbox_V1_KubernetesStopResponse = try await kubernetes.stop(
            .init(), options: Self.defaultCallOptions
        )
    }

    func kubernetesKubeconfig() async throws -> String {
        let response: Arcbox_V1_KubernetesKubeconfigResponse =
            try await kubernetes
            .getKubeconfig(.init(), options: Self.defaultCallOptions)
        return response.kubeconfig
    }
}

/// Owns the Kubernetes control state, the one API client, and both resource streams.
@MainActor
@Observable
final class KubernetesState {
    private static let minBackoff = Duration.seconds(2)
    private static let maxBackoff = Duration.seconds(15)

    private(set) var lifecycle: KubernetesLifecycle

    let podsModel = PodsViewModel()
    let servicesModel = ServicesViewModel()

    private var k8sClient: K8sClient?
    private var clientResolution:
        (
            generation: Int,
            task: Task<K8sClient, Error>
        )?
    private var podsTask: Task<Void, Never>?
    private var servicesTask: Task<Void, Never>?
    private var sessionClientID: ObjectIdentifier?
    private var statusGeneration = 0
    private var generation = 0

    init(lifecycle: KubernetesLifecycle = .checking) {
        self.lifecycle = lifecycle
    }

    func checkStatus(client: (any KubernetesControlClient)?) async {
        guard let client else {
            statusGeneration &+= 1
            lifecycle = .failed(.status, "ArcBox daemon is unavailable.")
            return
        }

        switch lifecycle {
        case .starting, .stopping:
            return
        default:
            break
        }

        let previousLifecycle = lifecycle
        statusGeneration &+= 1
        let statusGeneration = self.statusGeneration
        if previousLifecycle != .ready {
            lifecycle = .checking
        }

        do {
            let status = try await client.kubernetesStatus()
            guard statusGeneration == self.statusGeneration else { return }
            if status.isReady {
                setReady(client: client)
            } else {
                endSession()
                lifecycle = .disabled
                Analytics.register(["k8s_active": false])
            }
        } catch is CancellationError {
            guard statusGeneration == self.statusGeneration else { return }
            lifecycle = previousLifecycle
        } catch {
            guard statusGeneration == self.statusGeneration else { return }
            Log.pods.error(
                "Error checking Kubernetes status: \(error.localizedDescription, privacy: .private)"
            )
            ErrorReporting.capture(error, domain: .kubernetes, operation: "check_status")
            lifecycle = .failed(.status, ArcBoxClient.userMessage(for: error))
        }
    }

    func start(client: (any KubernetesControlClient)?) async {
        guard let client else {
            lifecycle = .failed(.start, "ArcBox daemon is unavailable.")
            return
        }
        switch lifecycle {
        case .disabled, .failed(.start, _):
            break
        default:
            return
        }

        let previousLifecycle = lifecycle
        statusGeneration &+= 1
        lifecycle = .starting
        let startedAt = CFAbsoluteTimeGetCurrent()

        do {
            try await client.startKubernetes()
            for attempt in 0..<30 {
                try Task.checkCancellation()
                if attempt > 0 {
                    try await Task.sleep(for: .seconds(2))
                }
                if try await client.kubernetesStatus().isReady {
                    setReady(client: client)
                    Analytics.capture(
                        .k8sEnabled,
                        properties: ["duration_ms": Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)]
                    )
                    return
                }
            }

            endSession()
            lifecycle = .failed(.start, "Kubernetes failed to start within 60 seconds.")
            Log.pods.warning("Kubernetes start timed out after 60s")
        } catch is CancellationError {
            lifecycle = previousLifecycle
        } catch {
            Log.pods.error(
                "Error starting Kubernetes: \(error.localizedDescription, privacy: .private)"
            )
            ErrorReporting.capture(error, domain: .kubernetes, operation: "start")
            endSession()
            lifecycle = .failed(.start, ArcBoxClient.userMessage(for: error))
        }
    }

    func stop(client: (any KubernetesControlClient)?) async {
        guard let client else {
            lifecycle = .failed(.stop, "ArcBox daemon is unavailable.")
            return
        }
        switch lifecycle {
        case .ready, .failed(.stop, _):
            break
        default:
            return
        }

        let previousLifecycle = lifecycle
        statusGeneration &+= 1
        lifecycle = .stopping

        do {
            try await client.stopKubernetes()
            endSession()
            lifecycle = .disabled
            Analytics.register(["k8s_active": false])
            Analytics.capture(.k8sDisabled)
        } catch is CancellationError {
            lifecycle = previousLifecycle
        } catch {
            Log.pods.error(
                "Error stopping Kubernetes: \(error.localizedDescription, privacy: .private)"
            )
            ErrorReporting.capture(error, domain: .kubernetes, operation: "stop")
            lifecycle = .failed(.stop, ArcBoxClient.userMessage(for: error))
        }
    }

    func retryStreams(client: (any KubernetesControlClient)?) {
        guard lifecycle == .ready, let client else { return }
        startSession(client: client)
    }

    // MARK: - Session lifecycle

    private func setReady(client: any KubernetesControlClient) {
        let clientID = ObjectIdentifier(client)
        lifecycle = .ready
        Analytics.register(["k8s_active": true])
        guard sessionClientID != clientID else { return }
        startSession(client: client)
    }

    private func startSession(client: any KubernetesControlClient) {
        generation &+= 1
        cancelSessionWork()
        k8sClient = nil
        sessionClientID = ObjectIdentifier(client)
        podsModel.streamPhase = .connecting
        servicesModel.streamPhase = .connecting

        let generation = self.generation
        podsTask = Task { [weak self] in
            await self?.supervise(
                self?.podsModel,
                operation: "watch_pods",
                generation: generation,
                client: client
            ) { $0.podStream() }
        }
        servicesTask = Task { [weak self] in
            await self?.supervise(
                self?.servicesModel,
                operation: "watch_services",
                generation: generation,
                client: client
            ) { $0.serviceStream() }
        }
    }

    private func cancelSessionWork() {
        podsTask?.cancel()
        podsTask = nil
        servicesTask?.cancel()
        servicesTask = nil
        clientResolution?.task.cancel()
        clientResolution = nil
    }

    private func endSession() {
        generation &+= 1
        cancelSessionWork()
        sessionClientID = nil
        k8sClient = nil
        podsModel.clear()
        servicesModel.clear()
    }

    // MARK: - Watch

    private func supervise<Model: K8sListModel>(
        _ model: Model?,
        operation: String,
        generation: Int,
        client: any KubernetesControlClient,
        stream: @escaping @Sendable (K8sClient) -> AsyncThrowingStream<[Model.Resource], any Error>
    ) async {
        guard let model else { return }
        var failures = 0

        while !Task.isCancelled, generation == self.generation {
            var delivered = false
            var lastError: String?
            var used: K8sClient?

            do {
                let k8s = try await resolveClient(client, generation: generation)
                guard generation == self.generation else { return }
                used = k8s

                for try await items in stream(k8s) {
                    guard generation == self.generation else { return }
                    model.apply(items)
                    model.streamPhase = .live
                    delivered = true
                }
            } catch is CancellationError {
                return
            } catch {
                guard generation == self.generation else { return }
                lastError = ArcBoxClient.userMessage(for: error)
                Log.pods.error(
                    "Kubernetes \(operation, privacy: .public) failed: \(error.localizedDescription, privacy: .private)"
                )
                ErrorReporting.capture(error, domain: .kubernetes, operation: operation)
                if let used {
                    invalidateClient(ifCurrent: used)
                }
            }

            guard !Task.isCancelled, generation == self.generation else { return }
            failures = delivered ? 1 : failures + 1
            model.streamPhase = .reconnecting(
                attempt: failures,
                lastError: lastError
            )
            do {
                try await Task.sleep(for: Self.backoff(afterFailures: failures))
            } catch {
                return
            }
        }
    }

    private static func backoff(afterFailures failures: Int) -> Duration {
        let doubled = minBackoff * Double(1 << min(failures - 1, 3))
        return min(doubled, maxBackoff)
    }

    private func invalidateClient(ifCurrent client: K8sClient) {
        if k8sClient === client {
            k8sClient = nil
        }
    }

    private func resolveClient(
        _ client: any KubernetesControlClient,
        generation: Int
    ) async throws -> K8sClient {
        if let k8sClient {
            return k8sClient
        }
        if let clientResolution, clientResolution.generation == generation {
            return try await clientResolution.task.value
        }

        let task = Task<K8sClient, Error> {
            let kubeconfig = try await client.kubernetesKubeconfig()
            return try K8sClient(config: try KubeConfig(yaml: kubeconfig))
        }
        clientResolution = (generation, task)

        do {
            let created = try await task.value
            guard generation == self.generation else { throw CancellationError() }
            if clientResolution?.generation == generation {
                clientResolution = nil
            }
            k8sClient = created
            return created
        } catch {
            if clientResolution?.generation == generation {
                clientResolution = nil
            }
            throw error
        }
    }
}

@MainActor
protocol K8sListModel: AnyObject {
    associatedtype Resource: K8sResource
    var streamPhase: KubernetesStreamPhase { get set }
    func apply(_ items: [Resource])
    func clear()
}

extension PodsViewModel: K8sListModel {}
extension ServicesViewModel: K8sListModel {}
