import FleetControlClient
import XCTest
import os

@testable import ArcBox

@MainActor
final class FleetViewModelTests: XCTestCase {
    func testVMSettingsAvailabilityRequiresStableFeatureAndBothFields() {
        let supported = FleetAgentInfo(
            agentVersion: "0.5.0",
            apiVersion: 1,
            features: ["vm-settings"]
        )
        let completeSettings = makeVMSettings()

        XCTAssertEqual(
            FleetViewModel.resolveVMSettingsAvailability(
                agentInfo: supported,
                settings: completeSettings,
                loadState: .connecting
            ),
            .loading
        )
        XCTAssertEqual(
            FleetViewModel.resolveVMSettingsAvailability(
                agentInfo: FleetAgentInfo(
                    agentVersion: "0.4.0",
                    apiVersion: 1,
                    features: []
                ),
                settings: completeSettings,
                loadState: .ready
            ),
            .unsupported
        )
        XCTAssertEqual(
            FleetViewModel.resolveVMSettingsAvailability(
                agentInfo: supported,
                settings: FleetAgentSettings(vmMode: completeSettings.vmMode),
                loadState: .ready
            ),
            .missingSettings
        )
        XCTAssertEqual(
            FleetViewModel.resolveVMSettingsAvailability(
                agentInfo: supported,
                settings: completeSettings,
                loadState: .ready
            ),
            .available
        )
        XCTAssertEqual(
            FleetViewModel.resolveVMSettingsAvailability(
                agentInfo: supported,
                settings: completeSettings,
                loadState: .failed("Watch disconnected.")
            ),
            .unavailable("Watch disconnected.")
        )
    }

    func testVMRestartRequirementSeparatesSettingsFromRuntimeReadiness() {
        let vm = FleetViewModel()
        vm.loadState = .ready
        vm.agentInfo = makeAgentInfo(features: ["vm-settings", "macos-image-prepare"])
        vm.settings = makeVMSettings(
            vmMode: FleetSetting(current: .enabled, target: .disabled)
        )

        XCTAssertTrue(vm.requiresAgentRestartForVM)

        vm.settings = makeVMSettings(
            vmMode: FleetSetting(current: .disabled, target: .enabled)
        )
        XCTAssertTrue(vm.requiresAgentRestartForVM)

        vm.settings = makeVMSettings()
        XCTAssertTrue(vm.requiresAgentRestartForVM)

        vm.agentInfo = makeAgentInfo(
            features: ["vm-settings", "macos-image-prepare", "vm-backend"]
        )
        XCTAssertFalse(vm.requiresAgentRestartForVM)

        vm.agentInfo = makeAgentInfo(features: ["vm-settings", "macos-image-prepare"])
        vm.settings = makeVMSettings(
            vmMode: FleetSetting(current: .disabled, target: .disabled)
        )
        XCTAssertFalse(vm.requiresAgentRestartForVM)

        vm.settings = makeVMSettings(
            image: FleetSetting(current: "tahoe-base", target: "tahoe-next")
        )
        XCTAssertFalse(vm.requiresAgentRestartForVM)
    }

    func testVMRestartRequirementSurvivesDesktopReopenOrExternalPreparation() {
        let vm = FleetViewModel()
        vm.loadState = .ready
        vm.agentInfo = makeAgentInfo(features: ["vm-settings", "macos-image-prepare"])
        vm.settings = makeVMSettings(
            vmMode: FleetSetting(current: .disabled, target: .enabled)
        )

        XCTAssertEqual(vm.imagePreparationState, .idle)
        XCTAssertTrue(vm.requiresAgentRestartForVM)

        vm.settings = makeVMSettings(
            image: FleetSetting(current: "", target: "tahoe-base"),
            vmMode: FleetSetting(current: .disabled, target: .enabled)
        )
        XCTAssertFalse(vm.requiresAgentRestartForVM)
    }

    func testMacOSImagePreparationUsesItsOwnCapability() {
        let vm = FleetViewModel()
        vm.loadState = .ready
        vm.settings = makeVMSettings(
            image: FleetSetting(current: "", target: "tahoe-base")
        )
        vm.agentInfo = makeAgentInfo(features: ["vm-settings"])

        XCTAssertFalse(vm.supportsMacOSImagePreparation)
        XCTAssertFalse(vm.isVMBackendActive)
        XCTAssertEqual(vm.runnerImageReadiness, .hidden)

        vm.agentInfo = makeAgentInfo(
            features: ["vm-settings", "macos-image-prepare", "vm-backend"]
        )

        XCTAssertTrue(vm.supportsMacOSImagePreparation)
        XCTAssertTrue(vm.isVMBackendActive)
        XCTAssertTrue(vm.canBeginMacOSRunnerImagePreparation)
        XCTAssertEqual(vm.runnerImageReadiness, .pending(reference: "tahoe-base"))
    }

    func testRunnerImageReadinessTracksPreparationAndRestartRequirement() {
        let vm = FleetViewModel()
        vm.loadState = .ready
        vm.agentInfo = makeAgentInfo(features: ["vm-settings", "macos-image-prepare"])
        vm.settings = makeVMSettings(
            image: FleetSetting(current: "", target: "tahoe-next")
        )

        let progress = FleetImagePreparationProgress(
            stage: "pulling",
            detail: "Downloading",
            fraction: 0.5
        )
        vm.imagePreparationState = .preparing(progress)
        XCTAssertEqual(vm.runnerImageReadiness, .preparing(progress))

        vm.settings = makeVMSettings(
            image: FleetSetting(current: "tahoe-next", target: "tahoe-next")
        )
        vm.imagePreparationState = .completed(reference: "tahoe-next")
        XCTAssertEqual(vm.runnerImageReadiness, .restartRequired)

        vm.agentInfo = makeAgentInfo(
            features: ["vm-settings", "macos-image-prepare", "vm-backend"]
        )
        XCTAssertEqual(vm.runnerImageReadiness, .completed(reference: "tahoe-next"))
    }

    func testMacOSImagePreparationConvergesAgainstAuthoritativeSettings() async {
        let initial = makeVMSettings(
            image: FleetSetting(current: "", target: "tahoe-next")
        )
        let converged = makeVMSettings(
            image: FleetSetting(current: "tahoe-next", target: "tahoe-next")
        )
        let client = FleetControlStub(
            initialSettings: initial,
            refreshedSettings: converged,
            preparation: .finished([
                FleetImagePreparationEvent(
                    kind: .macosRunnerImage,
                    detail: "downloading",
                    stage: "pulling",
                    fraction: 0.5
                )
            ])
        )
        let vm = FleetViewModel()
        vm.start(client: client)
        await waitUntil { vm.isReady }

        vm.beginMacOSRunnerImagePreparation()
        await waitUntil {
            vm.imagePreparationState == .completed(reference: "tahoe-next")
        }

        XCTAssertEqual(vm.settings, converged)
        XCTAssertNil(vm.lastError)
        vm.stop()
    }

    func testMacOSImagePreparationRejectsNonConvergedSettings() async {
        let pending = makeVMSettings(
            image: FleetSetting(current: "tahoe-base", target: "tahoe-next")
        )
        let client = FleetControlStub(
            initialSettings: pending,
            refreshedSettings: pending,
            preparation: .finished([])
        )
        let vm = FleetViewModel()
        vm.start(client: client)
        await waitUntil { vm.isReady }

        vm.beginMacOSRunnerImagePreparation()
        await waitUntil {
            if case .failed = vm.imagePreparationState { return true }
            return false
        }

        guard case .failed(let message) = vm.imagePreparationState else {
            return XCTFail("Expected image preparation to fail")
        }
        XCTAssertTrue(message.contains("tahoe-next"))
        XCTAssertEqual(vm.lastError, message)
        vm.stop()
    }

    func testStopCancelsMacOSImagePreparation() async {
        let settings = makeVMSettings(
            image: FleetSetting(current: "", target: "tahoe-next")
        )
        let client = FleetControlStub(
            initialSettings: settings,
            refreshedSettings: settings,
            preparation: .suspended
        )
        let vm = FleetViewModel()
        vm.start(client: client)
        await waitUntil { vm.isReady }

        vm.beginMacOSRunnerImagePreparation()
        await waitUntil { client.preparationStarted }
        vm.stop()
        await waitUntil { client.preparationTerminated }

        XCTAssertEqual(vm.imagePreparationState, .idle)
    }

    private func makeAgentInfo(features: [String]) -> FleetAgentInfo {
        FleetAgentInfo(agentVersion: "0.5.0", apiVersion: 1, features: features)
    }

    private func makeVMSettings(
        image: FleetSetting<String> = FleetSetting(current: "tahoe-base", target: "tahoe-base"),
        vmMode: FleetSetting<FleetVmMode> = FleetSetting(current: .auto, target: .auto)
    ) -> FleetAgentSettings {
        FleetAgentSettings(
            macosRunnerImage: image,
            vmMode: vmMode
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Condition was not satisfied before timeout")
    }
}

private final class FleetControlStub: FleetControlServicing, @unchecked Sendable {
    enum Preparation: Sendable {
        case finished([FleetImagePreparationEvent])
        case suspended
    }

    private struct State {
        var settingsReadCount = 0
        var watchContinuation: AsyncThrowingStream<FleetAgentSnapshot, Error>.Continuation?
        var preparationContinuation: AsyncThrowingStream<FleetImagePreparationEvent, Error>.Continuation?
        var preparationStarted = false
        var preparationTerminated = false
    }

    private let initialSettings: FleetAgentSettings
    private let refreshedSettings: FleetAgentSettings
    private let preparation: Preparation
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(
        initialSettings: FleetAgentSettings,
        refreshedSettings: FleetAgentSettings,
        preparation: Preparation
    ) {
        self.initialSettings = initialSettings
        self.refreshedSettings = refreshedSettings
        self.preparation = preparation
    }

    var preparationStarted: Bool {
        state.withLock { $0.preparationStarted }
    }

    var preparationTerminated: Bool {
        state.withLock { $0.preparationTerminated }
    }

    func fetchAgentInfo() async throws -> FleetAgentInfo {
        FleetAgentInfo(
            agentVersion: "test",
            apiVersion: 1,
            features: ["vm-settings", "macos-image-prepare"]
        )
    }

    func getStatus() async throws -> FleetAgentStatus {
        FleetAgentStatus(state: .unenrolled, machineID: nil)
    }

    func watchSnapshots() -> AsyncThrowingStream<FleetAgentSnapshot, Error> {
        AsyncThrowingStream { [self] continuation in
            state.withLock { $0.watchContinuation = continuation }
            continuation.yield(
                FleetAgentSnapshot(
                    enrollment: .unenrolled,
                    machineID: nil,
                    isDraining: false,
                    capabilities: [],
                    inFlightJobs: [],
                    recentVerdicts: [],
                    telemetry: nil,
                    settings: initialSettings
                )
            )
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { $0.watchContinuation = nil }
            }
        }
    }

    func drain() async throws {}
    func resume() async throws {}
    func unenroll() async throws {}

    func prepareImages(
        _ kinds: [FleetImageKind]
    ) -> AsyncThrowingStream<FleetImagePreparationEvent, Error> {
        AsyncThrowingStream { [self] continuation in
            state.withLock { state in
                state.preparationStarted = true
                state.preparationContinuation = continuation
            }
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { state in
                    state.preparationContinuation = nil
                    state.preparationTerminated = true
                }
            }

            if case .finished(let events) = preparation {
                for event in events {
                    continuation.yield(event)
                }
                continuation.finish()
            }
        }
    }

    func getSettings() async throws -> FleetAgentSettings {
        let readCount = state.withLock { state -> Int in
            defer { state.settingsReadCount += 1 }
            return state.settingsReadCount
        }
        return readCount == 0 ? initialSettings : refreshedSettings
    }

    func updateSettings(_ update: FleetSettingsUpdate) async throws -> FleetAgentSettings {
        refreshedSettings
    }
}
