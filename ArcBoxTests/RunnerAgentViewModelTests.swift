import RunnerAgentClient
import XCTest
import os

@testable import ArcBox

@MainActor
final class RunnerAgentViewModelTests: XCTestCase {
    func testVMSettingsAvailabilityRequiresStableFeatureAndBothFields() {
        let supported = RunnerAgentInfo(
            agentVersion: "0.5.0",
            apiVersion: 1,
            features: ["vm-settings"]
        )
        let completeSettings = makeVMSettings()

        XCTAssertEqual(
            RunnerAgentViewModel.resolveVMSettingsAvailability(
                agentInfo: supported,
                settings: completeSettings,
                loadState: .connecting
            ),
            .loading
        )
        XCTAssertEqual(
            RunnerAgentViewModel.resolveVMSettingsAvailability(
                agentInfo: RunnerAgentInfo(
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
            RunnerAgentViewModel.resolveVMSettingsAvailability(
                agentInfo: supported,
                settings: RunnerAgentSettings(vmMode: completeSettings.vmMode),
                loadState: .ready
            ),
            .missingSettings
        )
        XCTAssertEqual(
            RunnerAgentViewModel.resolveVMSettingsAvailability(
                agentInfo: supported,
                settings: completeSettings,
                loadState: .ready
            ),
            .available
        )
        XCTAssertEqual(
            RunnerAgentViewModel.resolveVMSettingsAvailability(
                agentInfo: supported,
                settings: completeSettings,
                loadState: .failed("Watch disconnected.")
            ),
            .unavailable("Watch disconnected.")
        )
    }

    func testVMRestartRequirementSeparatesSettingsFromRuntimeReadiness() {
        let vm = RunnerAgentViewModel()
        vm.loadState = .ready
        vm.agentInfo = makeAgentInfo(features: ["vm-settings", "macos-image-prepare"])
        vm.settings = makeVMSettings(
            vmMode: RunnerSetting(current: .enabled, target: .disabled)
        )

        XCTAssertTrue(vm.requiresAgentRestartForVM)

        vm.settings = makeVMSettings(
            vmMode: RunnerSetting(current: .disabled, target: .enabled)
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
            vmMode: RunnerSetting(current: .disabled, target: .disabled)
        )
        XCTAssertFalse(vm.requiresAgentRestartForVM)

        vm.settings = makeVMSettings(
            image: RunnerSetting(current: "tahoe-base", target: "tahoe-next")
        )
        XCTAssertFalse(vm.requiresAgentRestartForVM)
    }

    func testVMRestartRequirementSurvivesDesktopReopenOrExternalPreparation() {
        let vm = RunnerAgentViewModel()
        vm.loadState = .ready
        vm.agentInfo = makeAgentInfo(features: ["vm-settings", "macos-image-prepare"])
        vm.settings = makeVMSettings(
            vmMode: RunnerSetting(current: .disabled, target: .enabled)
        )

        XCTAssertEqual(vm.imagePreparationState, .idle)
        XCTAssertTrue(vm.requiresAgentRestartForVM)

        vm.settings = makeVMSettings(
            image: RunnerSetting(current: "", target: "tahoe-base"),
            vmMode: RunnerSetting(current: .disabled, target: .enabled)
        )
        XCTAssertFalse(vm.requiresAgentRestartForVM)
    }

    func testMacOSImagePreparationUsesItsOwnCapability() {
        let vm = RunnerAgentViewModel()
        vm.loadState = .ready
        vm.settings = makeVMSettings(
            image: RunnerSetting(current: "", target: "tahoe-base")
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
        let vm = RunnerAgentViewModel()
        vm.loadState = .ready
        vm.agentInfo = makeAgentInfo(features: ["vm-settings", "macos-image-prepare"])
        vm.settings = makeVMSettings(
            image: RunnerSetting(current: "", target: "tahoe-next")
        )

        let progress = RunnerImagePreparationProgress(
            stage: "pulling",
            detail: "Downloading",
            fraction: 0.5
        )
        vm.imagePreparationState = .preparing(progress)
        XCTAssertEqual(vm.runnerImageReadiness, .preparing(progress))

        vm.settings = makeVMSettings(
            image: RunnerSetting(current: "tahoe-next", target: "tahoe-next")
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
            image: RunnerSetting(current: "", target: "tahoe-next")
        )
        let converged = makeVMSettings(
            image: RunnerSetting(current: "tahoe-next", target: "tahoe-next")
        )
        let client = RunnerAgentControlStub(
            initialSettings: initial,
            refreshedSettings: converged,
            preparation: .finished([
                RunnerImagePreparationEvent(
                    kind: .macosRunnerImage,
                    detail: "downloading",
                    stage: "pulling",
                    fraction: 0.5
                )
            ])
        )
        let vm = RunnerAgentViewModel()
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
            image: RunnerSetting(current: "tahoe-base", target: "tahoe-next")
        )
        let client = RunnerAgentControlStub(
            initialSettings: pending,
            refreshedSettings: pending,
            preparation: .finished([])
        )
        let vm = RunnerAgentViewModel()
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
            image: RunnerSetting(current: "", target: "tahoe-next")
        )
        let client = RunnerAgentControlStub(
            initialSettings: settings,
            refreshedSettings: settings,
            preparation: .suspended
        )
        let vm = RunnerAgentViewModel()
        vm.start(client: client)
        await waitUntil { vm.isReady }

        vm.beginMacOSRunnerImagePreparation()
        await waitUntil { client.preparationStarted }
        vm.stop()
        await waitUntil { client.preparationTerminated }

        XCTAssertEqual(vm.imagePreparationState, .idle)
    }

    private func makeAgentInfo(features: [String]) -> RunnerAgentInfo {
        RunnerAgentInfo(agentVersion: "0.5.0", apiVersion: 1, features: features)
    }

    private func makeVMSettings(
        image: RunnerSetting<String> = RunnerSetting(current: "tahoe-base", target: "tahoe-base"),
        vmMode: RunnerSetting<RunnerVmMode> = RunnerSetting(current: .auto, target: .auto)
    ) -> RunnerAgentSettings {
        RunnerAgentSettings(
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

private final class RunnerAgentControlStub: RunnerAgentControlServicing, @unchecked Sendable {
    enum Preparation: Sendable {
        case finished([RunnerImagePreparationEvent])
        case suspended
    }

    private struct State {
        var settingsReadCount = 0
        var watchContinuation: AsyncThrowingStream<RunnerAgentSnapshot, Error>.Continuation?
        var preparationContinuation: AsyncThrowingStream<RunnerImagePreparationEvent, Error>.Continuation?
        var preparationStarted = false
        var preparationTerminated = false
    }

    private let initialSettings: RunnerAgentSettings
    private let refreshedSettings: RunnerAgentSettings
    private let preparation: Preparation
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(
        initialSettings: RunnerAgentSettings,
        refreshedSettings: RunnerAgentSettings,
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

    func fetchAgentInfo() async throws -> RunnerAgentInfo {
        RunnerAgentInfo(
            agentVersion: "test",
            apiVersion: 1,
            features: ["vm-settings", "macos-image-prepare"]
        )
    }

    func getStatus() async throws -> RunnerAgentStatus {
        RunnerAgentStatus(state: .unenrolled, hostID: nil)
    }

    func watchSnapshots() -> AsyncThrowingStream<RunnerAgentSnapshot, Error> {
        AsyncThrowingStream { [self] continuation in
            state.withLock { $0.watchContinuation = continuation }
            continuation.yield(
                RunnerAgentSnapshot(
                    enrollment: .unenrolled,
                    hostID: nil,
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
        _ kinds: [RunnerImageKind]
    ) -> AsyncThrowingStream<RunnerImagePreparationEvent, Error> {
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

    func getSettings() async throws -> RunnerAgentSettings {
        let readCount = state.withLock { state -> Int in
            defer { state.settingsReadCount += 1 }
            return state.settingsReadCount
        }
        return readCount == 0 ? initialSettings : refreshedSettings
    }

    func updateSettings(_ update: RunnerSettingsUpdate) async throws -> RunnerAgentSettings {
        refreshedSettings
    }
}
