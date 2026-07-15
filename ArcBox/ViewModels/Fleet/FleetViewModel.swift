import FleetControlClient
import Foundation
import SwiftUI
import os

/// Fleet runner page loading state.
enum FleetLoadState: Equatable {
    case idle
    case connecting
    case unavailable(String)
    case ready(FleetAgentSnapshot)
    case failed(String)
}

/// View model for the local fleet-agent control surface.
@MainActor
@Observable
final class FleetViewModel {
    var loadState: FleetLoadState = .idle
    var agentInfo: FleetAgentInfo?
    var status: FleetAgentStatus?
    var snapshot: FleetAgentSnapshot?
    var settings: FleetAgentSettings?
    var lastError: String?
    var isWatching = false
    var isPerformingAction = false
    var reconnectAttempt = 0

    @ObservationIgnored
    private var client: FleetControlClient?

    @ObservationIgnored
    private var watchTask: Task<Void, Never>?

    @ObservationIgnored
    private var snapshotObserver: (@MainActor @Sendable (FleetAgentSnapshot) -> Void)?

    @ObservationIgnored
    private var watchGeneration = UUID()

    var isReady: Bool {
        if case .ready = loadState { return true }
        return false
    }

    var machineID: String? {
        snapshot?.machineID ?? status?.machineID
    }

    var isEnrolled: Bool {
        if let snapshot {
            return snapshot.enrollment != .unenrolled && snapshot.enrollment != .unspecified
        }
        switch status?.state {
        case .enrolled, .draining, .detached, .credentialRejected:
            return true
        case .unspecified, .unenrolled, .unrecognized, nil:
            return false
        }
    }

    /// Begin the handshake and state watch loop.
    func start(
        client: FleetControlClient?,
        onSnapshot: (@MainActor @Sendable (FleetAgentSnapshot) -> Void)? = nil
    ) {
        stop()
        self.client = client
        snapshotObserver = onSnapshot

        guard let client else {
            markUnavailable("Fleet control client is unavailable.")
            return
        }

        loadState = .connecting
        let generation = watchGeneration
        watchTask = Task { [weak self, client] in
            await self?.run(client: client, generation: generation)
        }
    }

    /// Stop the live watch loop. Existing snapshot data is retained.
    func stop() {
        watchGeneration = UUID()
        watchTask?.cancel()
        watchTask = nil
        isWatching = false
        reconnectAttempt = 0
        snapshotObserver = nil
    }

    /// Refresh agent handshake metadata without restarting the watch loop.
    @discardableResult
    func getAgentInfo() async -> Bool {
        guard let client = requireClient() else { return false }

        do {
            agentInfo = try await client.getAgentInfo()
            lastError = nil
            return true
        } catch {
            handle(error)
            return false
        }
    }

    /// Refresh coarse lifecycle status.
    @discardableResult
    func getStatus() async -> Bool {
        guard let client = requireClient() else { return false }

        do {
            status = try await client.getStatus()
            lastError = nil
            return true
        } catch {
            handle(error)
            return false
        }
    }

    /// Refresh current settings.
    @discardableResult
    func getSettings() async -> Bool {
        guard let client = requireClient() else { return false }

        do {
            settings = try await client.getSettings()
            lastError = nil
            return true
        } catch {
            handle(error)
            return false
        }
    }

    /// Drain this host: stop accepting new offers and finish in-flight work.
    @discardableResult
    func drain() async -> Bool {
        guard let client = requireClient() else { return false }

        return await performAction("drain") {
            try await client.drain()
            await refreshAfterMutation(client: client)
        }
    }

    /// Resume accepting new offers after draining.
    @discardableResult
    func resume() async -> Bool {
        guard let client = requireClient() else { return false }

        return await performAction("resume") {
            try await client.resume()
            await refreshAfterMutation(client: client)
        }
    }

    /// Remove this Mac's persisted fleet enrollment.
    @discardableResult
    func unenroll() async -> Bool {
        guard let client = requireClient() else { return false }

        return await performAction("unenroll") {
            try await client.unenroll()
            // Watch publishes the authoritative unenrolled snapshot before
            // this RPC returns. Retain it for coordinator reconciliation.
            settings = nil
            status = FleetAgentStatus(state: .unenrolled, machineID: nil)
            await refreshAfterMutation(client: client)
        }
    }

    /// Apply a partial settings update.
    @discardableResult
    func updateSettings(_ update: FleetSettingsUpdate) async -> Bool {
        guard let client = requireClient() else { return false }
        guard !update.isEmpty else {
            return await getSettings()
        }

        return await performAction("update settings") {
            settings = try await client.updateSettings(update)
        }
    }

    /// Apply a partial settings update.
    @discardableResult
    func updateSettings(
        loadCeiling: Double? = nil,
        memFloorMib: UInt64? = nil,
        linuxRunnerImage: String? = nil,
        gateway: String? = nil,
        dockerMode: FleetDockerMode? = nil,
        runnerScript: String? = nil,
        participate: Bool? = nil
    ) async -> Bool {
        await updateSettings(
            FleetSettingsUpdate(
                loadCeiling: loadCeiling,
                memFloorMib: memFloorMib,
                linuxRunnerImage: linuxRunnerImage,
                gateway: gateway,
                dockerMode: dockerMode,
                runnerScript: runnerScript,
                participate: participate
            )
        )
    }

    private func run(client: FleetControlClient, generation: UUID) async {
        await loadInitialState(client: client, generation: generation)
        guard generation == watchGeneration else { return }
        await watchSnapshots(client: client, generation: generation)
    }

    private func loadInitialState(client: FleetControlClient, generation: UUID) async {
        do {
            let agentInfo = try await client.getAgentInfo()
            let status = try await client.getStatus()
            let settings = try await client.getSettings()
            guard generation == watchGeneration else { return }
            self.agentInfo = agentInfo
            self.status = status
            self.settings = settings
            lastError = nil
        } catch {
            guard generation == watchGeneration else { return }
            markUnavailable(FleetControlClient.userMessage(for: error))
        }
    }

    private func watchSnapshots(client: FleetControlClient, generation: UUID) async {
        while !Task.isCancelled, generation == watchGeneration {
            do {
                isWatching = true
                for try await snapshot in client.watchSnapshots() {
                    guard generation == watchGeneration else { return }
                    apply(snapshot)
                }

                guard !Task.isCancelled, generation == watchGeneration else { return }
                markWatchDisconnected("Fleet agent state stream ended.")
            } catch is CancellationError {
                return
            } catch {
                guard generation == watchGeneration else { return }
                markWatchDisconnected(FleetControlClient.userMessage(for: error))
            }

            guard generation == watchGeneration else { return }
            isWatching = false
            reconnectAttempt += 1
            try? await Task.sleep(for: .seconds(reconnectDelaySeconds))
        }
    }

    private func apply(_ snapshot: FleetAgentSnapshot) {
        self.snapshot = snapshot
        self.settings = snapshot.settings ?? settings
        self.status = Self.status(from: snapshot)
        self.loadState = .ready(snapshot)
        self.lastError = nil
        self.isWatching = true
        self.reconnectAttempt = 0
        snapshotObserver?(snapshot)
    }

    private func refreshAfterMutation(client: FleetControlClient) async {
        do {
            status = try await client.getStatus()
            settings = try await client.getSettings()
            lastError = nil
        } catch {
            handle(error)
        }
    }

    private func performAction(
        _ label: String,
        operation: () async throws -> Void
    ) async -> Bool {
        isPerformingAction = true
        lastError = nil
        defer { isPerformingAction = false }

        do {
            try await operation()
            return true
        } catch {
            Log.fleet.error("Fleet \(label, privacy: .public) failed: \(error.localizedDescription, privacy: .private)")
            handle(error)
            return false
        }
    }

    private func requireClient() -> FleetControlClient? {
        guard let client else {
            markUnavailable("Fleet control client is unavailable.")
            return nil
        }
        return client
    }

    private func handle(_ error: Error) {
        let message = FleetControlClient.userMessage(for: error)
        lastError = message
        loadState = snapshot == nil ? .unavailable(message) : .failed(message)
    }

    private func markUnavailable(_ message: String) {
        lastError = message
        isWatching = false
        loadState = .unavailable(message)
    }

    private func markWatchDisconnected(_ message: String) {
        lastError = message
        loadState = snapshot == nil ? .unavailable(message) : .failed(message)
    }

    private var reconnectDelaySeconds: Int64 {
        Int64(min(30, 1 << min(reconnectAttempt, 5)))
    }

    private static func status(from snapshot: FleetAgentSnapshot) -> FleetAgentStatus {
        let state: FleetConnectionState
        switch snapshot.enrollment {
        case .unenrolled:
            state = .unenrolled
        case .attaching, .attached:
            state = snapshot.isDraining ? .draining : .enrolled
        case .detached:
            state = .detached
        case .credentialRejected:
            state = .credentialRejected
        case .unspecified:
            state = .unspecified
        case .unrecognized(let value):
            state = .unrecognized(value)
        }
        return FleetAgentStatus(state: state, machineID: snapshot.machineID)
    }
}
