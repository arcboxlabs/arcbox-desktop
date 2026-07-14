import FleetControlClient
import FleetPlatformClient
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
    var workspaces: [FleetWorkspace] = []
    var lastError: String?
    var platformError: String?
    var isWatching = false
    var isPerformingAction = false
    var isLoadingWorkspaces = false
    var reconnectAttempt = 0

    @ObservationIgnored
    private var client: FleetControlClient?

    @ObservationIgnored
    private var platformClient: FleetPlatformClient?

    @ObservationIgnored
    private var watchTask: Task<Void, Never>?

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
    func start(client: FleetControlClient?, platformClient: FleetPlatformClient? = nil) {
        stop()
        self.client = client
        self.platformClient = platformClient

        guard let client else {
            markUnavailable("Fleet control client is unavailable.")
            return
        }

        loadState = .connecting
        watchTask = Task { [weak self, client] in
            await self?.run(client: client)
        }
    }

    /// Load the workspaces available to the signed-in Platform identity.
    @discardableResult
    func loadWorkspaces() async -> Bool {
        guard let platformClient = requirePlatformClient() else { return false }

        isLoadingWorkspaces = true
        platformError = nil
        defer { isLoadingWorkspaces = false }

        do {
            workspaces = try await platformClient.listWorkspaces()
            return true
        } catch {
            platformError = FleetPlatformClient.userMessage(for: error)
            return false
        }
    }

    /// Stop the live watch loop. Existing snapshot data is retained.
    func stop() {
        watchTask?.cancel()
        watchTask = nil
        isWatching = false
        reconnectAttempt = 0
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

    /// Enroll this Mac with a platform-issued enrollment token.
    @discardableResult
    func enroll(token: String, controlPlane: String? = nil) async -> Bool {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            lastError = "Enrollment token is required."
            return false
        }
        guard let client = requireClient() else { return false }

        return await performAction("enroll") {
            let machineID = try await client.enroll(
                token: token,
                controlPlane: Self.normalized(controlPlane)
            )
            status = FleetAgentStatus(state: .enrolled, machineID: machineID)
            await refreshAfterMutation(client: client)
        }
    }

    /// Issue a workspace-scoped token and immediately enroll the local Fleet Agent.
    @discardableResult
    func enroll(workspaceID: String, controlPlane: String? = nil) async -> Bool {
        let workspaceID = workspaceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !workspaceID.isEmpty else {
            platformError = "A workspace is required for enrollment."
            return false
        }
        guard let client = requireClient(),
            let platformClient = requirePlatformClient()
        else { return false }

        return await performAction("enroll") {
            let enrollment = try await platformClient.createEnrollmentToken(
                workspaceID: workspaceID
            )
            let machineID = try await client.enroll(
                token: enrollment.token,
                controlPlane: Self.normalized(controlPlane)
            )
            status = FleetAgentStatus(state: .enrolled, machineID: machineID)
            platformError = nil
            await refreshAfterMutation(client: client)
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
            snapshot = nil
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

    private func run(client: FleetControlClient) async {
        await loadInitialState(client: client)
        await watchSnapshots(client: client)
    }

    private func loadInitialState(client: FleetControlClient) async {
        do {
            agentInfo = try await client.getAgentInfo()
            status = try await client.getStatus()
            settings = try await client.getSettings()
            lastError = nil
        } catch {
            markUnavailable(FleetControlClient.userMessage(for: error))
        }
    }

    private func watchSnapshots(client: FleetControlClient) async {
        while !Task.isCancelled {
            do {
                isWatching = true
                for try await snapshot in client.watchSnapshots() {
                    apply(snapshot)
                }

                guard !Task.isCancelled else { return }
                markWatchDisconnected("Fleet agent state stream ended.")
            } catch is CancellationError {
                return
            } catch {
                markWatchDisconnected(FleetControlClient.userMessage(for: error))
            }

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

    private func requirePlatformClient() -> FleetPlatformClient? {
        guard let platformClient else {
            platformError = "Fleet Platform client is unavailable."
            return nil
        }
        return platformClient
    }

    private func handle(_ error: Error) {
        let message: String
        if error is FleetPlatformError || error is URLError {
            message = FleetPlatformClient.userMessage(for: error)
            platformError = message
        } else {
            message = FleetControlClient.userMessage(for: error)
        }
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

    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
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
