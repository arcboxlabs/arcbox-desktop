import FleetControlClient
import Foundation
import SwiftUI
import os

/// Fleet runner page loading state.
enum FleetLoadState: Equatable {
    case idle
    case connecting
    case unavailable(String)
    case ready
    case failed(String)
}

/// Whether the connected Agent exposes the complete VM settings contract.
enum FleetVMSettingsAvailability: Equatable {
    case loading
    case unavailable(String)
    case unsupported
    case missingSettings
    case available
}

/// Progress for the long-running macOS runner image preparation RPC.
struct FleetImagePreparationProgress: Equatable {
    let stage: String
    let detail: String
    let fraction: Double

    var displayDescription: String {
        detail.isEmpty ? stage.capitalized : "\(stage.capitalized): \(detail)"
    }
}

/// Observable state for macOS runner image preparation.
enum FleetImagePreparationState: Equatable {
    case idle
    case preparing(FleetImagePreparationProgress)
    case completed(reference: String)
    case failed(String)

    var isPreparing: Bool {
        if case .preparing = self { return true }
        return false
    }
}

private enum FleetAgentFeature {
    static let vmSettings = "vm-settings"
    static let macOSImagePrepare = "macos-image-prepare"
    static let vmBackend = "vm-backend"
}

private enum FleetImagePreparationError: LocalizedError {
    case targetDidNotConverge(String)

    var errorDescription: String? {
        switch self {
        case .targetDidNotConverge(let reference):
            "Fleet Agent finished preparing \(reference), but did not report it as the current image."
        }
    }
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
    var imagePreparationState: FleetImagePreparationState = .idle

    @ObservationIgnored
    private var client: (any FleetControlServicing)?

    @ObservationIgnored
    private var watchTask: Task<Void, Never>?

    @ObservationIgnored
    private var imagePreparationTask: Task<Void, Never>?

    @ObservationIgnored
    private var snapshotObserver: (@MainActor @Sendable (FleetAgentSnapshot) -> Void)?

    @ObservationIgnored
    private var watchGeneration = UUID()

    @ObservationIgnored
    private var imagePreparationGeneration = UUID()

    var isReady: Bool {
        if case .ready = loadState { return true }
        return false
    }

    var vmSettingsAvailability: FleetVMSettingsAvailability {
        Self.resolveVMSettingsAvailability(
            agentInfo: agentInfo,
            settings: settings,
            loadState: loadState
        )
    }

    var supportsMacOSImagePreparation: Bool {
        agentInfo?.supportsFeature(FleetAgentFeature.macOSImagePrepare) == true
    }

    var isVMBackendActive: Bool {
        agentInfo?.supportsFeature(FleetAgentFeature.vmBackend) == true
    }

    var canBeginMacOSRunnerImagePreparation: Bool {
        vmSettingsAvailability == .available
            && supportsMacOSImagePreparation
            && !isPerformingAction
            && !imagePreparationState.isPreparing
            && settings?.macosRunnerImage != nil
    }

    var runnerImageReadiness: FleetRunnerImageReadiness {
        guard vmSettingsAvailability == .available,
            supportsMacOSImagePreparation
        else {
            return .hidden
        }

        switch imagePreparationState {
        case .preparing(let progress):
            return .preparing(progress)
        case .failed(let message):
            return .failed(message)
        case .completed(let reference):
            if requiresAgentRestartForVM {
                return .restartRequired
            }
            return .completed(reference: reference)
        case .idle:
            if requiresAgentRestartForVM {
                return .restartRequired
            }
            guard let image = settings?.macosRunnerImage,
                image.isPending
            else {
                return .hidden
            }
            return .pending(reference: image.target)
        }
    }

    var requiresAgentRestartForVM: Bool {
        guard let vmMode = settings?.vmMode,
            let image = settings?.macosRunnerImage
        else {
            return false
        }

        if vmMode.isPending {
            switch vmMode.target {
            case .disabled:
                return true
            case .auto, .enabled:
                guard !image.isPending else { return false }
                return isVMBackendActive || image.current == image.target
            case .unspecified, .unrecognized:
                return false
            }
        }

        guard vmMode.target != .disabled,
            image.current == image.target
        else {
            return false
        }
        return !isVMBackendActive
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
        client: (any FleetControlServicing)?,
        onSnapshot: (@MainActor @Sendable (FleetAgentSnapshot) -> Void)? = nil
    ) {
        stop()
        agentInfo = nil
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
        imagePreparationGeneration = UUID()
        imagePreparationTask?.cancel()
        imagePreparationTask = nil
        if imagePreparationState.isPreparing {
            imagePreparationState = .idle
        }
        isWatching = false
        reconnectAttempt = 0
        snapshotObserver = nil
    }

    /// Refresh agent handshake metadata without restarting the watch loop.
    @discardableResult
    func getAgentInfo() async -> Bool {
        guard let client = requireClient() else { return false }

        do {
            agentInfo = try await client.fetchAgentInfo()
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
            applySettings(try await client.getSettings())
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
        let updatesVMSettings = update.macosRunnerImage != nil || update.vmMode != nil
        if updatesVMSettings {
            guard vmSettingsAvailability == .available else {
                lastError = "Fleet VM settings are unavailable."
                return false
            }
            guard !imagePreparationState.isPreparing else {
                lastError = "Wait for macOS image preparation to finish before changing VM settings."
                return false
            }
        }

        guard let client = requireClient() else { return false }
        guard !update.isEmpty else {
            return await getSettings()
        }

        return await performAction("update settings") {
            applySettings(try await client.updateSettings(update))
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
        participate: Bool? = nil,
        macosRunnerImage: String? = nil,
        vmMode: FleetVmMode? = nil
    ) async -> Bool {
        await updateSettings(
            FleetSettingsUpdate(
                loadCeiling: loadCeiling,
                memFloorMib: memFloorMib,
                linuxRunnerImage: linuxRunnerImage,
                gateway: gateway,
                dockerMode: dockerMode,
                runnerScript: runnerScript,
                participate: participate,
                macosRunnerImage: macosRunnerImage,
                vmMode: vmMode
            )
        )
    }

    /// Begin preparing the configured macOS runner image through the Agent.
    /// The Agent owns daemon communication; Desktop only consumes this local
    /// Fleet control stream and never manages either process.
    func beginMacOSRunnerImagePreparation() {
        guard !isPerformingAction, imagePreparationTask == nil else { return }
        guard vmSettingsAvailability == .available else {
            imagePreparationState = .failed("Fleet VM settings are unavailable.")
            return
        }
        guard supportsMacOSImagePreparation else {
            imagePreparationState = .failed(
                "This Fleet Agent does not support macOS image preparation."
            )
            return
        }
        guard let reference = settings?.macosRunnerImage?.target else {
            imagePreparationState = .failed("Fleet Agent did not report a macOS runner image.")
            return
        }
        guard let client = requireClient() else {
            imagePreparationState = .failed("Fleet control client is unavailable.")
            return
        }

        let generation = UUID()
        imagePreparationGeneration = generation
        imagePreparationState = .preparing(
            FleetImagePreparationProgress(
                stage: "starting",
                detail: "",
                fraction: 0
            )
        )
        imagePreparationTask = Task { [weak self, client] in
            await self?.runMacOSRunnerImagePreparation(
                client: client,
                generation: generation,
                reference: reference
            )
        }
    }

    private func run(client: any FleetControlServicing, generation: UUID) async {
        await loadInitialState(client: client, generation: generation)
        guard generation == watchGeneration else { return }
        await watchSnapshots(client: client, generation: generation)
    }

    private func runMacOSRunnerImagePreparation(
        client: any FleetControlServicing,
        generation: UUID,
        reference: String
    ) async {
        defer {
            if generation == imagePreparationGeneration {
                imagePreparationTask = nil
            }
        }

        do {
            for try await event in client.prepareImages([.macosRunnerImage]) {
                guard generation == imagePreparationGeneration else { return }
                guard event.kind == .macosRunnerImage else { continue }

                imagePreparationState = .preparing(
                    FleetImagePreparationProgress(
                        stage: event.stage,
                        detail: event.detail,
                        fraction: event.fraction
                    )
                )
            }

            guard generation == imagePreparationGeneration else { return }
            try Task.checkCancellation()
            let refreshedSettings = try await client.getSettings()
            guard generation == imagePreparationGeneration else { return }
            applySettings(refreshedSettings)
            guard refreshedSettings.macosRunnerImage?.current == reference,
                refreshedSettings.macosRunnerImage?.target == reference
            else {
                throw FleetImagePreparationError.targetDidNotConverge(reference)
            }
            imagePreparationState = .completed(reference: reference)
            lastError = nil
        } catch is CancellationError {
            guard generation == imagePreparationGeneration else { return }
            imagePreparationState = .idle
        } catch {
            guard generation == imagePreparationGeneration else { return }
            let message = FleetControlClient.userMessage(for: error)
            Log.fleet.error(
                "Fleet macOS image preparation failed: \(error.localizedDescription, privacy: .private)"
            )
            imagePreparationState = .failed(message)
            lastError = message
        }
    }

    private func loadInitialState(client: any FleetControlServicing, generation: UUID) async {
        do {
            let agentInfo = try await client.fetchAgentInfo()
            let status = try await client.getStatus()
            let settings = try await client.getSettings()
            guard generation == watchGeneration else { return }
            self.agentInfo = agentInfo
            self.status = status
            applySettings(settings)
            lastError = nil
        } catch {
            guard generation == watchGeneration else { return }
            markUnavailable(FleetControlClient.userMessage(for: error))
        }
    }

    private func watchSnapshots(client: any FleetControlServicing, generation: UUID) async {
        while !Task.isCancelled, generation == watchGeneration {
            do {
                if agentInfo == nil || reconnectAttempt > 0 {
                    let agentInfo = try await client.fetchAgentInfo()
                    guard generation == watchGeneration else { return }
                    self.agentInfo = agentInfo
                }
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
        if let settings = snapshot.settings {
            applySettings(settings)
        }
        self.status = Self.status(from: snapshot)
        self.loadState = .ready
        self.lastError = nil
        self.isWatching = true
        self.reconnectAttempt = 0
        snapshotObserver?(snapshot)
    }

    private func refreshAfterMutation(client: any FleetControlServicing) async {
        do {
            status = try await client.getStatus()
            applySettings(try await client.getSettings())
            lastError = nil
        } catch {
            handle(error)
        }
    }

    private func applySettings(_ newSettings: FleetAgentSettings) {
        let previousTarget = settings?.macosRunnerImage?.target
        settings = newSettings

        let newTarget = newSettings.macosRunnerImage?.target
        if previousTarget != newTarget, !imagePreparationState.isPreparing {
            imagePreparationState = .idle
        }

        guard case .completed(let reference) = imagePreparationState else { return }
        guard newSettings.macosRunnerImage?.current == reference,
            newSettings.macosRunnerImage?.target == reference
        else {
            imagePreparationState = .idle
            return
        }
    }

    private func performAction(
        _ label: String,
        operation: () async throws -> Void
    ) async -> Bool {
        guard !isPerformingAction else { return false }

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

    private func requireClient() -> (any FleetControlServicing)? {
        guard let client else {
            markUnavailable("Fleet control client is unavailable.")
            return nil
        }
        return client
    }

    private func handle(_ error: Error) {
        let message = FleetControlClient.userMessage(for: error)
        lastError = message
        if snapshot == nil {
            loadState = .unavailable(message)
        }
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
        case .updating:
            state = .draining
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

    static func resolveVMSettingsAvailability(
        agentInfo: FleetAgentInfo?,
        settings: FleetAgentSettings?,
        loadState: FleetLoadState
    ) -> FleetVMSettingsAvailability {
        switch loadState {
        case .idle, .connecting:
            return .loading
        case .unavailable(let message), .failed(let message):
            return .unavailable(message)
        case .ready:
            break
        }

        guard let agentInfo else {
            return .unavailable("Fleet Agent capability data is unavailable.")
        }
        guard agentInfo.supportsFeature(FleetAgentFeature.vmSettings) else {
            return .unsupported
        }
        guard settings?.vmMode != nil, settings?.macosRunnerImage != nil else {
            return .missingSettings
        }
        return .available
    }
}
