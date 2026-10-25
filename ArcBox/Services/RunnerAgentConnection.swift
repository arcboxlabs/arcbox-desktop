import Foundation
import Observation
import RunnerAgentClient
import os

enum RunnerAgentConnectionState: Equatable {
    case idle
    case connecting
    case ready(RunnerAgentInfo)
    case unavailable(String)
}

enum RunnerAgentConnectionError: LocalizedError {
    case clientUnavailable
    case handshakeFailed(String)

    var errorDescription: String? {
        switch self {
        case .clientUnavailable:
            "Runner Agent control client is unavailable."
        case .handshakeFailed(let message):
            message
        }
    }
}

/// Owns the app-wide client transport to the independently managed Runner Agent.
///
/// This type never installs, launches, stops, or updates the Agent process. It
/// only maintains the local gRPC channel and proves readiness with GetAgentInfo.
@MainActor
@Observable
final class RunnerAgentConnection {
    private struct ReadinessProbe {
        let id: UUID
        let generation: UInt
        let task: Task<RunnerAgentInfo, Error>
    }

    private(set) var state: RunnerAgentConnectionState = .idle

    @ObservationIgnored
    private(set) var controlClient: RunnerAgentClient?

    @ObservationIgnored
    private var connectionTask: Task<Void, Never>?

    @ObservationIgnored
    private var connectionTaskID: UUID?

    @ObservationIgnored
    private var connectionTaskFinished = false

    @ObservationIgnored
    private var readinessProbe: ReadinessProbe?

    @ObservationIgnored
    private var generation: UInt = 0

    @ObservationIgnored
    private var isShuttingDown = false

    @ObservationIgnored
    private let socketPath: String

    init(socketPath: String = RunnerAgentClient.defaultSocketPath) {
        self.socketPath = socketPath
    }

    /// Starts the single app-wide client transport. This method is idempotent.
    func start() {
        guard controlClient == nil, !isShuttingDown else { return }

        generation &+= 1
        let currentGeneration = generation
        state = .connecting
        do {
            let client = try RunnerAgentClient(socketPath: socketPath)
            let taskID = UUID()
            controlClient = client
            connectionTaskID = taskID
            connectionTaskFinished = false
            connectionTask = Task { [weak self] in
                defer {
                    self?.markConnectionTaskFinished(
                        id: taskID,
                        generation: currentGeneration,
                        client: client
                    )
                }
                do {
                    Log.runners.info("Runner Agent control runConnections starting")
                    try await client.runConnections()
                    Log.runners.info("Runner Agent control runConnections ended")
                } catch is CancellationError {
                    Log.runners.info("Runner Agent control runConnections cancelled")
                } catch {
                    Log.runners.error(
                        "Runner Agent control runConnections failed: \(error.localizedDescription, privacy: .private)"
                    )
                }
            }
        } catch {
            state = .unavailable(RunnerAgentClient.userMessage(for: error))
        }
    }

    /// Returns the shared client after a bounded, single-flight readiness probe.
    func ensureReady() async throws -> any RunnerAgentEnrollmentControlling {
        start()
        guard !isShuttingDown, let controlClient else {
            throw RunnerAgentConnectionError.clientUnavailable
        }
        let currentGeneration = generation

        let probe: ReadinessProbe
        if let readinessProbe, readinessProbe.generation == currentGeneration {
            probe = readinessProbe
        } else {
            state = .connecting
            let newProbe = ReadinessProbe(
                id: UUID(),
                generation: currentGeneration,
                task: Task {
                    try await controlClient.getAgentInfo(
                        timeout: .seconds(10),
                        waitForReady: true
                    )
                }
            )
            readinessProbe = newProbe
            probe = newProbe
        }

        do {
            let info = try await probe.task.value
            try Task.checkCancellation()
            guard generation == currentGeneration, self.controlClient === controlClient else {
                throw RunnerAgentConnectionError.clientUnavailable
            }
            if clearReadinessProbe(id: probe.id, generation: currentGeneration) {
                state = .ready(info)
            }
            return controlClient
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard generation == currentGeneration, self.controlClient === controlClient else {
                throw RunnerAgentConnectionError.clientUnavailable
            }
            let message = RunnerAgentClient.userMessage(for: error)
            if clearReadinessProbe(id: probe.id, generation: currentGeneration) {
                state = .unavailable(message)
            }
            throw RunnerAgentConnectionError.handshakeFailed(message)
        }
    }

    /// Gracefully closes only Desktop's gRPC transport.
    ///
    /// The Agent service keeps running. If in-flight calls do not settle within
    /// the grace period, the transport task is cancelled as a bounded fallback.
    @discardableResult
    func shutdown(gracePeriod: Duration = .seconds(5)) async -> Bool {
        isShuttingDown = true
        generation &+= 1
        readinessProbe?.task.cancel()
        readinessProbe = nil

        let client = controlClient
        let task = connectionTask
        let taskID = connectionTaskID
        controlClient = nil
        client?.close()

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: gracePeriod)
        while taskID == connectionTaskID, !connectionTaskFinished, clock.now < deadline {
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                break
            }
        }

        let finishedGracefully = taskID == nil || connectionTaskFinished
        if !finishedGracefully {
            task?.cancel()
        }

        connectionTask = nil
        connectionTaskID = nil
        connectionTaskFinished = false
        state = .idle
        isShuttingDown = false
        return finishedGracefully
    }

    private func clearReadinessProbe(id: UUID, generation: UInt) -> Bool {
        guard readinessProbe?.id == id, readinessProbe?.generation == generation else {
            return false
        }
        readinessProbe = nil
        return true
    }

    private func markConnectionTaskFinished(
        id: UUID,
        generation: UInt,
        client: RunnerAgentClient
    ) {
        guard connectionTaskID == id else { return }
        connectionTaskFinished = true

        guard self.generation == generation, controlClient === client, !isShuttingDown else {
            return
        }
        state = .unavailable("Runner Agent connection stopped.")
    }
}

extension RunnerAgentConnection: RunnerAgentReadying {}
